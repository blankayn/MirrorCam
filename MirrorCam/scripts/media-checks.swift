// Runs the app's geometry, rolling-buffer and clip-writer code on the cloud Mac.
// Synthetic media checks do not replace capture tests on an iPhone 6.
import AppKit
import Photos
import ImageIO
import CoreServices

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    print("PASS: \(message)")
    fflush(stdout)
}

for size in [CGSize(width: 1200, height: 1600), CGSize(width: 1600, height: 1200)] {
    for aspect in PhotoAspect.allCases {
        let crop = FrameGeometry.crop(size, aspect: aspect)
        let ratio = size.width > size.height ? aspect.landscapeRatio : aspect.portraitRatio
        check(abs(crop.width / crop.height - ratio) < 0.0001, "Aspect ratio \(aspect.title), \(size)")
        check(abs(crop.midX - size.width / 2) < 0.0001 && abs(crop.midY - size.height / 2) < 0.0001, "Crop stays centered")
        check(CGRect(origin: .zero, size: size).contains(crop), "Crop stays inside sensor frame")
        for resolution in PhotoResolution.allCases {
            let output = FrameGeometry.outputSize(crop.size, maxEdge: resolution.maxEdge)
            check(output.width <= crop.width && output.height <= crop.height, "No resolution upscaling")
            check(Int(output.width) % 2 == 0 && Int(output.height) % 2 == 0, "Even encoder dimensions")
        }
    }
}

func makeSample(_ index: Int) throws -> CMSampleBuffer {
    var pixels: CVPixelBuffer?
    let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, 480, 640, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixels) == noErr,
          let image = pixels else { throw CameraError.message("Synthetic pixels failed") }
    CVPixelBufferLockBaseAddress(image, [])
    memset(CVPixelBufferGetBaseAddress(image)!, Int32(32 + index * 4), CVPixelBufferGetDataSize(image))
    CVPixelBufferUnlockBaseAddress(image, [])
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 15),
        presentationTimeStamp: CMTime(value: Int64(1500 + index), timescale: 15), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: image,
        formatDescription: format!, sampleTiming: &timing, sampleBufferOut: &sample)
    guard let result = sample else { throw CameraError.message("Synthetic sample failed") }
    return result
}

let samples = try (0..<45).map(makeSample)
let rolling = RollingBuffer()
for sample in samples { rolling.appendVideo(sample) }
check(rolling.video.count <= 25 && rolling.span <= 1.5, "Rolling buffer is bounded")
check(rolling.span > 1.3, "Rolling buffer retains the lead-in")
let work = DispatchQueue(label: "MirrorCam.media-check")

