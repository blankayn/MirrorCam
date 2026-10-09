import Foundation
import CoreImage
import ImageIO
import Vision

struct HDRFrame {
    let data: Data
    let bias: Float
    let exposure: Double?

    init(data: Data, bias: Float, metadata: [String: Any] = [:]) {
        self.data = data; self.bias = bias
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let duration = (exif?[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
        let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
        let aperture = (exif?[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue ?? 1
        if let duration = duration, let iso = iso, duration > 0, iso > 0, aperture > 0 {
            exposure = duration * iso / (aperture * aperture)
        } else { exposure = nil }
    }
}

enum HDRProcessor {
    // Bound decoded images before merging: three 1600px frames, rather than three full 8MP images.
    static let maxEdge = 1600
    private static let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    private static let kernel = CIColorKernel(source: """
        kernel vec4 mergeHDR(__sample dark, __sample middle, __sample bright, float darkRatio, float brightRatio) {
            vec3 a = pow(clamp(dark.rgb, 0.0, 1.0), vec3(2.2)) / darkRatio;
            vec3 b = pow(clamp(middle.rgb, 0.0, 1.0), vec3(2.2));
            vec3 c = pow(clamp(bright.rgb, 0.0, 1.0), vec3(2.2)) / brightRatio;
            float wa = max(0.002, 1.0 - abs(dot(dark.rgb, vec3(0.2126, 0.7152, 0.0722)) * 2.0 - 1.0));
            float wb = max(0.002, 1.0 - abs(dot(middle.rgb, vec3(0.2126, 0.7152, 0.0722)) * 2.0 - 1.0));
            float wc = max(0.002, 1.0 - abs(dot(bright.rgb, vec3(0.2126, 0.7152, 0.0722)) * 2.0 - 1.0));
            // Reject moving content where non-clipped, exposure-normalized pixels disagree.
            float disagreement = max(length(a - b), length(c - b));
            float motion = smoothstep(0.15, 0.45, disagreement);
            float clipped = step(0.94, max(middle.r, max(middle.g, middle.b)));
            motion *= 1.0 - clipped;
            vec3 radiance = mix((wa * a + wb * b + wc * c) / (wa + wb + wc), b, motion);
            vec3 mapped = radiance / (vec3(0.6) + radiance);
            return vec4(pow(clamp(mapped, 0.0, 1.0), vec3(1.0 / 2.2)), middle.a);
        }
        """)

    static func merge(_ frames: [HDRFrame], options: PhotoOptions) throws -> Data {
        let sorted = frames.sorted { $0.bias < $1.bias }
        guard sorted.count == 3, let kernel = kernel else { throw CameraError.message("HDR merge is unavailable.") }
        let images = try sorted.map { try decode($0.data) }
        let reference = images[1]
        guard images.allSatisfy({ $0.width == reference.width && $0.height == reference.height }) else {
            throw CameraError.message("HDR exposures have different framing.")
        }
        let middle = CIImage(cgImage: reference)
        let dark = try align(images[0], to: reference)
        let bright = try align(images[2], to: reference)
        let ratios: [Double]
        if let a = sorted[0].exposure, let b = sorted[1].exposure, let c = sorted[2].exposure {
            ratios = [a / b, c / b]
        } else { ratios = [pow(2, Double(sorted[0].bias - sorted[1].bias)), pow(2, Double(sorted[2].bias - sorted[1].bias))] }
        guard ratios[0] > 0, ratios[1] > 0, ratios.allSatisfy({ $0.isFinite }) else {
            throw CameraError.message("HDR exposure metadata is invalid.")
        }
        // Samples use sRGB values; explicit null working space avoids applying the gamma conversion twice.
        guard let merged = kernel.apply(extent: middle.extent, arguments: [dark, middle, bright, ratios[0], ratios[1]]),
              let cgImage = context.createCGImage(merged, from: middle.extent, format: .RGBA8,
                  colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { throw CameraError.message("HDR could not be rendered.") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil) else { throw CameraError.message("HDR file could not be created.") }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality as String: 0.94,
            kCGImagePropertyOrientation as String: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CameraError.message("HDR file could not be saved.") }
        return try PhotoFraming.process(data as Data, options: options)
    }

    private static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw CameraError.message("HDR exposure could not be decoded.") }
        return image
    }

    private static func align(_ image: CGImage, to reference: CGImage) throws -> CIImage {
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: image, options: [:])
        request.usesCPUOnly = true
        try VNImageRequestHandler(cgImage: reference, options: [:]).perform([request])
        guard let result = request.results?.first as? VNImageTranslationAlignmentObservation else {
            throw CameraError.message("Hold still: HDR exposures could not be aligned.")
        }
        let transform = result.alignmentTransform
        guard abs(transform.tx) <= CGFloat(image.width) * 0.04,
              abs(transform.ty) <= CGFloat(image.height) * 0.04 else { throw CameraError.message("Too much camera movement for HDR.") }
        // Keep the center exposure's full frame. Extend only the few edge pixels needed by translation.
        return CIImage(cgImage: image).clampedToExtent().transformed(by: transform)
            .cropped(to: CGRect(x: 0, y: 0, width: reference.width, height: reference.height))
    }
}
