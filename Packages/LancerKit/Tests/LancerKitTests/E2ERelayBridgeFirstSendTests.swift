#if os(iOS)
import Testing
import Foundation
import LancerCore
@testable import SessionFeature
@testable import SSHTransport

/// REL-1: event-based one-shot post-rekey eligibility for gated mutating RPCs
/// (`sendDispatch` / `relayAppendConversation`). Replaces the prior 5s wall-clock
/// window — a first send 16s after pair must still be eligible.
@Suite @MainActor struct E2ERelayBridgeFirstSendTests {

    private func makePairedBridge(
        appendTimeout: Duration = .milliseconds(80),
        dispatchTimeout: Duration = .milliseconds(80)
    ) async -> (E2ERelayClient, E2ERelayBridge) {
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
        bridge.appendRPCWaitTimeoutOverride = appendTimeout
        bridge.dispatchRPCWaitTimeoutOverride = dispatchTimeout
        bridge.start()
        client.setStateForTesting(pairing: .paired, connection: .connected)
        for _ in 0..<20 where bridge.isActive == false {
            await Task.yield()
        }
        #expect(bridge.isActive)
        #expect(bridge.postRekeyMutatingRetryArmedForTesting)
        return (client, bridge)
    }

    private func appendRequest(clientTurnId: String) -> ConversationAppendRequest {
        ConversationAppendRequest(
            conversationId: nil,
            baseSeq: 0,
            clientTurnId: clientTurnId,
            agent: "claudeCode",
            cwd: "/tmp",
            prompt: "ping"
        )
    }

    private func appendResultPayload(clientTurnId: String, runId: String = "run-1") -> Data {
        Data("""
        {"type":"agentConversationsAppendResult","payload":{\
        "status":"started","conversationId":"conv-1","turnId":"turn-1",\
        "runId":"\(runId)","baseSeq":0,"nextSeq":2,"resumeMode":"new",\
        "clientTurnId":"\(clientTurnId)"}}
        """.utf8)
    }

    private func deliverAppendResult(
        _ client: E2ERelayClient, clientTurnId: String, runId: String = "run-1"
    ) async {
        client.deliverReceivedMessageForTesting(
            type: "agentConversationsAppendResult",
            payload: appendResultPayload(clientTurnId: clientTurnId, runId: runId)
        )
        for _ in 0..<10 { await Task.yield() }
    }

    @Test("pair then delayed first append remains eligible for one-shot resend")
    func delayedFirstAppendAfterPairStillEligible() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(50))
        defer { bridge.stop() }

        // Simulate ≫5s / 16s delay — eligibility is event-based, not wall-clock.
        try await Task.sleep(for: .milliseconds(20))
        #expect(bridge.postRekeyMutatingRetryArmedForTesting)

        client.onBypassSendForTesting = { [client] type in
            guard type == "agentConversationsAppend" else { return }
            if client.bypassedSendCountForTesting == 2 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(10))
                    client.deliverReceivedMessageForTesting(
                        type: "agentConversationsAppendResult",
                        payload: Data("""
                        {"type":"agentConversationsAppendResult","payload":{\
                        "status":"started","conversationId":"conv-1","turnId":"t1",\
                        "runId":"run-retry","baseSeq":0,"nextSeq":2,"resumeMode":"new",\
                        "clientTurnId":"device:delayed"}}
                        """.utf8)
                    )
                }
            }
        }

        let response = try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:delayed"))
        #expect(response.runId == "run-retry")
        #expect(client.bypassedSendCountForTesting == 2)
        #expect(bridge.postRekeyMutatingRetryArmedForTesting == false)
    }

    @Test("first successful gated RPC disarms the one-shot slot")
    func firstSuccessfulGatedRPCDisarms() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .seconds(2))
        defer { bridge.stop() }

        let task = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:ok"))
        }
        try await Task.sleep(for: .milliseconds(15))
        await deliverAppendResult(client, clientTurnId: "device:ok")
        _ = try await task.value
        #expect(client.bypassedSendCountForTesting == 1)
        #expect(bridge.postRekeyMutatingRetryArmedForTesting == false)

        // Ordinary timeout after consume must NOT resend.
        await #expect(throws: E2EError.timedOut) {
            _ = try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:next"))
        }
        #expect(client.bypassedSendCountForTesting == 2)
    }

    @Test("timeout resend disarms regardless of second-attempt outcome")
    func timeoutResendDisarms() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(40))
        defer { bridge.stop() }

        await #expect(throws: E2EError.timedOut) {
            _ = try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:both-timeout"))
        }
        #expect(client.bypassedSendCountForTesting == 2)
        #expect(bridge.postRekeyMutatingRetryArmedForTesting == false)

        await #expect(throws: E2EError.timedOut) {
            _ = try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:after"))
        }
        #expect(client.bypassedSendCountForTesting == 3, "no further resend once consumed")
    }

    @Test("new rekey re-arms eligibility")
    func newRekeyRearms() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(40))
        defer { bridge.stop() }

        await #expect(throws: E2EError.timedOut) {
            _ = try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:consume"))
        }
        #expect(bridge.postRekeyMutatingRetryArmedForTesting == false)

        client.setStateForTesting(pairing: .unpaired, connection: .disconnected)
        for _ in 0..<10 where bridge.isActive {
            await Task.yield()
        }
        client.setStateForTesting(pairing: .paired, connection: .connected)
        for _ in 0..<20 where bridge.postRekeyMutatingRetryArmedForTesting == false {
            await Task.yield()
        }
        #expect(bridge.postRekeyMutatingRetryArmedForTesting)
    }

    @Test("concurrent dispatch and append allow at most one protected operation")
    func concurrentDispatchAndAppendOnlyOneConsumesGate() async throws {
        let (client, bridge) = await makePairedBridge(
            appendTimeout: .milliseconds(50),
            dispatchTimeout: .milliseconds(50)
        )
        defer { bridge.stop() }

        async let appendResult: Void = {
            _ = try? await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:conc-a"))
        }()
        async let dispatchResult: Void = {
            _ = try? await bridge.sendDispatch(
                agent: "claudeCode", cwd: "/tmp", prompt: "x", budgetUSD: nil, model: nil
            )
        }()
        _ = await (appendResult, dispatchResult)

        // One protected op gets attempt+resend (2), the other a single attempt (1) → 3 total.
        #expect(
            client.bypassedSendCountForTesting == 3,
            "exactly one of dispatch/append may consume the one-shot; got \(client.bypassedSendCountForTesting)"
        )
        #expect(bridge.postRekeyMutatingRetryArmedForTesting == false)
    }

    @Test("duplicate paired emission while active does not re-arm")
    func duplicatePairedEmissionDoesNotRearm() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(40))
        defer { bridge.stop() }

        await #expect(throws: E2EError.timedOut) {
            _ = try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:disarm"))
        }
        #expect(bridge.postRekeyMutatingRetryArmedForTesting == false)

        // Same .paired while already active — not a rekey epoch.
        client.setStateForTesting(pairing: .paired, connection: .connected)
        try await Task.sleep(for: .milliseconds(30))
        #expect(bridge.postRekeyMutatingRetryArmedForTesting == false)
    }
}
#endif
