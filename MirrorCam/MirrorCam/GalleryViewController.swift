import UIKit
import AVKit
import PhotosUI
import Photos

final class GalleryViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private var items: [MediaItem] = []
    private var importing = false
    private lazy var editButton = UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(editLibrary))
    private lazy var importButton = UIBarButtonItem(title: "Import", style: .plain, target: self, action: #selector(importPhoto))
    private let formatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short; return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        let libraryTitle = UILabel(); libraryTitle.text = "MirrorCam"
        libraryTitle.font = .systemFont(ofSize: 16, weight: .semibold); libraryTitle.textColor = .white
        let signature = UILabel(); signature.text = "by kirtdmno"
        signature.font = .systemFont(ofSize: 11, weight: .medium)
        signature.textColor = UIColor(red: 0.45, green: 0.95, blue: 0.82, alpha: 1)
        let heading = UIStackView(arrangedSubviews: [libraryTitle, signature])
        heading.axis = .vertical; heading.alignment = .center; heading.spacing = 1
        heading.isAccessibilityElement = true; heading.accessibilityLabel = "MirrorCam library by kirtdmno"
        navigationItem.titleView = heading
        view.backgroundColor = .black; tableView.separatorColor = UIColor(white: 0.22, alpha: 1)
        tableView.rowHeight = 82
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.tintColor = .white
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Camera", style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [editButton, importButton]
        importButton.accessibilityLabel = "Import a photo from Photos to flip it"
        tableView.tableFooterView = UIView()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        MediaStore.shared.load { [weak self] items in
            guard let self = self else { return }
            self.items = items; self.tableView.reloadData()
            let label = UILabel(); label.text = "Your captures will appear here"; label.textColor = .lightGray; label.textAlignment = .center
            self.tableView.backgroundView = items.isEmpty ? label : nil
        }
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func editLibrary() {
        tableView.setEditing(!tableView.isEditing, animated: true)
        editButton.title = tableView.isEditing ? "Done" : "Edit"
    }
    @objc private func importPhoto() {
        guard !importing else { return }
        importing = true; importButton.isEnabled = false
        func openPicker(_ status: PHAuthorizationStatus) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                var allowed = status == .authorized
                if #available(iOS 14, *) { allowed = allowed || status == .limited }
                guard allowed, UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
                    self.importing = false; self.importButton.isEnabled = true
                    self.showMessage("Allow Photos access in Settings to import a photo.", settings: status == .denied)
                    return
                }
                let picker = UIImagePickerController()
                picker.sourceType = .photoLibrary; picker.mediaTypes = ["public.image"]
                picker.allowsEditing = false; picker.delegate = self
                self.present(picker, animated: true)
            }
        }
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .notDetermined { PHPhotoLibrary.requestAuthorization { openPicker($0) } }
        else { openPicker(status) }
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        importing = false; importButton.isEnabled = true; picker.dismiss(animated: true)
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let url = info[.imageURL] as? URL else {
            importing = false; importButton.isEnabled = true
            picker.dismiss(animated: true) { self.showMessage("Could not load this photo. Download it from iCloud in Photos and try again.") }
            return
        }
        // Keep the picker and its source file alive until the local copy is complete.
        picker.view.isUserInteractionEnabled = false
        MediaStore.shared.addEditedPhoto(from: url, flipped: false) { [weak self] result in
            guard let self = self else { return }
            self.importing = false; self.importButton.isEnabled = true
            picker.dismiss(animated: true) {
                switch result {
                case .success(let item): self.navigationController?.pushViewController(MediaDetailViewController(item: item), animated: true)
                case .failure(let error): self.showMessage(error.localizedDescription)
                }
            }
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return items.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "media") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "media")
        let item = items[indexPath.row]
        cell.backgroundColor = .black; cell.textLabel?.textColor = .white; cell.detailTextLabel?.textColor = .lightGray
        cell.textLabel?.text = item.kind == .livePhoto ? "LIVE Photo" : (item.kind == .motion ? "Motion photo + clip" : item.kind.rawValue.capitalized)
        cell.detailTextLabel?.text = formatter.string(from: item.created) + (item.savedToPhotos ? " · In Photos" : " · Local")
        cell.imageView?.image = UIImage(contentsOfFile: item.thumbnailURL.path)
        cell.imageView?.contentMode = .scaleAspectFit
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(MediaDetailViewController(item: items[indexPath.row]), animated: true)
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let item = items[indexPath.row]
        let alert = UIAlertController(title: "Delete local capture?", message: "This deletes the MirrorCam copy. Copies already saved in Photos remain there.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            MediaStore.shared.remove(item) { error in
                guard let self = self else { return }
                if let error = error { self.showMessage(error.localizedDescription) }
                else { self.items.removeAll { $0.id == item.id }; self.tableView.reloadData() }
            }
        })
        present(alert, animated: true)
    }
}

