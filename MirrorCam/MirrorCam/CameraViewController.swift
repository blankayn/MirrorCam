import UIKit
import AVFoundation

final class CameraViewController: UIViewController {
    private let engine = CameraEngine()
    private let preview = PreviewView()
    private let grid = GridView()
    private let shutter = ShutterButton()
    private let modes = UISegmentedControl(items: ["PHOTO", "VIDEO", "LIVE"])
    private let frameButton = UIButton(type: .system)
    private let zoomSlider = UISlider()
    private let resetZoomButton = UIButton(type: .system)
    private var photoOptions = PhotoOptions()
    private var previewAspect: NSLayoutConstraint?
    private var zoomLimit: CGFloat = 4
    private var irisRequested = false
    private var nativeLive = false
    private var liveDiagnostic = "Software LIVE capture"
    private let gridButton = UIButton(type: .system)
    private let timerButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let mirrorButton = UIButton(type: .system)
    private let switchButton = UIButton(type: .system)
    private let galleryButton = UIButton(type: .system)
    private let status = UILabel()
    private let countdownLabel = UILabel()
    private var mode: CaptureMode = .photo
    private var ready = false, busy = false, recording = false, saving = false, front = true
    private var flashAvailable = false, mirrored = true, motionReady = false
    private var flash: AVCaptureDevice.FlashMode = .off
    private var timerSeconds = 0
    private var countdownTimer: Timer?
    private var recordingTimer: Timer?
    private var recordingStart: TimeInterval = 0
    private var zoom: CGFloat = 1, pinchStart: CGFloat = 1
    private var cameraVisible = false
    private var modeRequest = 0
    private var modeSwitchPending = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var observers: [NSObjectProtocol] = []
    private let accent = UIColor(red: 0.45, green: 0.95, blue: 0.82, alpha: 1)

