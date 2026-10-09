import UIKit
import AVFoundation

final class PreviewView: UIView {
    override class var layerClass: AnyClass { return AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { return layer as! AVCaptureVideoPreviewLayer }
}

final class GridView: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.5)
        for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
            context.move(to: CGPoint(x: rect.width * fraction, y: 0))
            context.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
            context.move(to: CGPoint(x: 0, y: rect.height * fraction))
            context.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        context.strokePath()
    }
}

final class ShutterButton: UIControl {
    private let centerShape = UIView()
    private let ring = UIView()
    private var recording = false
    var mode: CaptureMode = .photo { didSet { update(animated: false) } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityLabel = "Capture photo"
        isAccessibilityElement = true
        ring.isUserInteractionEnabled = false; centerShape.isUserInteractionEnabled = false
        ring.layer.borderWidth = 4; ring.layer.borderColor = UIColor.white.cgColor
        addSubview(ring); addSubview(centerShape)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic UI") }
    override func layoutSubviews() { super.layoutSubviews(); update(animated: false) }
    override var isHighlighted: Bool {
        didSet { UIView.animate(withDuration: 0.12) { self.alpha = self.isHighlighted ? 0.65 : 1 } }
    }
    func setRecording(_ recording: Bool) { self.recording = recording; update(animated: true) }
    private func update(animated: Bool) {
        ring.frame = bounds.insetBy(dx: 2, dy: 2); ring.layer.cornerRadius = ring.bounds.width / 2
        let changes = {
            let inset: CGFloat = self.recording ? 24 : 10
            self.centerShape.frame = self.bounds.insetBy(dx: inset, dy: inset)
            self.centerShape.layer.cornerRadius = self.recording ? 6 : self.centerShape.bounds.width / 2
            self.centerShape.backgroundColor = self.mode == .video ? UIColor(red: 1, green: 0.24, blue: 0.3, alpha: 1) : .white
        }
        if animated { UIView.animate(withDuration: 0.2, animations: changes) } else { changes() }
        accessibilityLabel = recording ? "Stop recording" : (mode == .video ? "Start recording" : (mode == .motion ? "Capture motion photo" : "Capture photo"))
    }
}

extension UIViewController {
    func showMessage(_ message: String, settings: Bool = false) {
        guard presentedViewController == nil, viewIfLoaded?.window != nil else { return }
        let alert = UIAlertController(title: "MirrorCam", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        if settings {
            alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            })
        }
        present(alert, animated: true)
    }
}
