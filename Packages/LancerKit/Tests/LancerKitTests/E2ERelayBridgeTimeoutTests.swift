#if os(iOS)
import Testing
import Foundation
@testable import SessionFeature
@testable import SSHTransport

@Suite @MainActor struct E2ERelayBridgeTimeoutTests {
    @Test("relayListSessions throws timedOut when no response arrives")
    func relayListSessionsTimesOutWithoutResponse() async {
        let client = E2ERelayClient(
            relayURL: URL(string: "https://relay.example.com")!,
            pairingCode: "111222"
        )
        client.bypassSendForTesting = true
        let bridge = E2ERelayBridge(
            relayClient: client,
            approvalRelay: ApprovalRelay(),
            machineID: client.machineID
        )
        bridge.boundedRPCWaitTimeoutOverride = .milliseconds(50)
        bridge.start()
        defer { bridge.stop() }

        client.setStateForTesting(pairing: .paired, connection: .connected)
        for _ in 0..<10 where bridge.isActive == false {
            await Task.yield()
        }
        #expect(bridge.isActive)

        await #expect(throws: E2EError.timedOut) {
            _ = try await bridge.relayListSessions()
        }
    }
}
#endif
