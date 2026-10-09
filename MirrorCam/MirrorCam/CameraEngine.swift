import AVFoundation
import UIKit

enum CaptureMode: Int { case photo, video, motion }

final class CameraEngine: NSObject, AVCapturePhotoCaptureDelegate,
                          AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "com.mirrorcam.camera", qos: .userInitiated)
    var onState: ((Bool, Bool, Bool, Bool) -> Void)? // ready, busy, front camera, flash available
    var onRecording: ((Bool) -> Void)?
    var onCapture: ((Data?, URL?, CaptureMode) -> Void)?
    var onError: ((String) -> Void)?
    var onBufferReady: ((Bool) -> Void)?
    var onModeChanged: ((CaptureMode) -> Void)?

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let buffer = RollingBuffer()
    private var input: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var configured = false
    private var visible = false
    private var interrupted = false
    private var mode: CaptureMode = .photo
    private var saveMirrored = true
    private var orientation: AVCaptureVideoOrientation = .portrait
    private var requestedOrientation: AVCaptureVideoOrientation = .portrait
    private var flash: AVCaptureDevice.FlashMode = .off
    private var writer: ClipWriter?
    private var recordRequested = false
    private var finishing = false
    private var photoPending = false
    private var photoID: Int64?
    private var processedPhoto: Data?
    private var processingError: Error?
    private var captureGeneration = UUID()
    private var motionPending = false
    private var motionEnd: CMTime?
    private var motionPhoto: Data?
    private var motionURL: URL?
    private var bufferReady = false
    private var observers: [NSObjectProtocol] = []
    private var busy: Bool { return photoPending || writer != nil || recordRequested || finishing || motionPending }

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self = self else { return }
                self.interrupted = true
                self.clearBuffer()
                self.stopRecording()
                if self.motionPending { self.abortMotion("Motion capture was interrupted. Please try again.") }
                self.emitState()
                self.report("Camera interrupted. It will resume when the camera becomes available.")
            }
        })
        observers.append(center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self = self else { return }
                self.interrupted = false
                self.startIfNeeded()
            }
        })
        observers.append(center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self?.queue.async { [weak self] in
                guard let self = self else { return }
                self.clearBuffer()
                self.failCapture(error?.localizedDescription ?? "The camera stopped unexpectedly.")
                if error?.code == .mediaServicesWereReset { self.startIfNeeded() }
                else { self.interrupted = true; self.emitState() }
            }
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    func prepare() {
        queue.async {
            guard !self.configured else { self.startIfNeeded(); return }
            do {
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }
                self.session.sessionPreset = .photo
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(for: .video) else { throw CameraError.message("No camera is available. Use a physical iPhone.") }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput) else { throw CameraError.message("Cannot configure this camera.") }
                self.session.addInput(input); self.input = input
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)
                self.configured = true
                self.applyConnections()
            } catch {
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }
                self.session.commitConfiguration()
                self.input = nil
                self.configured = false
                self.report(error.localizedDescription)
            }
            self.startIfNeeded()
        }
    }

    func setVisible(_ visible: Bool) {
        queue.async {
            self.visible = visible
            if visible {
                if !self.session.isInterrupted { self.interrupted = false }
                self.startIfNeeded()
            }
            else {
                self.stopRecording()
                if self.motionPending { self.abortMotion("Motion capture was cancelled when the camera closed.") }
                self.setTorch(false)
                if self.session.isRunning { self.session.stopRunning() }
                self.clearBuffer(); self.emitState()
            }
        }
    }

    private func startIfNeeded() {
        if configured && visible && !interrupted && !session.isRunning { session.startRunning() }
        emitState()
    }

    func setMode(_ newMode: CaptureMode, microphone: Bool) {
        queue.async {
            guard self.configured, !self.busy else { return }
            self.setTorch(false)
            self.session.beginConfiguration()
            self.mode = newMode
            let preset: AVCaptureSession.Preset = newMode == .photo ? .photo : (newMode == .motion ? .vga640x480 : .hd1280x720)
            if newMode == .photo {
                if self.session.outputs.contains(where: { $0 === self.videoOutput }) { self.session.removeOutput(self.videoOutput) }
            }
            if self.session.canSetSessionPreset(preset) { self.session.sessionPreset = preset }
            else { self.session.sessionPreset = .medium }
            if newMode != .photo && !self.session.outputs.contains(where: { $0 === self.videoOutput }) {
                if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
                else {
                    self.mode = .photo
                    self.session.sessionPreset = .photo
                    self.session.commitConfiguration()
                    self.report("Video data capture is unavailable on this camera.")
                    DispatchQueue.main.async { self.onModeChanged?(.photo) }
                    self.emitState(); return
                }
            }
            if microphone && newMode != .photo && self.audioInput == nil {
                do {
                    guard let device = AVCaptureDevice.default(for: .audio) else { throw CameraError.message("No microphone is available.") }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.audioOutput) else {
                        throw CameraError.message("Cannot add microphone audio. Recording will be silent.")
                    }
                    self.session.addInput(input); self.audioInput = input
                    self.audioOutput.setSampleBufferDelegate(self, queue: self.queue)
                    self.session.addOutput(self.audioOutput)
                } catch { self.report(error.localizedDescription) }
            }
            if (!microphone || newMode == .photo), let audio = self.audioInput {
                self.session.removeInput(audio); self.session.removeOutput(self.audioOutput); self.audioInput = nil
            }
            self.applyConnections()
            self.videoOutput.connection(with: .video)?.isEnabled = newMode != .photo
            self.session.commitConfiguration()
            self.configureFrameRate(newMode == .motion ? 15 : 30)
            self.clearBuffer(); self.emitState()
            DispatchQueue.main.async { self.onModeChanged?(newMode) }
        }
    }

    private func configureFrameRate(_ fps: Double) {
        guard let device = input?.device,
              device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= fps && $0.maxFrameRate >= fps }) else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            let duration = CMTime(value: 1, timescale: Int32(fps))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        } catch { report(error.localizedDescription) }
    }

    func switchCamera() {
        queue.async {
            guard self.configured, !self.busy, let old = self.input else { return }
            let position: AVCaptureDevice.Position = old.device.position == .front ? .back : .front
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }
            do {
                let replacement = try AVCaptureDeviceInput(device: device)
                self.setTorch(false)
                self.session.beginConfiguration()
                self.session.removeInput(old)
                if self.session.canAddInput(replacement) { self.session.addInput(replacement); self.input = replacement }
                else { self.session.addInput(old); self.report("Could not switch cameras.") }
                self.applyConnections()
                self.session.commitConfiguration()
                self.configureFrameRate(self.mode == .motion ? 15 : 30)
                self.clearBuffer(); self.emitState()
            } catch { self.report(error.localizedDescription) }
        }
    }

    func setMirror(_ enabled: Bool) {
        queue.async {
            guard !self.busy else { return }
            self.saveMirrored = enabled; self.applyConnections(); self.clearBuffer()
        }
    }

    func setOrientation(_ orientation: AVCaptureVideoOrientation) {
        queue.async {
            self.requestedOrientation = orientation
            self.refreshOrientation()
        }
    }

    private func refreshOrientation() {
        guard !busy, orientation != requestedOrientation else { return }
        orientation = requestedOrientation; applyConnections(); clearBuffer()
    }

    private func applyConnections() {
        for output in [photoOutput as AVCaptureOutput, videoOutput as AVCaptureOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoOrientationSupported { connection.videoOrientation = orientation }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = input?.device.position == .front && saveMirrored
            }
        }
    }

    func setFlash(_ value: AVCaptureDevice.FlashMode) { queue.async { if !self.busy { self.flash = value } } }

    func zoom(_ factor: CGFloat) {
        queue.async {
            guard !self.busy, let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = max(1, min(factor, min(4, device.activeFormat.videoMaxZoomFactor)))
                device.unlockForConfiguration()
            } catch { self.report(error.localizedDescription) }
        }
    }

    func shutter() {
        queue.async {
            guard self.configured, self.visible, self.session.isRunning, !self.interrupted else { return }
            if self.mode == .video {
                if self.writer != nil || self.recordRequested { self.stopRecording() }
                else if !self.busy {
                    self.captureGeneration = UUID()
                    let generation = self.captureGeneration
                    self.recordRequested = true
                    self.setTorch(self.flash == .on)
                    self.emitState()
                    self.queue.asyncAfter(deadline: .now() + 3) {
                        if self.captureGeneration == generation && self.recordRequested { self.failCapture("The camera did not deliver video frames. Try again.") }
                    }
                }
                return
            }
            guard !self.busy else { return }
            self.captureGeneration = UUID()
            let generation = self.captureGeneration
            if self.mode == .motion {
                guard let first = self.buffer.video.first, let last = self.buffer.lastTime else {
                    self.report("Motion camera is warming up. Try again in a moment."); return
                }
                do {
                    let clip = try ClipWriter(url: Self.temporaryMovie(), firstVideo: first,
                                              hasAudio: self.audioInput != nil, motion: true, queue: self.queue)
                    self.writer = clip
                    // Inputs have independent timelines; both use the first video timestamp as origin.
                    for sample in self.buffer.video { try clip.append(sample, isVideo: true) }
                    for sample in self.buffer.audio { try clip.append(sample, isVideo: false) }
                    self.buffer.clear()
                    self.motionPending = true
                    self.motionEnd = CMTimeAdd(last, CMTime(seconds: 1.5, preferredTimescale: 600))
                    self.queue.asyncAfter(deadline: .now() + 5) {
                        if self.captureGeneration == generation && self.motionPending { self.abortMotion("Motion capture timed out. Please try again.") }
                    }
                } catch { self.failCapture(error.localizedDescription); return }
            }
            self.capturePhoto()
        }
    }

    private func capturePhoto() {
        photoPending = true
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        photoID = settings.uniqueID
        processedPhoto = nil; processingError = nil
        settings.isHighResolutionPhotoEnabled = mode == .photo
        if mode == .photo, input?.device.hasFlash == true,
           photoOutput.supportedFlashModes.contains(flash) { settings.flashMode = flash }
        else { settings.flashMode = .off }
        photoOutput.capturePhoto(with: settings, delegate: self)
        emitState()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async {
            guard self.photoPending, self.photoID == photo.resolvedSettings.uniqueID else { return }
            self.processingError = error
            self.processedPhoto = photo.fileDataRepresentation()
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async {
            guard self.photoPending, self.photoID == resolvedSettings.uniqueID else { return }
            self.photoPending = false
            let captureError = error ?? self.processingError
            guard captureError == nil, let data = self.processedPhoto else {
                self.processedPhoto = nil
                self.failCapture(captureError?.localizedDescription ?? "Could not capture a photo."); return
            }
            self.processedPhoto = nil; self.processingError = nil
            if self.motionPending { self.motionPhoto = data; self.completeMotionIfReady() }
            else { DispatchQueue.main.async { self.onCapture?(data, nil, .photo) } }
            self.emitState()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard visible, !interrupted else { return }
        let isVideo = output === videoOutput
        do {
            if recordRequested && isVideo {
                writer = try ClipWriter(url: Self.temporaryMovie(), firstVideo: sampleBuffer,
                                        hasAudio: audioInput != nil, motion: false, queue: queue)
                recordRequested = false
                DispatchQueue.main.async { self.onRecording?(true) }
            }
            if let writer = writer { try writer.append(sampleBuffer, isVideo: isVideo) }
            if mode == .motion, !motionPending {
                if isVideo { buffer.appendVideo(sampleBuffer) } else { buffer.appendAudio(sampleBuffer) }
                let ready = buffer.span >= 1.35
                if ready != bufferReady {
                    bufferReady = ready
                    DispatchQueue.main.async { self.onBufferReady?(ready) }
                }
            }
            if isVideo, let end = motionEnd, CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), end) >= 0 {
                motionEnd = nil
                finishWriter(isMotion: true)
            }
        } catch { failCapture(error.localizedDescription) }
    }

    private func stopRecording() {
        guard mode == .video else { return }
        recordRequested = false
        setTorch(false)
        DispatchQueue.main.async { self.onRecording?(false) }
        if writer != nil { finishWriter(isMotion: false) }
        else { emitState() }
    }

    private func finishWriter(isMotion: Bool) {
        guard let clip = writer else { return }
        writer = nil; finishing = true; emitState()
        clip.finish { result in
            self.queue.async {
                self.finishing = false
                switch result {
                case .success(let url):
                    if isMotion {
                        if self.motionPending { self.motionURL = url; self.completeMotionIfReady() }
                        else { try? FileManager.default.removeItem(at: url) }
                    } else { DispatchQueue.main.async { self.onCapture?(nil, url, .video) } }
                case .failure(let error): self.failCapture(error.localizedDescription)
                }
                self.emitState()
            }
        }
    }

    private func completeMotionIfReady() {
        guard motionPending, let data = motionPhoto, let url = motionURL else { return }
        motionPhoto = nil; motionURL = nil; motionPending = false
        clearBuffer()
        DispatchQueue.main.async { self.onCapture?(data, url, .motion) }
        emitState()
    }

    private func abortMotion(_ message: String) {
        writer?.cancel(); writer = nil
        if let url = motionURL { try? FileManager.default.removeItem(at: url) }
        motionURL = nil; motionPhoto = nil; motionEnd = nil; motionPending = false; photoPending = false
        processedPhoto = nil; processingError = nil
        clearBuffer(); emitState(); report(message)
    }

    private func failCapture(_ message: String) {
        if motionPending { abortMotion(message) }
        else {
            writer?.cancel(); writer = nil; photoPending = false; recordRequested = false
            processedPhoto = nil; processingError = nil
            setTorch(false)
            DispatchQueue.main.async { self.onRecording?(false) }
            emitState(); report(message)
        }
    }

    private func setTorch(_ on: Bool) {
        guard let device = input?.device, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if on { try device.setTorchModeOn(level: min(0.5, AVCaptureDevice.maxAvailableTorchLevel)) }
            else { device.torchMode = .off }
        } catch { report(error.localizedDescription) }
    }

    private func clearBuffer() {
        buffer.clear(); bufferReady = false
        DispatchQueue.main.async { self.onBufferReady?(false) }
    }

    private func emitState() {
        refreshOrientation()
        let ready = configured && visible && session.isRunning && !interrupted
        let busy = self.busy, front = input?.device.position == .front
        let flash = mode == .photo ? input?.device.hasFlash == true : (mode == .video && input?.device.hasTorch == true)
        DispatchQueue.main.async { self.onState?(ready, busy, front, flash) }
    }

    private func report(_ message: String) { DispatchQueue.main.async { self.onError?(message) } }
    private static func temporaryMovie() -> URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("MirrorCam-\(UUID().uuidString).mp4")
    }
}
