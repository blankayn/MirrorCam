import UIKit
import Photos
import AVFoundation
import ImageIO

enum MediaKind: String, Codable { case photo, video, motion }

struct MediaItem: Codable {
    let id: String
    let created: Date
    let kind: MediaKind
    var savedToPhotos: Bool
    var directory: URL { return MediaStore.root.appendingPathComponent(id, isDirectory: true) }
    var photoURL: URL? { return kind == .video ? nil : directory.appendingPathComponent("photo.jpg") }
    var videoURL: URL? { return kind == .photo ? nil : directory.appendingPathComponent("video.mp4") }
    var thumbnailURL: URL { return directory.appendingPathComponent("thumbnail.jpg") }
}

final class MediaStore {
    static let shared = MediaStore()
    static var root: URL {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Captures", isDirectory: true)
    }
    private let queue = DispatchQueue(label: "com.mirrorcam.media", qos: .utility)

    func load(_ completion: @escaping ([MediaItem]) -> Void) {
        queue.async {
            let directories = (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
            let items = directories.compactMap { directory -> MediaItem? in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent("item.json")),
                      let item = try? JSONDecoder().decode(MediaItem.self, from: data),
                      UUID(uuidString: item.id) != nil, item.id == directory.lastPathComponent else { return nil }
                return item
            }.sorted { $0.created > $1.created }
            DispatchQueue.main.async { completion(items) }
        }
    }

    func add(photo: Data?, video: URL?, mode: CaptureMode, completion: @escaping (Result<MediaItem, Error>) -> Void) {
        queue.async {
            let kind: MediaKind = mode == .photo ? .photo : (mode == .video ? .video : .motion)
            let item = MediaItem(id: UUID().uuidString, created: Date(), kind: kind, savedToPhotos: false)
            do {
                try FileManager.default.createDirectory(at: item.directory, withIntermediateDirectories: true, attributes: nil)
                if let data = photo, let url = item.photoURL { try data.write(to: url, options: .atomic) }
                if let source = video, let destination = item.videoURL { try FileManager.default.moveItem(at: source, to: destination) }
                var thumbnail: UIImage?
                if let photoURL = item.photoURL { thumbnail = Self.downsample(photoURL, pixels: 240) }
                else if let videoURL = item.videoURL {
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 240, height: 240)
                    if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) { thumbnail = UIImage(cgImage: cg) }
                }
                if let data = thumbnail?.jpegData(compressionQuality: 0.8) { try data.write(to: item.thumbnailURL, options: .atomic) }
                try self.write(item)
                DispatchQueue.main.async { completion(.success(item)) }
            } catch {
                try? FileManager.default.removeItem(at: item.directory)
                if let video = video { try? FileManager.default.removeItem(at: video) }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    static func downsample(_ url: URL, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    func remove(_ item: MediaItem, completion: @escaping (Error?) -> Void) {
        queue.async {
            do {
                try FileManager.default.removeItem(at: item.directory)
                DispatchQueue.main.async { completion(nil) }
            } catch { DispatchQueue.main.async { completion(error) } }
        }
    }

    func saveToPhotos(_ item: MediaItem, completion: @escaping (Result<MediaItem, Error>) -> Void) {
        if item.savedToPhotos { completion(.success(item)); return }
        func save(_ status: PHAuthorizationStatus) {
            var allowed = status == .authorized
            if #available(iOS 14, *) { allowed = allowed || status == .limited }
            guard allowed else {
                DispatchQueue.main.async { completion(.failure(CameraError.message("Photos access is disabled. Enable it in Settings to save. Your capture is still in MirrorCam."))) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                if let url = item.photoURL {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = item.created
                    request.addResource(with: .photo, fileURL: url, options: nil)
                }
                if let url = item.videoURL {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = item.created
                    request.addResource(with: .video, fileURL: url, options: nil)
                }
            }, completionHandler: { success, error in
                self.queue.async {
                    if success {
                        var updated = item; updated.savedToPhotos = true
                        // Keep the success flag even if metadata persistence fails; Photos already saved it.
                        try? self.write(updated)
                        DispatchQueue.main.async { completion(.success(updated)) }
                    } else {
                        DispatchQueue.main.async { completion(.failure(error ?? CameraError.message("Could not save to Photos. Try again."))) }
                    }
                }
            })
        }
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .notDetermined { PHPhotoLibrary.requestAuthorization { save($0) } }
        else { save(status) }
    }

    private func write(_ item: MediaItem) throws {
        try JSONEncoder().encode(item).write(to: item.directory.appendingPathComponent("item.json"), options: .atomic)
    }
}
