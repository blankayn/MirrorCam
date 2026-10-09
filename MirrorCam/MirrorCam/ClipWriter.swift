import AVFoundation
import AudioToolbox

enum CameraError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// All append and finish calls occur on CameraEngine.queue. No second camera session.
final class ClipWriter {
    let url: URL
    let assetIdentifier: String?
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private let start: CMTime
    private let queue: DispatchQueue
    private let maximumPendingFrames: Int
    private let metadata: AVAssetWriterInputMetadataAdaptor?
    private var stillMarker: AVTimedMetadataGroup?
    private var pendingVideo: [CMSampleBuffer] = []
    private var pendingAudio: [CMSampleBuffer] = []
    private var drainScheduled = false
    private var finalizing = false
    private var finishDeadline: TimeInterval = 0
    private var completion: ((Result<URL, Error>) -> Void)?
    private var ended = false
    private var terminalError: Error?
    private(set) var frameCount = 0

    init(url: URL, firstVideo: CMSampleBuffer, hasAudio: Bool, motion: Bool, queue: DispatchQueue,
         aspect: PhotoAspect = .wide, stillTime: CMTime? = nil) throws {
        self.url = url
        self.queue = queue
        maximumPendingFrames = motion ? 64 : 8
        start = CMSampleBufferGetPresentationTimeStamp(firstVideo)
        guard let pixels = CMSampleBufferGetImageBuffer(firstVideo) else {
            throw CameraError.message("The camera did not provide a video frame.")
        }
        writer = try AVAssetWriter(outputURL: url, fileType: motion ? .mov : .mp4)
        assetIdentifier = motion ? UUID().uuidString : nil
        let sourceSize = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))
        let size = FrameGeometry.outputSize(FrameGeometry.crop(sourceSize, aspect: aspect).size, maxEdge: nil)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: motion ? 1_500_000 : 4_000_000,
                AVVideoExpectedSourceFrameRateKey: motion ? 15 : 30,
                AVVideoMaxKeyFrameIntervalKey: motion ? 15 : 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel
            ]
        ]
        video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw CameraError.message("H.264 video encoding is unavailable.") }
        writer.add(video)
        if hasAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CameraError.message("Audio encoding is unavailable.") }
            writer.add(input)
            audio = input
        } else { audio = nil }
        if let identifier = assetIdentifier, let stillTime = stillTime {
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = "com.apple.quicktime.content.identifier" as NSString
            item.value = identifier as NSString
            item.dataType = "com.apple.metadata.datatype.UTF-8"
            writer.metadata = [item]
            let spec: [String: Any] = [
                kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
                kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8"
            ]
            var description: CMFormatDescription?
            let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault,
                metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [spec] as CFArray,
                formatDescriptionOut: &description)
            guard status == noErr, let hint = description else { throw CameraError.message("Cannot create Live Photo timing metadata.") }
            let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: hint)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CameraError.message("Live Photo metadata is unavailable.") }
            writer.add(input)
            metadata = AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
            let marker = AVMutableMetadataItem()
            marker.keySpace = .quickTimeMetadata
            marker.key = "com.apple.quicktime.still-image-time" as NSString
            marker.value = NSNumber(value: Int8(0))
            marker.dataType = "com.apple.metadata.datatype.int8"
            // Metadata adaptor timestamps use the movie timeline, unlike source sample timestamps.
            stillMarker = AVTimedMetadataGroup(items: [marker], timeRange: CMTimeRange(start: CMTimeSubtract(stillTime, start), duration: CMTime(value: 1, timescale: 15)))
        } else { metadata = nil }
        guard writer.startWriting() else { throw writer.error ?? CameraError.message("Cannot start recording.") }
        writer.startSession(atSourceTime: start)
    }

    func append(_ sample: CMSampleBuffer, isVideo: Bool) throws {
        if let error = terminalError { throw error }
        guard !ended else { return }
        if writer.status == .failed { throw writer.error ?? CameraError.message("Recording failed.") }
        guard writer.status == .writing,
              CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), start) >= 0 else { return }
        guard let input = isVideo ? video : audio else { return }
        let empty = isVideo ? pendingVideo.isEmpty : pendingAudio.isEmpty
        if empty && input.isReadyForMoreMediaData {
            guard input.append(sample) else { throw writer.error ?? CameraError.message("Cannot encode this frame.") }
            if isVideo { frameCount += 1 }
        } else if isVideo {
            // Preserve the pre-roll during encoder startup; never retain capture's pixel pool.
            if let copy = RollingBuffer.copyVideo(sample) {
                if pendingVideo.count >= maximumPendingFrames { pendingVideo.removeFirst() }
                pendingVideo.append(copy)
            }
        } else {
            if pendingAudio.count >= 150 { pendingAudio.removeFirst() }
            pendingAudio.append(sample)
        }
        drain()
    }

    func finish(_ completion: @escaping (Result<URL, Error>) -> Void) {
        if let error = terminalError { completion(.failure(error)); return }
        guard !ended else { return }
        ended = true
        self.completion = completion
        finishDeadline = ProcessInfo.processInfo.systemUptime + 10
        drain()
    }

    private func drain() {
        guard !finalizing else { return }
        guard writer.status == .writing else {
            fail(writer.error ?? CameraError.message("Recording failed.")); return
        }
        if let marker = stillMarker, let metadata = metadata, metadata.assetWriterInput.isReadyForMoreMediaData {
            guard metadata.append(marker) else { fail(writer.error ?? CameraError.message("Cannot write Live Photo timing.")); return }
            stillMarker = nil
        }
        while !pendingVideo.isEmpty && video.isReadyForMoreMediaData {
            guard video.append(pendingVideo.removeFirst()) else { fail(writer.error ?? CameraError.message("Video encoding failed.")); return }
            frameCount += 1
        }
        if let audio = audio {
            while !pendingAudio.isEmpty && audio.isReadyForMoreMediaData {
                guard audio.append(pendingAudio.removeFirst()) else { fail(writer.error ?? CameraError.message("Audio encoding failed.")); return }
            }
        }
        if !pendingVideo.isEmpty || !pendingAudio.isEmpty || stillMarker != nil {
            if ended && ProcessInfo.processInfo.systemUptime > finishDeadline { fail(CameraError.message("The encoder timed out.")); return }
            if !drainScheduled {
                drainScheduled = true
                queue.asyncAfter(deadline: .now() + 0.01) { [self] in
                    drainScheduled = false; drain()
                }
            }
            return
        }
        guard ended, let completion = completion else { return }
        finalizing = true
        self.completion = nil
        guard frameCount > 0, writer.status == .writing else {
            let error = writer.error ?? CameraError.message("No video frames were recorded.")
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            completion(.failure(error))
            return
        }
        video.markAsFinished(); audio?.markAsFinished(); metadata?.assetWriterInput.markAsFinished()
        writer.finishWriting { [self] in
            if writer.status == .completed { completion(.success(url)) }
            else {
                try? FileManager.default.removeItem(at: url)
                completion(.failure(writer.error ?? CameraError.message("Could not finish recording.")))
            }
        }
    }

    private func fail(_ error: Error) {
        terminalError = error
        finalizing = true
        writer.cancelWriting(); pendingVideo.removeAll(); pendingAudio.removeAll()
        try? FileManager.default.removeItem(at: url)
        completion?(.failure(error)); completion = nil
    }

    func cancel() {
        guard !finalizing else { return }
        ended = true; finalizing = true
        writer.cancelWriting()
        pendingVideo.removeAll(); pendingAudio.removeAll()
        try? FileManager.default.removeItem(at: url)
        completion?(.failure(CameraError.message("Recording cancelled."))); completion = nil
    }
}
