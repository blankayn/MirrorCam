import Foundation
import CoreImage
import ImageIO
#if canImport(MobileCoreServices)
import MobileCoreServices
#else
import CoreServices
#endif

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
    private static let alignmentKernel = CIColorKernel(source: """
        kernel vec4 registrationBrightness(__sample pixel, float ratio, float limit) {
            vec3 radiance = pow(clamp(pixel.rgb, 0.0, 1.0), vec3(2.2)) / ratio;
            return vec4(pow(clamp(radiance / limit, 0.0, 1.0), vec3(1.0 / 2.2)), pixel.a);
        }
        """)
    private static let kernel = CIColorKernel(source: """
        kernel vec4 mergeHDR(__sample dark, __sample middle, __sample bright, float darkRatio, float brightRatio) {
            vec3 a = pow(clamp(dark.rgb, 0.0, 1.0), vec3(2.2)) / darkRatio;
            vec3 b = pow(clamp(middle.rgb, 0.0, 1.0), vec3(2.2));
            vec3 c = pow(clamp(bright.rgb, 0.0, 1.0), vec3(2.2)) / brightRatio;
            float wa = max(0.002, 1.0 - abs(dot(dark.rgb, vec3(0.2126, 0.7152, 0.0722)) * 2.0 - 1.0));
            float wb = max(0.002, 1.0 - abs(dot(middle.rgb, vec3(0.2126, 0.7152, 0.0722)) * 2.0 - 1.0));
            float wc = max(0.002, 1.0 - abs(dot(bright.rgb, vec3(0.2126, 0.7152, 0.0722)) * 2.0 - 1.0));
            wa *= 1.0 - step(0.995, max(dark.r, max(dark.g, dark.b)));
            wb *= 1.0 - step(0.995, max(middle.r, max(middle.g, middle.b)));
            wc *= 1.0 - step(0.995, max(bright.r, max(bright.g, bright.b)));
            // Reject moving content where non-clipped, exposure-normalized pixels disagree.
            float disagreement = max(length(a - b), length(c - b));
            float motion = smoothstep(0.15, 0.45, disagreement);
            float clipped = step(0.94, max(middle.r, max(middle.g, middle.b)));
            motion *= 1.0 - clipped;
            float total = wa + wb + wc;
            // When every exposure clips, retain the strongest known radiance lower bound.
            vec3 estimate = total > 0.0001 ? (wa * a + wb * b + wc * c) / total : max(a, max(b, c));
            vec3 radiance = mix(estimate, b, motion);
            vec3 mapped = radiance / (vec3(0.6) + radiance);
            return vec4(pow(clamp(mapped, 0.0, 1.0), vec3(1.0 / 2.2)), middle.a);
        }
        """)

    static func merge(_ frames: [HDRFrame], options: PhotoOptions) throws -> Data {
        let sorted = frames.sorted { $0.bias < $1.bias }
        guard sorted.count == 3, sorted[0].bias < sorted[1].bias, sorted[1].bias < sorted[2].bias,
              let kernel = kernel else { throw CameraError.message("HDR merge is unavailable.") }
        let images = try sorted.map { try decode($0.data) }
        let reference = images[1]
        guard images.allSatisfy({ $0.width == reference.width && $0.height == reference.height }) else {
            throw CameraError.message("HDR exposures have different framing.")
        }
        let middle = CIImage(cgImage: reference)
        let ratios: [Double]
        if let a = sorted[0].exposure, let b = sorted[1].exposure, let c = sorted[2].exposure {
            ratios = [a / b, c / b]
        } else { ratios = [pow(2, Double(sorted[0].bias - sorted[1].bias)), pow(2, Double(sorted[2].bias - sorted[1].bias))] }
        guard ratios[0] > 0, ratios[1] > 0, ratios.allSatisfy({ $0.isFinite }) else {
            throw CameraError.message("HDR exposure metadata is invalid.")
        }
        let dark = try align(images[0], to: reference, ratio: ratios[0])
        let bright = try align(images[2], to: reference, ratio: ratios[1])
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

    private static func align(_ image: CGImage, to reference: CGImage, ratio: Double) throws -> CIImage {
        // Registration sees equal exposure and equal clipping limits. Otherwise a bright/dark
        // bracket can be mistaken for movement. Only registration uses these adjusted images.
        let scale = min(1, 160 / CGFloat(max(reference.width, reference.height)))
        let limit = min(1, 1 / ratio)
        let target = try registrationImage(image, ratio: ratio, limit: limit, scale: scale)
        let baseline = try registrationImage(reference, ratio: 1, limit: limit, scale: scale)
        let targetPixels = try luminance(target), referencePixels = try luminance(baseline)
        let width = baseline.width, height = baseline.height
        let maxX = max(1, Int(ceil(Double(width) * 0.04))), maxY = max(1, Int(ceil(Double(height) * 0.04)))
        func score(_ dx: Int, _ dy: Int) -> Double {
            var difference: Double = 0, count = 0
            for y in stride(from: maxY + 1, to: height - maxY - 1, by: 2) {
                for x in stride(from: maxX + 1, to: width - maxX - 1, by: 2) {
                    let value = referencePixels[y * width + x]
                    // Exclude clipped regions with no reliable texture.
                    if value <= 8 || value >= 247 { continue }
                    let other = targetPixels[(y - dy) * width + x - dx]
                    difference += abs(Double(value) - Double(other)); count += 1
                }
            }
            return count > 20 ? difference / Double(count) : 0
        }
        var bestX = 0, bestY = 0, best = score(0, 0)
        for dy in -maxY...maxY {
            for dx in -maxX...maxX {
                let candidate = score(dx, dy)
                if candidate < best - 0.001 { best = candidate; bestX = dx; bestY = dy }
            }
        }
        guard best < 28 else { throw CameraError.message("Hold still: HDR images differ too much to align.") }
        func fraction(_ left: Double, _ center: Double, _ right: Double) -> CGFloat {
            let denominator = left - 2 * center + right
            guard denominator > 0.001 else { return 0 }
            return CGFloat(max(-0.5, min(0.5, 0.5 * (left - right) / denominator)))
        }
        let subX = abs(bestX) < maxX ? fraction(score(bestX - 1, bestY), best, score(bestX + 1, bestY)) : 0
        let subY = abs(bestY) < maxY ? fraction(score(bestX, bestY - 1), best, score(bestX, bestY + 1)) : 0
        // Bitmap rows go down, while Core Image's vertical coordinates go up.
        let transform = CGAffineTransform(translationX: (CGFloat(bestX) + subX) / scale,
            y: -(CGFloat(bestY) + subY) / scale)
        guard abs(transform.tx) <= CGFloat(image.width) * 0.04,
              abs(transform.ty) <= CGFloat(image.height) * 0.04 else {
            throw CameraError.message("Too much camera movement for HDR (translation \(transform.tx), \(transform.ty); exposure ratio \(ratio)).")
        }
        // Keep the center exposure's full frame. Extend only the few edge pixels needed by translation.
        return CIImage(cgImage: image).clampedToExtent().transformed(by: transform)
            .cropped(to: CGRect(x: 0, y: 0, width: reference.width, height: reference.height))
    }

    private static func registrationImage(_ image: CGImage, ratio: Double, limit: Double, scale: CGFloat) throws -> CGImage {
        let small = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let normalized = alignmentKernel?.apply(extent: small.extent, arguments: [small, ratio, limit]),
              let result = context.createCGImage(normalized, from: small.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { throw CameraError.message("HDR alignment could not be prepared.") }
        return result
    }

    private static func luminance(_ image: CGImage) throws -> [UInt8] {
        guard let bitmap = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let memory = bitmap.data else { throw CameraError.message("HDR alignment memory is unavailable.") }
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = memory.assumingMemoryBound(to: UInt8.self)
        return (0..<image.width * image.height).map { index in
            UInt8((Int(bytes[index * 4]) * 54 + Int(bytes[index * 4 + 1]) * 183 + Int(bytes[index * 4 + 2]) * 19) / 256)
        }
    }
}
