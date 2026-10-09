import AVFoundation

/// Owned by CameraEngine's serial queue. Copy pixels so capture's pool is never retained.
final class RollingBuffer {
    private(set) var video: [CMSampleBuffer] = []
    private(set) var audio: [CMSampleBuffer] = []
    var duration = 1.5
    var lastTime: CMTime? { return video.last.map { CMSampleBufferGetPresentationTimeStamp($0) } }
    var span: Double {
        guard let first = video.first, let last = lastTime else { return 0 }
        return CMTimeGetSeconds(CMTimeSubtract(last, CMSampleBufferGetPresentationTimeStamp(first)))
    }

    func clear() { video.removeAll(); audio.removeAll() }

    func appendVideo(_ sample: CMSampleBuffer) {
        guard let copy = Self.copyVideo(sample) else { return }
        video.append(copy)
        let now = CMSampleBufferGetPresentationTimeStamp(sample)
        video.removeAll { CMTimeGetSeconds(CMTimeSubtract(now, CMSampleBufferGetPresentationTimeStamp($0))) > duration }
        // A hard ceiling guards against unexpected frame-rate/timestamp behavior.
        if video.count > 25 { video.removeFirst(video.count - 25) }
        audio.removeAll { CMTimeGetSeconds(CMTimeSubtract(now, CMSampleBufferGetPresentationTimeStamp($0))) > duration }
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        audio.append(sample)
        if audio.count > 100 { audio.removeFirst(audio.count - 100) }
    }

    static func copyVideo(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        guard let source = CMSampleBufferGetImageBuffer(sample) else { return nil }
        var destination: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
        guard CVPixelBufferCreate(kCFAllocatorDefault, CVPixelBufferGetWidth(source),
                                  CVPixelBufferGetHeight(source), CVPixelBufferGetPixelFormatType(source),
                                  attributes as CFDictionary, &destination) == kCVReturnSuccess,
              let target = destination else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(target, [])
        defer {
            CVPixelBufferUnlockBaseAddress(target, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        if CVPixelBufferIsPlanar(source) {
            for plane in 0..<CVPixelBufferGetPlaneCount(source) {
                guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dst = CVPixelBufferGetBaseAddressOfPlane(target, plane) else { return nil }
                let srcStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dstStride = CVPixelBufferGetBytesPerRowOfPlane(target, plane)
                for row in 0..<CVPixelBufferGetHeightOfPlane(source, plane) {
                    memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), min(srcStride, dstStride))
                }
            }
        } else {
            guard let src = CVPixelBufferGetBaseAddress(source), let dst = CVPixelBufferGetBaseAddress(target) else { return nil }
            let srcStride = CVPixelBufferGetBytesPerRow(source), dstStride = CVPixelBufferGetBytesPerRow(target)
            for row in 0..<CVPixelBufferGetHeight(source) {
                memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), min(srcStride, dstStride))
            }
        }
        CVBufferPropagateAttachments(source, target)
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: target,
                                                           formatDescriptionOut: &format) == noErr,
              let description = format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sample),
                                        presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
                                        decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: target,
                                                       formatDescription: description, sampleTiming: &timing,
                                                       sampleBufferOut: &result) == noErr else { return nil }
        return result
    }
}