final class MediaDetailViewController: UIViewController {
    private var item: MediaItem
    private let imageView = UIImageView()
    private let liveView = PHLivePhotoView()
    private let separateButton = UIButton(type: .system)
    private var liveRequest: PHLivePhotoRequestID?
    private let saveButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let flipButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private var flipped = false, editingPhoto = false
    private let info = UILabel()
    private var player: AVPlayer?
    init(item: MediaItem) { self.item = item; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Programmatic UI") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.kind == .livePhoto ? "LIVE Photo" : (item.kind == .motion ? "Motion" : item.kind.rawValue.capitalized)
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(imageView)
        liveView.contentMode = .scaleAspectFit; liveView.isHidden = true
        liveView.playbackGestureRecognizer.isEnabled = false
        liveView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(liveView)
        NSLayoutConstraint.activate([
            liveView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor), liveView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            liveView.topAnchor.constraint(equalTo: imageView.topAnchor), liveView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])
        liveView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(holdLive(_:))))
        saveButton.setTitle(item.savedToPhotos ? "Saved to Photos" : "Save to Photos", for: .normal)
        saveButton.isEnabled = !item.savedToPhotos
        playButton.setTitle("Play clip", for: .normal); playButton.isHidden = item.videoURL == nil
        separateButton.setTitle("Save photo + video", for: .normal); separateButton.isHidden = item.kind != .livePhoto
        separateButton.isEnabled = !item.savedToPhotos
        shareButton.setTitle("Share", for: .normal)
        flipButton.setTitle("Flip horizontally", for: .normal); flipButton.isHidden = item.photoURL == nil
        copyButton.setTitle("Create flipped copy", for: .normal); copyButton.isHidden = true
        flipButton.accessibilityHint = "Preview the opposite horizontal orientation, then create a copy to keep it."
        for button in [saveButton, playButton, separateButton, shareButton, flipButton, copyButton] {
            button.tintColor = UIColor(red: 0.45, green: 0.95, blue: 0.82, alpha: 1)
            button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        separateButton.addTarget(self, action: #selector(saveSeparate), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(play), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        flipButton.addTarget(self, action: #selector(toggleFlip), for: .touchUpInside)
        copyButton.addTarget(self, action: #selector(createFlippedCopy), for: .touchUpInside)
        info.textColor = .lightGray; info.font = .systemFont(ofSize: 12); info.textAlignment = .center; info.numberOfLines = 3
        info.text = item.kind == .livePhoto ? "Touch and hold the photo to animate it.\nSave to Photos imports one Live Photo.\nShare sends the original JPEG and MOV files."
            : (item.kind == .motion ? "This older Motion capture saves as a photo and separate video." : "Captures stay in MirrorCam until you delete them.")
        let stack = UIStackView(arrangedSubviews: [flipButton, copyButton, playButton, saveButton, separateButton, shareButton, info])
        stack.axis = .vertical; stack.spacing = 4; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -12)
        ])
        let url = item.photoURL ?? item.thumbnailURL
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = MediaStore.downsample(url, pixels: 1400)
            DispatchQueue.main.async { self?.imageView.image = image }
        }
        if item.kind == .livePhoto, let photo = item.photoURL, let video = item.videoURL {
            liveRequest = PHLivePhoto.request(withResourceFileURLs: [photo, video], placeholderImage: nil,
                targetSize: CGSize(width: 750, height: 1000), contentMode: .aspectFit) { [weak self] livePhoto, result in
                guard !(result[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false) else { return }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.liveView.livePhoto = livePhoto; self.liveView.isHidden = livePhoto == nil || self.flipped
                    if livePhoto == nil && !self.flipped { self.info.text = "Live preview is unavailable on this device. Play clip still works. Try Save to Photos, or save the photo + video separately." }
                }
            }
        }
    }

    @objc private func toggleFlip() {
        guard !editingPhoto else { return }
        flipped.toggle(); liveView.stopPlayback()
        imageView.transform = flipped ? CGAffineTransform(scaleX: -1, y: 1) : .identity
        liveView.isHidden = flipped || liveView.livePhoto == nil
        flipButton.setTitle(flipped ? "Undo flip" : "Flip horizontally", for: .normal)
        copyButton.isHidden = !flipped
        saveButton.isHidden = flipped; shareButton.isHidden = flipped
        playButton.isHidden = flipped || item.videoURL == nil
        separateButton.isHidden = flipped || item.kind != .livePhoto
        info.text = flipped ? "Create a flipped still-photo copy, then Save to Photos.\nOriginal stays unchanged. JPEG copies are up to 2048 pixels."
            : (item.kind == .livePhoto ? "Touch and hold the photo to animate it.\nSave to Photos imports one Live Photo."
               : "Captures stay in MirrorCam until you delete them.")
    }
    @objc private func createFlippedCopy() {
        guard flipped, !editingPhoto, let url = item.photoURL else { return }
        editingPhoto = true; flipButton.isEnabled = false; copyButton.isEnabled = false
        copyButton.setTitle("Creating copy…", for: .normal)
        MediaStore.shared.addEditedPhoto(from: url, flipped: true) { [weak self] result in
            guard let self = self else { return }
            self.editingPhoto = false; self.flipButton.isEnabled = true; self.copyButton.isEnabled = true
            self.copyButton.setTitle("Create flipped copy", for: .normal)
            switch result {
            case .success(let copy):
                if self.navigationController?.topViewController === self {
                    self.navigationController?.pushViewController(MediaDetailViewController(item: copy), animated: true)
                }
            case .failure(let error): self.showMessage(error.localizedDescription)
            }
        }
    }
    @objc private func save() {
        saveCapture(separate: false)
    }
    @objc private func saveSeparate() { saveCapture(separate: true) }
    private func saveCapture(separate: Bool) {
        saveButton.isEnabled = false; separateButton.isEnabled = false; flipButton.isEnabled = false
        MediaStore.shared.saveToPhotos(item, separate: separate) { [weak self] result in
            guard let self = self else { return }
            self.flipButton.isEnabled = true
            switch result {
            case .success(let item): self.item = item; self.saveButton.setTitle("Saved to Photos", for: .normal)
            case .failure(let error):
                self.saveButton.isEnabled = true; self.separateButton.isEnabled = true
                self.showMessage(error.localizedDescription, settings: PHPhotoLibrary.authorizationStatus() == .denied)
            }
        }
    }
    @objc private func holdLive(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { liveView.startPlayback(with: .full) }
        else if gesture.state == .ended || gesture.state == .cancelled { liveView.stopPlayback() }
    }
    deinit { if let request = liveRequest { PHLivePhoto.cancelRequest(withRequestID: request) } }
    @objc private func play() {
        guard let url = item.videoURL else { return }
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url); self.player = player; controller.player = player
        present(controller, animated: true) { player.play() }
    }
    @objc private func share() {
        let urls = [item.photoURL, item.videoURL].compactMap { $0 }
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = shareButton
        present(controller, animated: true)
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); player?.pause(); liveView.stopPlayback() }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); player?.pause() }
}
