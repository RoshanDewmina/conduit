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
#endif
