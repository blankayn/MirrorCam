import UIKit
import AVKit

final class GalleryViewController: UITableViewController {
    private var items: [MediaItem] = []
    private let formatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short; return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "MirrorCam Library"
        view.backgroundColor = .black; tableView.separatorColor = UIColor(white: 0.22, alpha: 1)
        tableView.rowHeight = 82
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.tintColor = .white
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Camera", style: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(editLibrary))
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
        navigationItem.rightBarButtonItem?.title = tableView.isEditing ? "Done" : "Edit"
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return items.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "media") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "media")
        let item = items[indexPath.row]
        cell.backgroundColor = .black; cell.textLabel?.textColor = .white; cell.detailTextLabel?.textColor = .lightGray
        cell.textLabel?.text = item.kind == .motion ? "Motion photo + clip" : item.kind.rawValue.capitalized
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
    private let saveButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let info = UILabel()
    private var player: AVPlayer?
    init(item: MediaItem) { self.item = item; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Programmatic UI") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.kind == .motion ? "Motion" : item.kind.rawValue.capitalized
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(imageView)
        saveButton.setTitle(item.savedToPhotos ? "Saved to Photos" : "Save to Photos", for: .normal)
        saveButton.isEnabled = !item.savedToPhotos
        playButton.setTitle("Play clip", for: .normal); playButton.isHidden = item.videoURL == nil
        shareButton.setTitle("Share", for: .normal)
        for button in [saveButton, playButton, shareButton] {
            button.tintColor = UIColor(red: 0.45, green: 0.95, blue: 0.82, alpha: 1)
            button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(play), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        info.textColor = .lightGray; info.font = .systemFont(ofSize: 12); info.textAlignment = .center; info.numberOfLines = 3
        info.text = item.kind == .motion ? "Motion saves as a still photo and a separate video in Photos.\nThis is a compatible motion pair, not a native Live Photo." : "Captures stay in MirrorCam until you delete them."
        let stack = UIStackView(arrangedSubviews: [playButton, saveButton, shareButton, info])
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
    }

    @objc private func save() {
        saveButton.isEnabled = false
        MediaStore.shared.saveToPhotos(item) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let item): self.item = item; self.saveButton.setTitle("Saved to Photos", for: .normal)
            case .failure(let error): self.saveButton.isEnabled = true; self.showMessage(error.localizedDescription, settings: true)
            }
        }
    }
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
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); player?.pause() }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); player?.pause() }
}
