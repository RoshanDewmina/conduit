#if DEBUG && os(iOS)
import SwiftUI
import SessionFeature

/// Debug-only harness that brings up the **real** `SessionView` +
/// `SessionViewModel` against a live SSH host, so the Warp-style block
/// pipeline (PTYBridge → OSC 133 → blocks, alt-screen → raw escalation) runs
/// end-to-end. Driven by the same env vars as `DebugTerminalHarness`:
///
/// ```
/// xcrun simctl launch booted dev.lancer.mobile \
///   SIMCTL_CHILD_LANCER_TEST_HOST=127.0.0.1 \
///   SIMCTL_CHILD_LANCER_TEST_USER=roshansilva \
///   SIMCTL_CHILD_LANCER_TEST_PW="$(security find-generic-password -s lancer-localhost-ssh -w)"
/// ```
///
/// Auto-trusts the first host key (in-memory store, fresh each launch) so the
/// test is plug-and-play; production paths keep the TOFU confirmation sheet.
public struct DebugSessionHarness: View {
    @State private var vm: SessionViewModel
    @State private var started = false

    public init() {
        let env = ProcessInfo.processInfo.environment
        let hostname = env["LANCER_TEST_HOST"] ?? "127.0.0.1"
        let port = Int(env["LANCER_TEST_PORT"] ?? "22") ?? 22
        let user = env["LANCER_TEST_USER"] ?? "roshansilva"
        let pw = env["LANCER_TEST_PW"] ?? ""
        _vm = State(initialValue: SessionViewModel.debugPasswordSession(
            name: "\(user)@\(hostname)",
            hostname: hostname,
            port: port,
            username: user,
            password: pw,
            // Optional command auto-run on connect (e.g. LANCER_TEST_AUTOCMD="ls -la"),
            // so blocks form without typing. Goes through the unified shell → OSC 133.
            startupCommand: env["LANCER_TEST_AUTOCMD"]
        ))
    }

    public var body: some View {
        SessionWorkspaceContainer(viewModel: vm, onSwitchHost: {})
            .task {
                guard !started else { return }
                started = true
                await vm.connect()
                // Localhost first-connect: auto-trust the unknown host key, then
                // the reconnect in trustHostKey() establishes the session.
                if vm.pendingHostKeyFingerprint != nil {
                    await vm.trustHostKey()
                }
            }
    }
}
#endif
