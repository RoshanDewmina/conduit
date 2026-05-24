import Foundation
import SSHTransport

/// A lightweight value type that encapsulates a remote port's identity for
/// use with `SSHProxyURLSchemeHandler`. For M6 the transport is the
/// curl-over-SSH handler; M7 will upgrade to a NIO direct-tcpip tunnel.
///
/// Engine module — no UIKit/SwiftUI imports.
public actor LocalPortForward {
    // MARK: - State

    private(set) public var localPort: Int = 0
    private var _session: SSHSession?
    private var _remotePort: Int = 0

    public init() {}

    // MARK: - Lifecycle

    /// Prepare the forwarding context. For the M6 curl-over-SSH implementation
    /// this is a no-op: the `SSHProxyURLSchemeHandler` is stateless and handles
    /// its own channel lifecycle per request.
    ///
    /// - Parameters:
    ///   - remoteHost: Hostname as seen from the SSH server (usually "localhost").
    ///   - remotePort: Port of the remote dev server.
    ///   - session: An active `SSHSession`.
    public func start(
        remoteHost: String,
        remotePort: Int,
        session: SSHSession
    ) async throws {
        _session = session
        _remotePort = remotePort
        // In M6 we re-use the scheme-handler approach, so no actual TCP listener
        // is needed. The local "port" is a virtual value used to build the
        // conduit-preview:// URL.
        localPort = remotePort
    }

    /// Tears down any resources. No-op for M6.
    public func stop() async {
        _session = nil
        localPort = 0
    }

    // MARK: - URL

    /// The URL that `WKWebView` should load to render the remote dev server.
    public var localURL: URL {
        URL(string: "conduit-preview://localhost/")!
    }
}
