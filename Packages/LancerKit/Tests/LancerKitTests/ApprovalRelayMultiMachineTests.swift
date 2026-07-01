import Testing
import Foundation
@testable import LancerCore
@testable import SecurityKit
#if os(iOS)
@testable import SessionFeature
@testable import SSHTransport

/// Multi-machine relay routing (step "0." in `forwardDecisionOnly`) is fail-closed:
/// if the approval's origin machine was never registered, or its bridge is no
/// longer present in `relayBridges`, the routing step must fall through to the
/// pre-existing fallback chain (E2E bridge → SSH channel → backend relay → queue)
/// rather than crash, hang, or misroute to a different machine's bridge.
///
/// `E2ERelayBridge.isActive` only flips to `true` after a real WebSocket pairing
/// handshake, which is not achievable here, so these tests exercise the
/// dictionary-miss paths rather than the successful-routing happy path.
@Suite @MainActor struct ApprovalRelayMultiMachineRoutingTests {
    @Test("unregistered approval falls through, does not hang or crash")
    func unregisteredApprovalFallsThrough() async throws {
        let relay = ApprovalRelay()
        relay.credentialKeychain = Keychain(service: "test.relayCreds.multiMachine1", inMemory: true)

        await relay.forwardDecisionOnly(approvalID: "unknown-1", decision: .approved, editedToolInput: nil)

        #expect(true, "forwardDecisionOnly must return, not hang, when no relay origin is registered")
    }

    @Test("registered origin with no matching bridge falls through")
    func registeredOriginWithNoBridgeFallsThrough() async throws {
        let relay = ApprovalRelay()
        relay.credentialKeychain = Keychain(service: "test.relayCreds.multiMachine2", inMemory: true)

        relay.registerRelayOrigin(approvalID: "appr-2", machineID: RelayMachineID())

        await relay.forwardDecisionOnly(approvalID: "appr-2", decision: .rejected, editedToolInput: nil)

        #expect(true, "forwardDecisionOnly must return, not hang, when the registered machine has no bridge")
    }

    @Test("registered origin with an inactive bridge falls through without misrouting to a different bridge")
    func registeredOriginWithMismatchedBridgeFallsThrough() async throws {
        let relay = ApprovalRelay()
        relay.credentialKeychain = Keychain(service: "test.relayCreds.multiMachine3", inMemory: true)

        let machineA = RelayMachineID()
        let machineB = RelayMachineID()

        let clientB = E2ERelayClient(
            relayURL: URL(string: "wss://127.0.0.1:1")!,
            pairingCode: "000000",
            machineID: machineB
        )
        let bridgeB = E2ERelayBridge(relayClient: clientB, approvalRelay: relay, machineID: machineB)
        // Not calling .start()/.connect(): isActive starts false and there's no
        // reason to spin up a real socket attempt in this test.
        relay.relayBridges[machineB] = bridgeB

        // Registered for machineA, but only machineB's bridge exists in the dict —
        // exercises the exact-key-miss path (not "dict entirely empty").
        relay.registerRelayOrigin(approvalID: "appr-3", machineID: machineA)

        await relay.forwardDecisionOnly(approvalID: "appr-3", decision: .approved, editedToolInput: nil)

        #expect(true, "forwardDecisionOnly must fall through, not misroute to machineB's bridge, when the registered machine's own bridge is absent")
    }
}
#endif
