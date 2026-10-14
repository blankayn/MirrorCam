import UIKit
import Photos
import AVFoundation
import ImageIO

enum MediaKind: String, Codable { case photo, video, motion, livePhoto }

struct MediaItem: Codable {
    let id: String
    let created: Date
    let kind: MediaKind
    var savedToPhotos: Bool
    // Optional fields keep old captures' JSON readable after an update.
    var photosAssetIdentifier: String? = nil
    var livePhotoVerified: Bool? = nil
    var savedSeparately: Bool? = nil
    var photosVerificationMessage: String? = nil
    var directory: URL { return MediaStore.root.appendingPathComponent(id, isDirectory: true) }
    var photoURL: URL? { return kind == .video ? nil : directory.appendingPathComponent("photo.jpg") }
    var videoURL: URL? { return kind == .photo ? nil : directory.appendingPathComponent(kind == .livePhoto ? "video.mov" : "video.mp4") }
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
            let kind: MediaKind = mode == .photo ? .photo : (mode == .video ? .video : .livePhoto)
            let item = MediaItem(id: UUID().uuidString, created: Date(), kind: kind, savedToPhotos: false)
            do {
                try FileManager.default.createDirectory(at: item.directory, withIntermediateDirectories: true, attributes: nil)
                if let data = photo, let url = item.photoURL { try data.write(to: url, options: .atomic) }
                if let source = video, let destination = item.videoURL { try FileManager.default.moveItem(at: source, to: destination) }
                if kind == .livePhoto, let photo = item.photoURL, let movie = item.videoURL {
                    let report = try LivePhotoSupport.validate(photo: photo, movie: movie)
                    LivePhotoDiagnostics.record("pair-created", report.summary)
                }
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
                if kind == .livePhoto { LivePhotoDiagnostics.record("pair-error", error.localizedDescription) }
                try? FileManager.default.removeItem(at: item.directory)
                if let video = video { try? FileManager.default.removeItem(at: video) }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func addEditedPhoto(from url: URL, flipped: Bool, completion: @escaping (Result<MediaItem, Error>) -> Void) {
        queue.async {
            autoreleasepool {
                do {
                    let data = try PhotoFraming.editedPhoto(url, flipped: flipped)
                    self.add(photo: data, video: nil, mode: .photo, completion: completion)
                } catch { DispatchQueue.main.async { completion(.failure(error)) } }
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

    func saveToPhotos(_ item: MediaItem, separate: Bool = false, completion: @escaping (Result<MediaItem, Error>) -> Void) {
        if item.savedToPhotos { completion(.success(item)); return }
        func save(_ status: PHAuthorizationStatus) {
            var allowed = status == .authorized
            if #available(iOS 14, *) { allowed = allowed || status == .limited }
            guard allowed else {
                LivePhotoDiagnostics.record("photos-permission", "Photos access denied or restricted; local capture retained")
                DispatchQueue.main.async { completion(.failure(CameraError.message("Photos access is disabled. Enable it in Settings to save. Your capture is still in MirrorCam."))) }
                return
            }
            self.queue.async {
                if item.kind == .livePhoto && !separate {
                    do {
                        guard let photo = item.photoURL, let movie = item.videoURL else { throw CameraError.message("LIVE resources are missing.") }
                        let report = try LivePhotoSupport.validate(photo: photo, movie: movie)
                        LivePhotoDiagnostics.record("import-start", report.summary)
                    } catch {
                        LivePhotoDiagnostics.record("import-preflight-error", error.localizedDescription)
                        DispatchQueue.main.async { completion(.failure(error)) }; return
                    }
                }
                self.performPhotosSave(item, separate: separate, completion: completion)
            }
        }
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .notDetermined { PHPhotoLibrary.requestAuthorization { save($0) } }
        else { save(status) }
    }

    private func performPhotosSave(_ item: MediaItem, separate: Bool, completion: @escaping (Result<MediaItem, Error>) -> Void) {
            var createdIdentifier: String?
            PHPhotoLibrary.shared().performChanges({
                if item.kind == .livePhoto && !separate, let photo = item.photoURL, let video = item.videoURL {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = item.created
                    request.addResource(with: .photo, fileURL: photo, options: nil)
                    request.addResource(with: .pairedVideo, fileURL: video, options: nil)
                    createdIdentifier = request.placeholderForCreatedAsset?.localIdentifier
                    return
                }
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
                        updated.photosAssetIdentifier = createdIdentifier; updated.savedSeparately = separate
                        // Record import success before verification to avoid duplicate imports on retry.
                        self.persistPhotosResult(updated)
                        if item.kind == .livePhoto && !separate {
                            LivePhotoDiagnostics.record("import-complete", "Photos creation succeeded; checking photoLive subtype")
                            self.verifySavedLivePhoto(updated, attempt: 0, completion: completion)
                        } else { DispatchQueue.main.async { completion(.success(updated)) } }
                    } else {
                        let message = item.kind == .livePhoto && !separate
                            ? "Photos could not import this Live Photo. Your capture is still in MirrorCam. Try again, or use Save photo + video. \(error?.localizedDescription ?? "")"
                            : (error?.localizedDescription ?? "Could not save to Photos. Try again.")
                        LivePhotoDiagnostics.record("import-error", message)
                        DispatchQueue.main.async { completion(.failure(CameraError.message(message))) }
                    }
                }
            })
    }

    func verifyInPhotos(_ item: MediaItem, completion: @escaping (Result<MediaItem, Error>) -> Void) {
        queue.async {
            guard item.kind == .livePhoto, item.savedToPhotos, item.savedSeparately != true else {
                DispatchQueue.main.async { completion(.failure(CameraError.message("This item was not saved as a paired Live Photo."))) }; return
            }
            self.verifySavedLivePhoto(item, attempt: 0, completion: completion)
        }
    }

    /// Runs on the media queue after performChanges completes, including a bounded visibility retry.
    private func verifySavedLivePhoto(_ item: MediaItem, attempt: Int, completion: @escaping (Result<MediaItem, Error>) -> Void) {
        var updated = item
        let status = PHPhotoLibrary.authorizationStatus()
        var allowed = status == .authorized
        if #available(iOS 14, *) { allowed = allowed || status == .limited }
        let asset = allowed ? item.photosAssetIdentifier.flatMap {
            PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).firstObject
        } : nil
        if asset == nil && allowed && item.photosAssetIdentifier != nil && attempt < 3 {
            queue.asyncAfter(deadline: .now() + 0.3) { self.verifySavedLivePhoto(item, attempt: attempt + 1, completion: completion) }
            return
        }
        if let asset = asset {
            updated.livePhotoVerified = asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive)
            updated.photosVerificationMessage = updated.livePhotoVerified == true
                ? "Verified: the saved Photos asset has the photoLive subtype."
                : "Photos saved the resources, but the asset does not have the photoLive subtype. Playback compatibility is not confirmed."
            let resources = PHAssetResource.assetResources(for: asset).map { String($0.type.rawValue) }.joined(separator: ",")
            LivePhotoDiagnostics.record("asset-verification", "photoLive=\(updated.livePhotoVerified == true); resources=\(resources)")
        } else {
            updated.livePhotoVerified = nil
            updated.photosVerificationMessage = item.photosAssetIdentifier == nil
                ? "This earlier save has no recorded Photos identifier, so MirrorCam cannot verify its subtype. Check it in Photos."
                : "Photos reported a successful save, but the asset cannot be fetched. Check Photos access or whether the asset was deleted, then Verify in Photos again."
            LivePhotoDiagnostics.record("asset-unverified", updated.photosVerificationMessage!)
        }
        persistPhotosResult(updated)
        // Creation already succeeded. Return its saved state even if verification is unavailable.
        DispatchQueue.main.async { completion(.success(updated)) }
    }

    private func persistPhotosResult(_ item: MediaItem) {
        do { try write(item) }
        catch { LivePhotoDiagnostics.record("local-save-state-error", "Photos result could not be persisted: \(error.localizedDescription)") }
    }

    private func write(_ item: MediaItem) throws {
        try JSONEncoder().encode(item).write(to: item.directory.appendingPathComponent("item.json"), options: .atomic)
    }
}
