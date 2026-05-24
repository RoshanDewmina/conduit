#if os(iOS)
import SwiftUI
import Observation
import WebKit
import PreviewKit
import SSHTransport
import ConduitCore

@MainActor @Observable
public final class PreviewViewModel {
    public var detectedPorts: [Int] = []
    public var selectedPort: Int? = nil
    public var manualPortText: String = ""
    public var isDetecting: Bool = false
    public var viewportPreset: ViewportPreset = .iPhone
    public var reloadToken: UUID = UUID()

    public enum ViewportPreset: String, CaseIterable, Sendable {
        case iPhone = "iPhone"
        case iPad = "iPad"
        case desktop = "Desktop"

        public var size: CGSize {
            switch self {
            case .iPhone:  CGSize(width: 390, height: 844)
            case .iPad:    CGSize(width: 1024, height: 1366)
            case .desktop: CGSize(width: 1440, height: 900)
            }
        }
    }

    public var activePort: Int? {
        selectedPort ?? detectedPorts.first
    }

    public var remoteHost: String = "localhost"

    public init() {}

    public func detectPorts(session: SSHSession) async {
        isDetecting = true
        defer { isDetecting = false }
        let detector = PortDetector(session: session)
        detectedPorts = (try? await detector.detect()) ?? []
        if selectedPort == nil {
            selectedPort = detectedPorts.first
        }
    }

    public func reload() {
        reloadToken = UUID()
    }

    public func captureScreenshot(from webView: WKWebView?, insertInto composer: ((String) -> Void)?) {
        guard let webView else { return }
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { image, error in
            guard let image, error == nil else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-\(UUID()).png")
            if let data = image.pngData() {
                try? data.write(to: url)
            }
            DispatchQueue.main.async {
                composer?("[screenshot: \(url.lastPathComponent)] ")
            }
        }
    }
}
#endif
