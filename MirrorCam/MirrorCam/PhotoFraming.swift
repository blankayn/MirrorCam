import Foundation
import CoreImage
import ImageIO
#if canImport(MobileCoreServices)
import MobileCoreServices
#else
import CoreServices
#endif

enum PhotoFraming {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func process(_ data: Data, options: PhotoOptions) throws -> Data {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw CameraError.message("Could not decode the captured photo.")
        }
        return try jpeg(image, options: options, identifier: nil)
    }

    static func still(_ pixels: CVPixelBuffer, options: PhotoOptions, identifier: String?) throws -> Data {
        // The capture connection already physically rotates and mirrors these pixels.
        return try jpeg(CIImage(cvPixelBuffer: pixels), options: options, identifier: identifier)
    }

    static func editedPhoto(_ url: URL, flipped: Bool) throws -> Data {
        // Decode at a bounded size before processing large imported images on iPhone 6.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CameraError.message("Could not open this photo.") }
        let image = CIImage(cgImage: pixels)
        let result = flipped ? image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: image.extent.width, ty: 0)) : image
        guard let output = context.createCGImage(result, from: image.extent) else {
            throw CameraError.message("Could not flip this photo.")
        }
        return try encode(output, identifier: nil)
    }

    private static func jpeg(_ image: CIImage, options: PhotoOptions, identifier: String?) throws -> Data {
        let crop = FrameGeometry.crop(image.extent.size, aspect: options.aspect)
            .offsetBy(dx: image.extent.minX, dy: image.extent.minY)
        let cropped = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let size = FrameGeometry.outputSize(crop.size, maxEdge: options.resolution.maxEdge)
        let resized = cropped.transformed(by: CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
        guard let cgImage = context.createCGImage(resized, from: CGRect(origin: .zero, size: size)) else {
            throw CameraError.message("Could not process the photo frame.")
        }
        return try encode(cgImage, identifier: identifier)
    }

    private static func encode(_ cgImage: CGImage, identifier: String?) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil) else {
            throw CameraError.message("Could not create the photo file.")
        }
        var metadata: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.94,
                                       kCGImagePropertyOrientation as String: 1]
        if let identifier = identifier { metadata[kCGImagePropertyMakerAppleDictionary as String] = [LivePhotoSupport.makerIdentifierKey: identifier] }
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CameraError.message("Could not save the photo frame.") }
        return data as Data
    }
}
