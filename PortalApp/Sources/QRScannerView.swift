import AVFoundation
import SwiftUI
import VisionKit

/// QRScannerView shows the camera and reports the text of each QR code it sees. It uses the system's data scanner where the device
/// offers it, and an AVFoundation capture session otherwise.
struct QRScannerView: View {
    let onPayload: @MainActor (String) -> Void

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScannerRepresentable(onPayload: onPayload)
        } else {
            CaptureSessionRepresentable(onPayload: onPayload)
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onPayload: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: @MainActor (String) -> Void

        init(onPayload: @escaping @MainActor (String) -> Void) { self.onPayload = onPayload }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue { onPayload(text) }
            }
        }
    }
}

/// CaptureSessionBox holds the capture session so it can be started and stopped off the main thread.
private final class CaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}

private struct CaptureSessionRepresentable: UIViewControllerRepresentable {
    let onPayload: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> CaptureViewController {
        let controller = CaptureViewController()
        controller.onPayload = onPayload
        return controller
    }

    func updateUIViewController(_ controller: CaptureViewController, context: Context) {
        controller.onPayload = onPayload
    }
}

private final class CaptureViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onPayload: @MainActor (String) -> Void = { _ in }
    private let box = CaptureSessionBox()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var isConfigured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.session = box.session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        configure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard isConfigured else { return }
        let box = box
        DispatchQueue.global(qos: .userInitiated).async { box.session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let box = box
        DispatchQueue.global(qos: .userInitiated).async { box.session.stopRunning() }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
        let output = AVCaptureMetadataOutput()
        guard box.session.canAddInput(input), box.session.canAddOutput(output) else { return }
        box.session.addInput(input)
        box.session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        if output.availableMetadataObjectTypes.contains(.qr) { output.metadataObjectTypes = [.qr] }
        isConfigured = true
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let texts = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard !texts.isEmpty else { return }
        MainActor.assumeIsolated {
            for text in texts { onPayload(text) }
        }
    }
}
