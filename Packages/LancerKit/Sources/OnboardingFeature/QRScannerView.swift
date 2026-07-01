#if os(iOS)
import SwiftUI
@preconcurrency import AVFoundation
import VisionKit

/// Camera-based QR scanner.
///
/// Prefers VisionKit's `DataScannerViewController` (live, high-quality) and
/// falls back to a raw `AVCaptureSession` + `AVCaptureMetadataOutput` pipeline
/// on devices/OS where the data scanner is unavailable. The Simulator has no
/// camera, so both paths report unavailable there — callers must offer a
/// manual-code entry fallback (see `OnboardingScanScreen`'s `onEnterCodeInstead`).
struct QRScannerView: View {
    /// Called with the decoded QR string on the first successful scan.
    var onScan: (String) -> Void
    /// Called when the camera is unavailable (Simulator, no permission, no hardware).
    var onUnavailable: (String) -> Void

    var body: some View {
        Group {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                DataScannerContainer(onScan: onScan, onUnavailable: onUnavailable)
            } else if AVCaptureScannerView.isCameraAvailable {
                AVCaptureScannerView(onScan: onScan, onUnavailable: onUnavailable)
            } else {
                UnavailablePlaceholder(onUnavailable: onUnavailable)
            }
        }
    }
}

private struct UnavailablePlaceholder: View {
    var onUnavailable: (String) -> Void
    var body: some View {
        Color.black
            .onAppear { onUnavailable("No camera available on this device.") }
    }
}

// MARK: - VisionKit path

private struct DataScannerContainer: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onUnavailable: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !context.coordinator.didScan else { return }
        do {
            try controller.startScanning()
        } catch {
            onUnavailable("Could not start the camera: \(error.localizedDescription)")
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private(set) var didScan = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems, in: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item], in: dataScanner)
        }

        private func handle(_ items: [RecognizedItem], in scanner: DataScannerViewController) {
            guard !didScan else { return }
            for case let .barcode(barcode) in items {
                if let payload = barcode.payloadStringValue {
                    didScan = true
                    scanner.stopScanning()
                    onScan(payload)
                    return
                }
            }
        }
    }
}

// MARK: - AVFoundation fallback path

private struct AVCaptureScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onUnavailable: (String) -> Void

    static var isCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> AVScannerController {
        let controller = AVScannerController()
        controller.coordinator = context.coordinator
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ controller: AVScannerController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        private var didScan = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScan,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue
            else { return }
            didScan = true
            onScan(value)
        }
    }
}

private final class AVScannerController: UIViewController {
    var coordinator: AVCaptureScannerView.Coordinator?
    var onUnavailable: ((String) -> Void)?

    // Mutated only on `sessionQueue`; the @MainActor controller hands it to that
    // queue's @Sendable closures, so opt out of the isolation check explicitly.
    private nonisolated(unsafe) let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "dev.lancer.qrscanner")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            onUnavailable?("Could not access the camera.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onUnavailable?("Could not configure QR scanning.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }
}
#endif
