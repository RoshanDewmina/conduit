#if os(iOS)
import Testing
import Foundation
import LancerCore
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

    @Test("relayFetchConversation throws timedOut when no response arrives")
    func relayFetchConversationTimesOutWithoutResponse() async {
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
            _ = try await bridge.relayFetchConversation(
                ConversationFetchRequest(conversationId: "conv-1", sinceSeq: 0, limit: 200)
            )
        }
    }

    @Test("stop clears an in-flight conversationsFetch continuation")
    func stopClearsConversationsFetchContinuation() async {
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
        bridge.boundedRPCWaitTimeoutOverride = .seconds(5)
        bridge.start()

        client.setStateForTesting(pairing: .paired, connection: .connected)
        for _ in 0..<10 where bridge.isActive == false {
            await Task.yield()
        }
        #expect(bridge.isActive)

        let fetchTask = Task {
            try await bridge.relayFetchConversation(
                ConversationFetchRequest(conversationId: "conv-stop", sinceSeq: 0, limit: 200)
            )
        }
        await Task.yield()
        await Task.yield()
        bridge.stop()

        await #expect(throws: E2EError.notPaired) {
            _ = try await fetchTask.value
        }
    }
}
#endif
