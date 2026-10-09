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

    private static func jpeg(_ image: CIImage, options: PhotoOptions, identifier: String?) throws -> Data {
        let crop = FrameGeometry.crop(image.extent.size, aspect: options.aspect)
            .offsetBy(dx: image.extent.minX, dy: image.extent.minY)
        let cropped = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let size = FrameGeometry.outputSize(crop.size, maxEdge: options.resolution.maxEdge)
        let resized = cropped.transformed(by: CGAffineTransform(scaleX: size.width / crop.width, y: size.height / crop.height))
        guard let cgImage = context.createCGImage(resized, from: CGRect(origin: .zero, size: size)) else {
            throw CameraError.message("Could not process the photo frame.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil) else {
            throw CameraError.message("Could not create the photo file.")
        }
        var metadata: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.94,
                                       kCGImagePropertyOrientation as String: 1]
        if let identifier = identifier { metadata[kCGImagePropertyMakerAppleDictionary as String] = ["17": identifier] }
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CameraError.message("Could not save the photo frame.") }
        return data as Data
    }
}