    override var prefersStatusBarHidden: Bool { return true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        preview.previewLayer.session = engine.session
        preview.previewLayer.videoGravity = .resizeAspectFill
        engine.onLiveBackend = { [weak self] native, diagnostic in
            guard let self = self else { return }
            self.nativeLive = native; self.liveDiagnostic = diagnostic
            if native { self.photoOptions = PhotoOptions() }
            self.updateFrame(); self.updateStatus()
        }
        engine.onZoom = { [weak self] actual, limit in
            guard let self = self else { return }
            self.zoom = actual; self.zoomLimit = limit
            self.zoomSlider.maximumValue = Float(max(1.01, limit)); self.zoomSlider.value = Float(actual)
            self.resetZoomButton.setTitle(String(format: "%.1f×", Double(actual)), for: .normal)
            self.zoomSlider.isEnabled = limit > 1 && self.ready && !self.busy
        }
        engine.onState = { [weak self] ready, busy, front, flash in
            guard let self = self else { return }
            self.ready = ready; self.busy = busy; self.front = front; self.flashAvailable = flash
            self.updatePreview(); self.updateControls()
        }
        engine.onBufferReady = { [weak self] ready in
            self?.motionReady = ready; self?.updateStatus()
        }
        engine.onModeChanged = { [weak self] mode in
            guard let self = self else { return }
            self.mode = mode; self.modes.selectedSegmentIndex = mode.rawValue
            self.modeSwitchPending = false; self.updateFrame(); self.updateControls()
        }
        engine.onRecording = { [weak self] recording in
            guard let self = self else { return }
            self.recording = recording
            self.shutter.setRecording(recording)
            self.recordingTimer?.invalidate(); self.recordingTimer = nil
            if recording {
                self.recordingStart = ProcessInfo.processInfo.systemUptime
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateStatus() }
            }
            self.updateControls(); self.updateStatus()
        }
        engine.onError = { [weak self] text in self?.endBackgroundTask(); self?.showMessage(text) }
        engine.onCapture = { [weak self] photo, video, mode in
            guard let self = self else { return }
            self.saving = true; self.updateControls()
            MediaStore.shared.add(photo: photo, video: video, mode: mode) { [weak self] result in
                guard let self = self else { return }
                self.saving = false; self.updateControls()
                self.endBackgroundTask()
                switch result {
                case .success(let item):
                    self.setThumbnail(item)
                    self.status.text = "Saved in MirrorCam · open Library to save to Photos"
                    UIAccessibility.post(notification: .announcement, argument: "Capture saved in MirrorCam")
                case .failure(let error): self.showMessage("Could not store capture: \(error.localizedDescription)")
                }
            }
            UIView.animate(withDuration: 0.1, animations: { self.preview.alpha = 0.45 }) { _ in
                UIView.animate(withDuration: 0.18) { self.preview.alpha = 1 }
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if let self = self, self.backgroundTask == .invalid, self.recording || self.busy || self.saving {
                self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish MirrorCam capture") { [weak self] in self?.endBackgroundTask() }
            }
            self?.cancelCountdown(); self?.engine.setVisible(false)
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.cameraVisible else { return }
            self.authorizeCamera()
            self.setCaptureOrientation()
        })
        observers.append(center.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setCaptureOrientation()
        })
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }

    deinit {
        countdownTimer?.invalidate(); recordingTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        modeSwitchPending = false; modes.selectedSegmentIndex = mode.rawValue
        cameraVisible = true; authorizeCamera(); setCaptureOrientation()
        MediaStore.shared.load { [weak self] items in
            if let item = items.first { self?.setThumbnail(item) }
            else {
                self?.galleryButton.setBackgroundImage(nil, for: .normal)
                self?.galleryButton.setTitle("Library", for: .normal)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraVisible = false; modeRequest += 1; cancelCountdown(); engine.setVisible(false)
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); updatePreview() }

    private func buildUI() {
        view.backgroundColor = .black
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)
        preview.clipsToBounds = true
        grid.backgroundColor = .clear; grid.isUserInteractionEnabled = false; grid.isHidden = true
        grid.contentMode = .redraw; grid.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: preview.leadingAnchor), grid.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            grid.topAnchor.constraint(equalTo: preview.topAnchor), grid.bottomAnchor.constraint(equalTo: preview.bottomAnchor)
        ])
        let top = UIStackView(arrangedSubviews: [gridButton, timerButton, flashButton, mirrorButton])
        top.axis = .horizontal; top.distribution = .fillEqually; top.spacing = 4
        top.backgroundColor = .clear
        let topBackdrop = UIView(); topBackdrop.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        topBackdrop.layer.cornerRadius = 16
        topBackdrop.translatesAutoresizingMaskIntoConstraints = false; top.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBackdrop); topBackdrop.addSubview(top)
        NSLayoutConstraint.activate([
            topBackdrop.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            topBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), topBackdrop.heightAnchor.constraint(equalToConstant: 88),
            top.leadingAnchor.constraint(equalTo: topBackdrop.leadingAnchor, constant: 4), top.trailingAnchor.constraint(equalTo: topBackdrop.trailingAnchor, constant: -4),
            top.topAnchor.constraint(equalTo: topBackdrop.topAnchor), top.heightAnchor.constraint(equalToConstant: 44)
        ])
        frameButton.setTitle("4:3 · Max", for: .normal)
        frameButton.accessibilityLabel = "Photo Size and Zoom Adjustment"
        frameButton.addTarget(self, action: #selector(adjustPhotoSize), for: .touchUpInside)
        frameButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold); frameButton.tintColor = accent
        resetZoomButton.setTitle("1.0×", for: .normal); resetZoomButton.tintColor = accent
        resetZoomButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        resetZoomButton.accessibilityLabel = "Reset zoom to 1×"
        resetZoomButton.addTarget(self, action: #selector(resetZoom), for: .touchUpInside)
        zoomSlider.minimumValue = 1; zoomSlider.maximumValue = 4; zoomSlider.value = 1; zoomSlider.tintColor = accent
        zoomSlider.accessibilityLabel = "Camera zoom"
        zoomSlider.addTarget(self, action: #selector(slideZoom), for: .valueChanged)
        let adjustments = UIStackView(arrangedSubviews: [frameButton, zoomSlider, resetZoomButton])
        adjustments.axis = .horizontal; adjustments.spacing = 12; adjustments.translatesAutoresizingMaskIntoConstraints = false
        topBackdrop.addSubview(adjustments)
        NSLayoutConstraint.activate([
            adjustments.leadingAnchor.constraint(equalTo: topBackdrop.leadingAnchor, constant: 12),
            adjustments.trailingAnchor.constraint(equalTo: topBackdrop.trailingAnchor, constant: -12),
            adjustments.topAnchor.constraint(equalTo: top.bottomAnchor), adjustments.bottomAnchor.constraint(equalTo: topBackdrop.bottomAnchor),
            frameButton.widthAnchor.constraint(equalToConstant: 96), resetZoomButton.widthAnchor.constraint(equalToConstant: 44)
        ])
        for button in [gridButton, timerButton, flashButton, mirrorButton] {
            button.tintColor = .white; button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        }
        gridButton.setTitle("Grid Off", for: .normal); timerButton.setTitle("Timer Off", for: .normal)
        flashButton.setTitle("Flash Off", for: .normal); mirrorButton.setTitle("Mirror On", for: .normal)
        gridButton.addTarget(self, action: #selector(toggleGrid), for: .touchUpInside)
        timerButton.addTarget(self, action: #selector(cycleTimer), for: .touchUpInside)
        flashButton.addTarget(self, action: #selector(cycleFlash), for: .touchUpInside)
        mirrorButton.addTarget(self, action: #selector(toggleMirror), for: .touchUpInside)
        mirrorButton.accessibilityLabel = "Save front camera photos and videos mirrored"

        let bottom = UIView(); bottom.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        bottom.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(bottom)
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor), bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: view.bottomAnchor), bottom.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -180)
        ])
        let frameArea = UILayoutGuide(); view.addLayoutGuide(frameArea)
        NSLayoutConstraint.activate([
            frameArea.leadingAnchor.constraint(equalTo: view.leadingAnchor), frameArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frameArea.topAnchor.constraint(equalTo: topBackdrop.bottomAnchor, constant: 8), frameArea.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -8),
            preview.centerXAnchor.constraint(equalTo: frameArea.centerXAnchor), preview.centerYAnchor.constraint(equalTo: frameArea.centerYAnchor),
            preview.widthAnchor.constraint(lessThanOrEqualTo: frameArea.widthAnchor), preview.heightAnchor.constraint(lessThanOrEqualTo: frameArea.heightAnchor)
        ])
        let fitWidth = preview.widthAnchor.constraint(equalTo: frameArea.widthAnchor); fitWidth.priority = .defaultHigh; fitWidth.isActive = true
        updateFrame()
        modes.selectedSegmentIndex = 0; modes.tintColor = accent
        modes.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 12, weight: .semibold)], for: .normal)
        modes.addTarget(self, action: #selector(changeMode), for: .valueChanged)
        shutter.addTarget(self, action: #selector(pressShutter), for: .touchUpInside)
        galleryButton.backgroundColor = UIColor(white: 0.15, alpha: 1)
        galleryButton.layer.cornerRadius = 12; galleryButton.clipsToBounds = true
        galleryButton.setTitle("Library", for: .normal); galleryButton.tintColor = .white
        galleryButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        galleryButton.imageView?.contentMode = .scaleAspectFill; galleryButton.accessibilityLabel = "Open capture library"
        galleryButton.addTarget(self, action: #selector(openGallery), for: .touchUpInside)
        switchButton.setTitle("↻", for: .normal); switchButton.titleLabel?.font = .systemFont(ofSize: 36, weight: .light)
        switchButton.tintColor = .white; switchButton.accessibilityLabel = "Switch front and back cameras"
        switchButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        status.textColor = .white; status.textAlignment = .center; status.numberOfLines = 2
        status.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        for child in [modes, shutter, galleryButton, switchButton, status] {
            child.translatesAutoresizingMaskIntoConstraints = false; bottom.addSubview(child)
        }
        NSLayoutConstraint.activate([
            modes.topAnchor.constraint(equalTo: bottom.topAnchor, constant: 14), modes.centerXAnchor.constraint(equalTo: bottom.centerXAnchor),
            modes.widthAnchor.constraint(equalTo: bottom.widthAnchor, multiplier: 0.76), modes.heightAnchor.constraint(equalToConstant: 32),
            shutter.centerXAnchor.constraint(equalTo: bottom.centerXAnchor), shutter.topAnchor.constraint(equalTo: modes.bottomAnchor, constant: 14),
            shutter.widthAnchor.constraint(equalToConstant: 78), shutter.heightAnchor.constraint(equalTo: shutter.widthAnchor),
            galleryButton.centerYAnchor.constraint(equalTo: shutter.centerYAnchor), galleryButton.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 28),
            galleryButton.widthAnchor.constraint(equalToConstant: 50), galleryButton.heightAnchor.constraint(equalToConstant: 50),
            switchButton.centerYAnchor.constraint(equalTo: shutter.centerYAnchor), switchButton.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -28),
            switchButton.widthAnchor.constraint(equalToConstant: 50), switchButton.heightAnchor.constraint(equalToConstant: 50),
            status.topAnchor.constraint(equalTo: shutter.bottomAnchor, constant: 6), status.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -12), status.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4)
        ])
        countdownLabel.textColor = .white; countdownLabel.font = .systemFont(ofSize: 88, weight: .thin)
        countdownLabel.textAlignment = .center; countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        countdownLabel.isUserInteractionEnabled = false; view.addSubview(countdownLabel)
        NSLayoutConstraint.activate([
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        preview.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        updateControls(); updateStatus()
    }

    private func authorizeCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            engine.setVisible(cameraVisible && UIApplication.shared.applicationState == .active); engine.prepare()
            engine.setMode(mode, microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async { if self?.cameraVisible == true { self?.authorizeCamera() } }
            }
        default:
            ready = false; updateControls(); status.text = "Camera access is required"
            showMessage("Enable Camera access in Settings to use MirrorCam.", settings: true)
        }
    }

    private func updatePreview() {
        guard let connection = preview.previewLayer.connection else { return }
        if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = front
        }
    }

    private func setCaptureOrientation() {
        let orientation: AVCaptureVideoOrientation
        switch UIDevice.current.orientation {
        case .landscapeLeft: orientation = .landscapeRight
        case .landscapeRight: orientation = .landscapeLeft
        case .portraitUpsideDown: orientation = .portraitUpsideDown
        case .portrait: orientation = .portrait
        default: return
        }
        engine.setOrientation(orientation)
    }

    private func updateControls() {
        let countdown = countdownTimer != nil
        let idle = ready && !busy && !saving && !countdown && !modeSwitchPending
        shutter.isEnabled = recording || countdown || idle
        shutter.alpha = shutter.isEnabled ? 1 : 0.45
        modes.isEnabled = idle; switchButton.isEnabled = idle
        mirrorButton.isEnabled = idle && front; flashButton.isEnabled = idle && flashAvailable
        timerButton.isEnabled = idle; galleryButton.isEnabled = !busy && !saving && !countdown && !modeSwitchPending
        frameButton.isEnabled = idle && mode != .video
        resetZoomButton.isEnabled = idle; zoomSlider.isEnabled = idle && zoomLimit > 1
        for button in [switchButton, mirrorButton, flashButton, timerButton, galleryButton] { button.alpha = button.isEnabled ? 1 : 0.4 }
        shutter.mode = mode
        updateStatus()
    }

    private func updateStatus() {
        if recording {
            let seconds = Int(ProcessInfo.processInfo.systemUptime - recordingStart)
            status.text = String(format: "● %02d:%02d", seconds / 60, seconds % 60)
            status.textColor = UIColor(red: 1, green: 0.3, blue: 0.35, alpha: 1)
        } else {
            status.textColor = .white
            if saving { status.text = "Saving capture…" }
            else if busy { status.text = mode == .motion ? "Hold steady · capturing Live Photo…" : "Processing…" }
            else if !ready { status.text = "Camera unavailable" }
            else if mode == .motion && nativeLive { status.text = "Iris12 experiment · native LIVE ready" }
            else if mode == .motion { status.text = motionReady ? "LIVE ready · 1.5s before + after" : "LIVE warming up · wait for full pre-roll" }
            else { status.text = front ? "Mirror preview · saved mirror \(mirrored ? "on" : "off")" : "Rear camera" }
        }
    }

    @objc private func toggleGrid() {
        grid.isHidden.toggle(); gridButton.setTitle(grid.isHidden ? "Grid Off" : "Grid On", for: .normal)
    }
    @objc private func cycleTimer() {
        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
        timerButton.setTitle(timerSeconds == 0 ? "Timer Off" : "Timer \(timerSeconds)s", for: .normal)
    }
    @objc private func cycleFlash() {
        if mode == .video { flash = flash == .off ? .on : .off }
        else { flash = flash == .off ? .auto : (flash == .auto ? .on : .off) }
        flashButton.setTitle(flash == .off ? "Flash Off" : (flash == .on ? "Flash On" : "Flash Auto"), for: .normal)
        engine.setFlash(flash)
    }
    @objc private func toggleMirror() {
        mirrored.toggle(); mirrorButton.setTitle(mirrored ? "Mirror On" : "Mirror Off", for: .normal); engine.setMirror(mirrored)
    }
    @objc private func switchCamera() { zoom = 1; engine.switchCamera() }

    @objc private func changeMode() {
        guard let requested = CaptureMode(rawValue: modes.selectedSegmentIndex) else { return }
        modeRequest += 1; let request = modeRequest
        modeSwitchPending = true; updateControls()
        func apply(_ microphone: Bool) {
            guard request == modeRequest, cameraVisible else { return }
            mode = requested; shutter.mode = mode
            flash = .off; flashButton.setTitle("Flash Off", for: .normal); engine.setFlash(.off)
            engine.setMode(mode, microphone: microphone)
            if !microphone && mode != .photo { showMessage("Microphone access is disabled. Video and motion clips will be silent. Enable Microphone in Settings to record audio.", settings: true) }
        }
        if requested == .photo { apply(false); return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: apply(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in DispatchQueue.main.async { apply(granted) } }
        default: apply(false)
        }
    }

    @objc private func pressShutter() {
        if countdownTimer != nil { cancelCountdown(); return }
        if recording || timerSeconds == 0 { engine.shutter(); return }
        var remaining = timerSeconds
        countdownLabel.text = "\(remaining)"
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            remaining -= 1
            self.countdownLabel.text = remaining > 0 ? "\(remaining)" : nil
            if remaining <= 0 {
                timer.invalidate(); self.countdownTimer = nil
                self.engine.shutter(); self.updateControls()
            } else { UIAccessibility.post(notification: .announcement, argument: "\(remaining)") }
        }
        updateControls()
    }

    private func cancelCountdown() { countdownTimer?.invalidate(); countdownTimer = nil; countdownLabel.text = nil; updateControls() }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard ready, !busy, !saving, !modeSwitchPending, countdownTimer == nil else { return }
        if gesture.state == .began { pinchStart = zoom }
        zoom = max(1, min(zoomLimit, pinchStart * gesture.scale)); engine.zoom(zoom)
    }

    @objc private func slideZoom() { engine.zoom(CGFloat(zoomSlider.value)) }
    @objc private func resetZoom() { engine.zoom(1) }

    private func updateFrame() {
        previewAspect?.isActive = false
        let aspect: PhotoAspect = mode == .video ? .wide : photoOptions.aspect
        previewAspect = preview.widthAnchor.constraint(equalTo: preview.heightAnchor, multiplier: aspect.portraitRatio)
        previewAspect?.isActive = true
        let size = photoOptions.resolution == .maximum ? "Max" : photoOptions.resolution.title
        frameButton.setTitle("\(photoOptions.aspect.title.components(separatedBy: " ")[0]) · \(size)", for: .normal)
        engine.setPhotoOptions(photoOptions)
        view.setNeedsLayout()
    }

    @objc private func adjustPhotoSize() {
        let alert = UIAlertController(title: "Photo Size and Zoom Adjustment",
            message: nativeLive ? "Iris12 experiment uses native 4:3 photos at maximum resolution.\n\(liveDiagnostic)"
                : "Choose framing or resolution. Software LIVE stills use the video frame's resolution. Iris12 experiment tries native capture on iOS 12 and falls back if rejected.", preferredStyle: .actionSheet)
        for aspect in PhotoAspect.allCases {
            let action = UIAlertAction(title: "\(aspect == photoOptions.aspect ? "✓ " : "")\(aspect.title)", style: .default) { [weak self] _ in
                self?.photoOptions.aspect = aspect; self?.updateFrame()
            }
            action.isEnabled = !nativeLive; alert.addAction(action)
        }
        for resolution in PhotoResolution.allCases {
            let action = UIAlertAction(title: "\(resolution == photoOptions.resolution ? "✓ " : "")Size: \(resolution.title)", style: .default) { [weak self] _ in
                self?.photoOptions.resolution = resolution; self?.updateFrame()
            }
            action.isEnabled = !nativeLive; alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: irisRequested ? "Turn Iris12 experiment off" : "Try Iris12 native capture (iOS 12)", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.irisRequested.toggle(); self.modeSwitchPending = true; self.updateControls()
            self.engine.setIrisExperiment(self.irisRequested)
        })
        alert.addAction(UIAlertAction(title: "LIVE capture status", style: .default) { [weak self] _ in
            guard let self = self else { return }; self.showMessage(self.liveDiagnostic)
        })
        alert.addAction(UIAlertAction(title: "Reset zoom to 1×", style: .default) { [weak self] _ in self?.resetZoom() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = frameButton
        present(alert, animated: true)
    }

    @objc private func openGallery() {
        let navigation = UINavigationController(rootViewController: GalleryViewController())
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func setThumbnail(_ item: MediaItem) {
        if let image = UIImage(contentsOfFile: item.thumbnailURL.path) {
            galleryButton.setTitle(nil, for: .normal); galleryButton.setBackgroundImage(image, for: .normal)
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid
    }
}
