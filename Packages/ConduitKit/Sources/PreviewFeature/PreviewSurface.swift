#if canImport(WebKit) && canImport(UIKit)
import SwiftUI
import WebKit
import PreviewKit
import SSHTransport
import DesignSystem

public struct PreviewSurface: UIViewRepresentable {
    public let session: SSHSession
    public let remotePort: Int

    public init(session: SSHSession, remotePort: Int) {
        self.session = session
        self.remotePort = remotePort
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let handler = SSHProxyURLSchemeHandler(session: session, remotePort: remotePort)
        config.setURLSchemeHandler(handler, forURLScheme: "conduit-preview")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "conduit-preview://localhost/")!))
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}
}

public struct PreviewView: View {
    public let session: SSHSession
    public let remotePort: Int
    public init(session: SSHSession, remotePort: Int) {
        self.session = session; self.remotePort = remotePort
    }
    public var body: some View {
        PreviewSurface(session: session, remotePort: remotePort)
            .navigationTitle("localhost:\(remotePort)")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Smart Preview (M6)

/// A full-screen preview view with automatic port detection and a toolbar
/// for selecting ports and viewport presets.
public struct SmartPreviewView: View {
    @State private var vm = PreviewViewModel()
    public let session: SSHSession

    public init(session: SSHSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            PreviewToolbar(vm: $vm, session: session)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            if let port = vm.activePort {
                PreviewSurface(session: session, remotePort: port)
                    .id(vm.reloadToken)  // force full reload on token change
            } else {
                ContentUnavailableView(
                    "No dev server detected",
                    systemImage: "network.slash",
                    description: Text(
                        "Start a dev server on the remote and tap the antenna button to detect it."
                    )
                )
            }
        }
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.detectPorts(session: session) }
    }
}
#endif
