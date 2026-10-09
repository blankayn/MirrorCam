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

    // Create the same JPEG pairing tag as PhotoFraming, then let PhotoKit validate the resource pair.
    let photo = movie.deletingPathExtension().appendingPathExtension("jpg")
    let context = CGContext(data: nil, width: Int(expectedSize.width), height: Int(expectedSize.height), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(NSColor.green.cgColor); context.fill(CGRect(origin: .zero, size: expectedSize))
    let destination = CGImageDestinationCreateWithURL(photo as CFURL, kUTTypeJPEG, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyMakerAppleDictionary as String: ["17": id]] as CFDictionary)
    check(CGImageDestinationFinalize(destination), "JPEG pairing metadata written")
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
print("Synthetic media checks passed; iPhone 6 camera and Photos-library tests remain required.")