let referenceSize = CGSize(width: 1200, height: 1600)
let referenceContext = CGContext(data: nil, width: 1200, height: 1600, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
referenceContext.setFillColor(NSColor.red.cgColor); referenceContext.fill(CGRect(x: 0, y: 0, width: 600, height: 1600))
referenceContext.setFillColor(NSColor.blue.cgColor); referenceContext.fill(CGRect(x: 600, y: 0, width: 600, height: 1600))
let referenceImage = referenceContext.makeImage()!
for orientation in [1, 2, 6, 8] {
    let original = NSMutableData()
    let jpeg = CGImageDestinationCreateWithData(original, kUTTypeJPEG, 1, nil)!
    CGImageDestinationAddImage(jpeg, referenceImage, [kCGImagePropertyOrientation as String: orientation] as CFDictionary)
    check(CGImageDestinationFinalize(jpeg), "Reference JPEG generated")
    for aspect in PhotoAspect.allCases {
        for resolution in PhotoResolution.allCases {
            let data = try PhotoFraming.process(original as Data, options: PhotoOptions(aspect: aspect, resolution: resolution))
            let source = CGImageSourceCreateWithData(data as CFData, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let sourceSize = orientation >= 5 ? CGSize(width: 1600, height: 1200) : referenceSize
            let expected = FrameGeometry.outputSize(FrameGeometry.crop(sourceSize, aspect: aspect).size, maxEdge: resolution.maxEdge)
            check(CGSize(width: image.width, height: image.height) == expected, "Processed JPEG framing, resolution and orientation \(orientation)")
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
            check((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue == 1, "Saved JPEG pixels are upright")
            if orientation == 2 && aspect == .full && resolution == .maximum {
                let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
                bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let bytes = bitmap.data!.assumingMemoryBound(to: UInt8.self)
                let offset = (image.height / 2 * image.width + image.width / 4) * 4
                check(bytes[offset + 2] > bytes[offset] + 50, "Mirrored JPEG metadata is normalized into mirrored pixels")
            }
        }
    }
}

for aspect in PhotoAspect.allCases {
    let movie = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/check-\(aspect.rawValue).mov")
    try? FileManager.default.removeItem(at: movie)
    let marker = CMSampleBufferGetPresentationTimeStamp(samples[22])
    let clip = try ClipWriter(url: movie, firstVideo: samples[0], hasAudio: false, motion: true, queue: work, aspect: aspect, stillTime: marker)
    let semaphore = DispatchSemaphore(value: 0)
    var finishResult: Result<URL, Error>?
    work.async {
        do {
            for sample in samples { try clip.append(sample, isVideo: true) }
            clip.finish { result in finishResult = result; semaphore.signal() }
        } catch { finishResult = .failure(error); semaphore.signal() }
    }
    check(semaphore.wait(timeout: .now() + 20) == .success, "Writer finalizes without a deadlock")
    _ = try finishResult!.get()
    let asset = AVURLAsset(url: movie)
    let video = asset.tracks(withMediaType: .video).first!
    let expectedSize = FrameGeometry.outputSize(FrameGeometry.crop(CGSize(width: 480, height: 640), aspect: aspect).size, maxEdge: nil)
    check(video.naturalSize == expectedSize, "LIVE video uses chosen frame dimensions")
    check(abs(CMTimeGetSeconds(asset.duration) - 3) < 0.1, "LIVE clip duration is about three seconds")
    let id = clip.assetIdentifier!
    check(asset.metadata.contains { $0.key as? String == "com.apple.quicktime.content.identifier" && $0.stringValue == id }, "QuickTime pairing identifier survives encoding")
    let metadataTrack = asset.tracks(withMediaType: .metadata).first!
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
    let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
    reader.add(output); check(reader.startReading(), "Timed metadata reader starts")
    var foundMarker: CMTime?
    while let group = adaptor.nextTimedMetadataGroup() {
        if group.items.contains(where: { $0.key as? String == "com.apple.quicktime.still-image-time" }) { foundMarker = group.timeRange.start; break }
    }
    check(foundMarker != nil, "Key-photo metadata is readable")
    let actualMarker = CMTimeGetSeconds(foundMarker!)
    print("Key photo time: \(actualMarker), expected \(22.0 / 15.0)"); fflush(stdout)
    check(abs(actualMarker - 22.0 / 15.0) < 0.01, "Key-photo timing is relative to the clip start")
    reader.cancelReading()

    // Use the app's actual key-photo encoder, then let PhotoKit validate the resource pair.
    let photo = movie.deletingPathExtension().appendingPathExtension("jpg")
    let options = PhotoOptions(aspect: aspect, resolution: .maximum)
    let photoData = try PhotoFraming.still(CMSampleBufferGetImageBuffer(samples[22])!, options: options, identifier: id)
    try photoData.write(to: photo)
    let imageSource = CGImageSourceCreateWithData(photoData as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)! as NSDictionary
    let maker = properties[kCGImagePropertyMakerAppleDictionary] as! NSDictionary
    check(maker["17"] as? String == id, "JPEG and MOV share the pairing identifier")
    let encodedImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
    check(CGSize(width: encodedImage.width, height: encodedImage.height) == expectedSize, "LIVE key photo uses the same frame as its video")
    for resolution in PhotoResolution.allCases {
        let data = try PhotoFraming.process(photoData, options: PhotoOptions(aspect: aspect, resolution: resolution))
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let expected = FrameGeometry.outputSize(expectedSize, maxEdge: resolution.maxEdge)
        check(CGSize(width: image.width, height: image.height) == expected, "Photo resolution changes preserve framing and do not upscale")
    }
    var loaded = false, liveValid = false
    _ = PHLivePhoto.request(withResourceFileURLs: [photo, movie], placeholderImage: nil, targetSize: CGSize(width: 240, height: 320), contentMode: .aspectFit) { livePhoto, info in
        guard !(info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false) else { return }
        liveValid = livePhoto != nil; loaded = true
        if livePhoto == nil { print("PhotoKit validation result: \(info)") }
    }
    let deadline = Date().addingTimeInterval(20)
    while !loaded && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    check(loaded && liveValid, "PhotoKit recognizes \(aspect.title) resources as one Live Photo")
}
// Exercise the actual three-exposure HDR merger, including clipping and mirrored metadata.
func hdrFixture(bias: Float, orientation: Int = 1, width: Int = 320, height: Int = 240, shift: Int = 0) -> Data {
    let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    let pixels = bitmap.data!.assumingMemoryBound(to: UInt8.self)
    let exposure = pow(2.0, Double(bias))
    for y in 0..<height {
        for x in 0..<width {
            let sourceX = max(0, min(width - 1, x - shift))
            let band = min(3, sourceX * 4 / width)
            let base = [0.008, 0.12, 1.8, 3.0][band]
            // Asymmetric detail avoids the many equivalent shifts of a periodic checkerboard.
            let hash = ((sourceX / 13 * 73856093) ^ (y / 11 * 19349663)) & 255
            let texture = 0.76 + 0.24 * Double(hash) / 255
            let value = UInt8(pow(min(1, base * texture * exposure), 1 / 2.2) * 255)
            let index = (y * width + x) * 4
            pixels[index] = value; pixels[index + 1] = value; pixels[index + 2] = value; pixels[index + 3] = 255
        }
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil)!
    CGImageDestinationAddImage(destination, bitmap.makeImage()!, [kCGImagePropertyOrientation: orientation,
        kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
    check(CGImageDestinationFinalize(destination), "HDR fixture JPEG encoded")
    return data as Data
}

func hdrPixel(_ data: Data, xFraction: Double) -> Int {
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
    let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Int(bitmap.data!.assumingMemoryBound(to: UInt8.self)[(image.height / 2 * image.width + Int(Double(image.width) * xFraction)) * 4])
}

let hdrFrames = [-1.5, 0, 1.5].map { bias -> HDRFrame in
    let data = hdrFixture(bias: Float(bias))
    return HDRFrame(data: data, bias: Float(bias), metadata: [kCGImagePropertyExifDictionary as String:
        [kCGImagePropertyExifExposureTime as String: 0.01 * pow(2, bias), kCGImagePropertyExifISOSpeedRatings as String: [100], kCGImagePropertyExifFNumber as String: 2.0]])
}
check(abs(hdrFrames[0].exposure! / hdrFrames[1].exposure! - pow(2, -1.5)) < 0.00001, "HDR uses actual EXIF exposure ratios")
let hdrData = try HDRProcessor.merge(hdrFrames, options: PhotoOptions())
let middleData = hdrFrames[1].data
check(hdrPixel(middleData, xFraction: 0.875) == hdrPixel(middleData, xFraction: 0.625), "Reference photo loses detail in clipped highlights")
check(hdrPixel(hdrData, xFraction: 0.875) > hdrPixel(hdrData, xFraction: 0.625) + 5, "HDR recovers detail from darker exposure in clipped highlights")
check(hdrPixel(hdrData, xFraction: 0.125) > hdrPixel(middleData, xFraction: 0.125), "HDR tone mapping lifts shadow detail")
let translatedFrames = [HDRFrame(data: hdrFixture(bias: -1.5, shift: 8), bias: -1.5), hdrFrames[1], hdrFrames[2]]
let translatedHDR = try HDRProcessor.merge(translatedFrames, options: PhotoOptions())
check(abs(hdrPixel(translatedHDR, xFraction: 0.7625) - hdrPixel(hdrData, xFraction: 0.7625)) < 6,
    "HDR translation aligns the outer exposure to the center frame")
for aspect in PhotoAspect.allCases {
    let data = try HDRProcessor.merge(hdrFrames, options: PhotoOptions(aspect: aspect, resolution: .maximum))
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
    let crop = FrameGeometry.crop(CGSize(width: 320, height: 240), aspect: aspect)
    let size = FrameGeometry.outputSize(crop.size, maxEdge: nil)
    check(CGSize(width: image.width, height: image.height) == size, "HDR preserves selected framing without added zoom")
}
let mirrorFrames = [-1.5, 0, 1.5].map { HDRFrame(data: hdrFixture(bias: Float($0), orientation: 2), bias: Float($0)) }
let mirroredHDR = try HDRProcessor.merge(mirrorFrames, options: PhotoOptions())
check(hdrPixel(mirroredHDR, xFraction: 0.125) > hdrPixel(mirroredHDR, xFraction: 0.875) + 80, "HDR normalizes mirrored JPEG orientation")
do {
    _ = try HDRProcessor.merge(Array(hdrFrames.prefix(2)), options: PhotoOptions())
    fatalError("HDR accepted an incomplete bracket")
} catch { check(true, "Incomplete HDR brackets reject for regular-photo fallback") }
let oversized = [-1.5, 0, 1.5].map { HDRFrame(data: hdrFixture(bias: Float($0), width: 1800, height: 1350), bias: Float($0)) }
let limitedHDR = try HDRProcessor.merge(oversized, options: PhotoOptions())
let limitedImage = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(limitedHDR as CFData, nil)!, 0, nil)!
check(limitedImage.width == 1600 && limitedImage.height == 1200, "HDR decode and output are bounded to 1600 pixels")
print("Synthetic media checks passed; iPhone 6 camera and Photos-library tests remain required.")
