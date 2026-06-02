#if DEBUG && os(iOS)
import SwiftUI
import SessionFeature

/// Debug-only harness that brings up the new SwiftTerm-based `LiveTerminalView`
/// against a real SSH host. Driven entirely by env vars injected at launch, so
/// no secret lives in source:
///
/// ```
/// xcrun simctl launch booted dev.conduit.mobile \
///   SIMCTL_CHILD_CONDUIT_TERMINAL_TEST=1 \
///   SIMCTL_CHILD_CONDUIT_TEST_HOST=127.0.0.1 \
///   SIMCTL_CHILD_CONDUIT_TEST_USER=roshansilva \
///   SIMCTL_CHILD_CONDUIT_TEST_PW="$(security find-generic-password -s conduit-localhost-ssh -w)"
/// ```
public struct DebugTerminalHarness: View {
    private let model: LiveTerminalModel

    public init() {
        let env = ProcessInfo.processInfo.environment
        let hostname = env["CONDUIT_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(env["CONDUIT_TEST_PORT"] ?? "22") ?? 22
        let user = env["CONDUIT_TEST_USER"] ?? "roshansilva"
        let pw = env["CONDUIT_TEST_PW"] ?? ""
        model = LiveTerminalModel.passwordSession(
            name: "\(user)@\(hostname)",
            hostname: hostname,
            port: port,
            username: user,
            password: pw,
            // Debug harness against a local sshd: trust the first-seen host key
            // automatically so the test is plug-and-play. Production paths keep
            // the default (false) and still prompt via the TOFU sheet.
            autoTrustHostKey: true,
            // Optional scripted command on connect (e.g. CONDUIT_TEST_AUTOCMD="tput cols").
            autoCommand: env["CONDUIT_TEST_AUTOCMD"]
        )
    }

    public var body: some View {
        LiveTerminalView(model: model)
    }
}
#endif
