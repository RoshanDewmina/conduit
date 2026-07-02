import Testing
import Foundation
@testable import LancerCore
@testable import SecurityKit
#if os(iOS)
@testable import SessionFeature
@testable import SSHTransport

/// `CommandGateway` is the UI-independent entry point AppIntents use to reach
/// pause/resume/cancel/status when no live `RunControlStore`/view model is in
/// scope. These tests exercise its transport-priority fallback the same way
/// `ApprovalRelayMultiMachineTests` exercises `ApprovalRelay`'s: `E2ERelayBridge
/// .isActive` only flips true after a real WebSocket pairing handshake, which
/// isn't achievable in a unit test, so these cover the "no transport" /
/// "transport present but inactive" fallthrough paths rather than the
/// successful-send happy path.
@Suite @MainActor struct CommandGatewayTests {
    @Test("no channel and no relay bridge: pause/resume/cancel report transportUnavailable, do not hang")
    func noTransportRunControl() async throws {
        let relay = ApprovalRelay()
        relay.credentialKeychain = Keychain(service: "test.commandGateway.noTransport1", inMemory: true)
        let gateway = CommandGateway(approvalRelay: relay)

        #expect(await gateway.execute(.pause(runId: "r1")) == .transportUnavailable)
        #expect(await gateway.execute(.resume(runId: "r1")) == .transportUnavailable)
        #expect(await gateway.execute(.cancel(runId: "r1")) == .transportUnavailable)
    }

    @Test("no channel and no relay bridge: queryStatus reports transportUnavailable, does not hang")
    func noTransportStatusQuery() async throws {
        let relay = ApprovalRelay()
        relay.credentialKeychain = Keychain(service: "test.commandGateway.noTransport2", inMemory: true)
        let gateway = CommandGateway(approvalRelay: relay)

        #expect(await gateway.execute(.queryStatus(homeDir: nil)) == .transportUnavailable)
    }

    @Test("a relay bridge that never paired (isActive false) is not sent to — falls through to transportUnavailable")
    func inactiveBridgeFallsThrough() async throws {
        let relay = ApprovalRelay()
        relay.credentialKeychain = Keychain(service: "test.commandGateway.inactiveBridge", inMemory: true)
        let client = E2ERelayClient(relayURL: URL(string: "wss://127.0.0.1:1")!, pairingCode: "000000")
        let bridge = E2ERelayBridge(relayClient: client, approvalRelay: relay)
        // Not calling .start(): isActive starts false and there's no reason to
        // spin up a real socket attempt in this test (same rationale as
        // ApprovalRelayMultiMachineTests' registeredOriginWithMismatchedBridgeFallsThrough).
        relay.e2eBridge = bridge

        let gateway = CommandGateway(approvalRelay: relay)
        #expect(await gateway.execute(.pause(runId: "r2")) == .transportUnavailable)
        #expect(await gateway.execute(.resume(runId: "r2")) == .transportUnavailable)
        #expect(await gateway.execute(.cancel(runId: "r2")) == .transportUnavailable)
        #expect(await gateway.execute(.queryStatus(homeDir: "/tmp")) == .transportUnavailable)
    }
}
#endif
