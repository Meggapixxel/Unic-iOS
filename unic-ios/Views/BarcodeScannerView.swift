import SwiftUI
import UIKit
@preconcurrency import AVFoundation
import AudioToolbox

/// SwiftUI wrapper around `BarcodeScannerViewController`.
/// Fires `onScan` exactly once per presentation with the decoded barcode string.
struct BarcodeScannerView: UIViewControllerRepresentable {
    /// Called on the main actor with the first successfully decoded barcode value.
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}

    func makeCoordinator() -> Void {}
}

/// UIKit view controller that manages an `AVCaptureSession` for barcode scanning.
/// Triggers haptic feedback on a successful scan and stops the session to prevent multiple callbacks.
final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    /// Called exactly once with the decoded barcode string.
    var onScan: ((String) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        setupOverlay()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasScanned = false
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async { session?.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func setupSession() {
        let session = AVCaptureSession()
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            showPermissionError()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean13, .ean8, .code128, .code39, .upce, .pdf417, .qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        captureSession = session
        previewLayer = preview
    }

    private func setupOverlay() {
        let overlay = ScannerOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func showPermissionError() {
        DispatchQueue.main.async {
            let label = UILabel()
            label.text = NSLocalizedString("barcode_no_camera", comment: "")
            label.textColor = .white
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 32),
                label.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -32)
            ])
        }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        MainActor.assumeIsolated {
            guard !hasScanned, let value else { return }
            hasScanned = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            captureSession?.stopRunning()
            onScan?(value)
        }
    }
}

private final class ScannerOverlayView: UIView {
    private let cutoutSize = CGSize(width: 260, height: 160)

    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(rect)

        let cutout = CGRect(
            x: (rect.width - cutoutSize.width) / 2,
            y: (rect.height - cutoutSize.height) / 2 - 20,
            width: cutoutSize.width,
            height: cutoutSize.height
        )
        ctx.clear(cutout)

        let color = UIColor.systemGreen.cgColor
        ctx.setStrokeColor(color)
        ctx.setLineWidth(3)
        let len: CGFloat = 20
        let r = cutout

        ctx.move(to: CGPoint(x: r.minX, y: r.minY + len)); ctx.addLine(to: CGPoint(x: r.minX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.minX + len, y: r.minY))
        ctx.move(to: CGPoint(x: r.maxX - len, y: r.minY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + len))
        ctx.move(to: CGPoint(x: r.minX, y: r.maxY - len)); ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.minX + len, y: r.maxY))
        ctx.move(to: CGPoint(x: r.maxX - len, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY - len))
        ctx.strokePath()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }
}
