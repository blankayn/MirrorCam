import Foundation
import AVFoundation
import Photos
import ImageIO

/// Public ImageIO/AVFoundation metadata, matching the two reference repositories.
enum LivePhotoSupport {
    static let contentIdentifierKey = "com.apple.quicktime.content.identifier"
    static let stillImageTimeKey = "com.apple.quicktime.still-image-time"
    static let makerIdentifierKey = "17"

    struct PairReport {
        let identifier: String
        let duration: Double
        let stillTime: Double
        let videoSize: CGSize
        let photoSize: CGSize
        let hasAudio: Bool
        var summary: String {
            return String(format: "Pair %@\nJPEG %.0f × %.0f; MOV %.0f × %.0f\nClip %.3fs; key photo %.3fs; audio %@",
                identifier, photoSize.width, photoSize.height, videoSize.width, videoSize.height,
                duration, stillTime, hasAudio ? "yes" : "no")
        }
    }

    /// Call on a worker queue. Reads actual resources; does not prove Photos import.
    static func validate(photo: URL, movie: URL) throws -> PairReport {
        guard let source = CGImageSourceCreateWithURL(photo as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) as String? == "public.jpeg",
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let maker = properties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any],
              let identifier = maker[makerIdentifierKey] as? String, !identifier.isEmpty,
              let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber else {
            throw CameraError.message("LIVE JPEG is unreadable or missing its asset identifier.")
        }
        let asset = AVURLAsset(url: movie)
        guard movie.pathExtension.lowercased() == "mov", let video = asset.tracks(withMediaType: .video).first,
              asset.metadata(forFormat: .quickTimeMetadata).contains(where: {
                $0.keySpace == .quickTimeMetadata && $0.key as? String == contentIdentifierKey && $0.stringValue == identifier
              }) else { throw CameraError.message("LIVE JPEG and MOV asset identifiers do not match, or the movie has no video track.") }
        let duration = CMTimeGetSeconds(video.timeRange.duration)
        let videoStart = CMTimeGetSeconds(video.timeRange.start)
        guard duration.isFinite, videoStart.isFinite, duration > 0 else { throw CameraError.message("LIVE movie is empty or has invalid timing.") }
        var stillTime: Double?
        for track in asset.tracks(withMediaType: .metadata) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { continue }
            reader.add(output)
            let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
            guard reader.startReading() else { throw reader.error ?? CameraError.message("Cannot read LIVE timing metadata.") }
            while let group = adaptor.nextTimedMetadataGroup() {
                if group.items.contains(where: {
                    $0.keySpace == .quickTimeMetadata && $0.key as? String == stillImageTimeKey &&
                    $0.dataType == "com.apple.metadata.datatype.int8" &&
                    ($0.numberValue?.intValue == 0 || $0.numberValue?.intValue == -1)
                }) {
                    let time = CMTimeGetSeconds(group.timeRange.start)
                    let span = CMTimeGetSeconds(group.timeRange.duration)
                    guard time.isFinite, span.isFinite, time >= videoStart, time < videoStart + duration, span > 0 else {
                        reader.cancelReading(); throw CameraError.message("LIVE key-photo marker is outside the movie timeline.")
                    }
                    stillTime = time
                }
            }
            guard reader.status == .completed else { throw reader.error ?? CameraError.message("LIVE timing metadata could not be read completely.") }
        }
        guard let time = stillTime else { throw CameraError.message("LIVE movie has no QuickTime still-image-time timed metadata track.") }
        let photoSize = CGSize(width: width.doubleValue, height: height.doubleValue)
        let rect = CGRect(origin: .zero, size: video.naturalSize).applying(video.preferredTransform)
        let videoSize = CGSize(width: abs(rect.width), height: abs(rect.height))
        guard photoSize.width > 0, photoSize.height > 0, videoSize.width > 0, videoSize.height > 0,
              abs(photoSize.width / photoSize.height - videoSize.width / videoSize.height) < 0.02 else {
            throw CameraError.message("LIVE photo and video framing do not match.")
        }
        return PairReport(identifier: identifier, duration: duration, stillTime: time,
            videoSize: videoSize, photoSize: photoSize, hasAudio: !asset.tracks(withMediaType: .audio).isEmpty)
    }
}

/// Main-thread owner; filters degraded responses and times out unsupported playback.
final class LivePhotoPreviewRequest {
    private var request: PHLivePhotoRequestID?
    private var deadline: DispatchWorkItem?
    private var completion: ((Result<PHLivePhoto, Error>) -> Void)?

    init(photo: URL, movie: URL, size: CGSize, completion: @escaping (Result<PHLivePhoto, Error>) -> Void) {
        self.completion = completion
        request = PHLivePhoto.request(withResourceFileURLs: [photo, movie], placeholderImage: nil,
            targetSize: size, contentMode: .aspectFit) { [weak self] livePhoto, info in
                DispatchQueue.main.async {
                    guard let self = self, self.completion != nil else { return }
                    if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true { return }
                    if let livePhoto = livePhoto { self.finish(.success(livePhoto)) }
                    else { self.finish(.failure(info[PHLivePhotoInfoErrorKey] as? Error ??
                        CameraError.message("Live Photo playback is unavailable for this pair on this device."))) }
                }
            }
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(CameraError.message("Live Photo playback timed out. The JPEG and MOV are still in MirrorCam.")))
        }
        deadline = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
    }

    private func finish(_ result: Result<PHLivePhoto, Error>) {
        guard let callback = completion else { return }
        completion = nil; deadline?.cancel(); deadline = nil
        if let request = request { PHLivePhoto.cancelRequest(withRequestID: request) }
        request = nil
        switch result {
        case .success: LivePhotoDiagnostics.record("preview", "PHLivePhoto resource playback loaded")
        case .failure(let error): LivePhotoDiagnostics.record("preview-error", error.localizedDescription)
        }
        callback(result)
    }

    func cancel() {
        completion = nil; deadline?.cancel(); deadline = nil
        if let request = request { PHLivePhoto.cancelRequest(withRequestID: request) }
        request = nil
    }
    deinit { cancel() }
}

/// Bounded on-device log for diagnostics; never records photo pixels or Apple ID.
enum LivePhotoDiagnostics {
    private static let queue = DispatchQueue(label: "com.mirrorcam.live-diagnostics", qos: .utility)
    private static let formatter = ISO8601DateFormatter()
    private static var logURL: URL {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LivePhotoDiagnostics.txt")
    }
    static func record(_ stage: String, _ message: String) {
        NSLog("[MirrorCam LIVE] %@: %@", stage, message)
        queue.async {
            let line = "\(formatter.string(from: Date())) [\(stage)] \(message.replacingOccurrences(of: "\n", with: " | "))\n"
            var existing = (try? Data(contentsOf: logURL)) ?? Data()
            if existing.count > 64 * 1024 { existing = Data(existing.suffix(32 * 1024)) }
            existing.append(Data(line.utf8))
            do {
                try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try existing.write(to: logURL, options: .atomic)
            } catch { NSLog("[MirrorCam LIVE] Cannot write diagnostic log: %@", error.localizedDescription) }
        }
    }
    static func snapshot(_ completion: @escaping (String) -> Void) {
        queue.async {
            let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? "No LIVE diagnostics recorded yet."
            DispatchQueue.main.async { completion(log) }
        }
    }
}
