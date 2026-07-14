#if os(iOS)
import Testing
import Foundation
import LancerCore
@testable import SessionFeature
@testable import SSHTransport

/// Correlated append resume: clientTurnId echo + epoch-guarded waits so late /
/// mismatched / missing results never resolve the wrong waiter.
@Suite @MainActor struct E2ERelayBridgeAppendResumeTests {

    private func makePairedBridge(
        appendTimeout: Duration = .milliseconds(80),
        armRetry: Bool = true
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
        bridge.start()
        client.setStateForTesting(pairing: .paired, connection: .connected)
        for _ in 0..<20 where bridge.isActive == false {
            await Task.yield()
        }
        #expect(bridge.isActive)
        if !armRetry {
            bridge.disarmPostRekeyMutatingRetryForTesting()
        }
        return (client, bridge)
    }

    private func appendRequest(clientTurnId: String) -> ConversationAppendRequest {
        ConversationAppendRequest(
            conversationId: nil,
            baseSeq: 0,
            clientTurnId: clientTurnId,
            agent: "claudeCode",
            cwd: "/tmp",
            prompt: "Reply with exactly reconnect-ok. Do not use tools."
        )
    }

    private func appendResultPayload(
        clientTurnId: String?,
        status: String = "started",
        conversationId: String = "conv-resume-1",
        turnId: String = "turn-1",
        runId: String = "run-1"
    ) -> Data {
        let idField: String
        if let clientTurnId {
            idField = #""clientTurnId":"\#(clientTurnId)","#
        } else {
            idField = ""
        }
        return Data("""
        {"type":"agentConversationsAppendResult","payload":{\
        "status":"\(status)","conversationId":"\(conversationId)",\
        "turnId":"\(turnId)","runId":"\(runId)","baseSeq":0,"nextSeq":2,\
        \(idField)"resumeMode":"new"}}
        """.utf8)
    }

    private func appendErrorResultPayload(
        clientTurnId: String?,
        error: String
    ) -> Data {
        let idField: String
        if let clientTurnId {
            idField = #""clientTurnId":"\#(clientTurnId)","#
        } else {
            idField = ""
        }
        return Data("""
        {"type":"agentConversationsAppendResult","payload":{\
        "status":"","conversationId":"","baseSeq":0,"nextSeq":0,\
        \(idField)"error":"\(error)"}}
        """.utf8)
    }

    private func deliverAppendResult(
        _ client: E2ERelayClient,
        clientTurnId: String?,
        runId: String = "run-1"
    ) async {
        client.deliverReceivedMessageForTesting(
            type: "agentConversationsAppendResult",
            payload: appendResultPayload(clientTurnId: clientTurnId, runId: runId)
        )
        for _ in 0..<10 { await Task.yield() }
    }

    @Test("first append after re-key completes from matching agentConversationsAppendResult")
    func firstAppendAfterRekeyCompletesFromAppendResult() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .seconds(2))
        defer { bridge.stop() }

        let request = appendRequest(clientTurnId: "device:resume-1")
        let task = Task {
            try await bridge.relayAppendConversation(request)
        }
        try await Task.sleep(for: .milliseconds(20))
        await deliverAppendResult(client, clientTurnId: "device:resume-1")

        let response = try await task.value
        #expect(response.status == "started")
        #expect(response.conversationId == "conv-resume-1")
        #expect(response.runId == "run-1")
        #expect(response.clientTurnId == "device:resume-1")
        #expect(client.bypassedSendCountForTesting == 1)
    }

    @Test("dropped first append result after re-key retries once with same clientTurnId")
    func droppedFirstAppendResultRetriesOnceIdempotently() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(60))
        defer { bridge.stop() }

        client.onBypassSendForTesting = { [client] type in
            guard type == "agentConversationsAppend" else { return }
            if client.bypassedSendCountForTesting == 2 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(15))
                    client.deliverReceivedMessageForTesting(
                        type: "agentConversationsAppendResult",
                        payload: Data("""
                        {"type":"agentConversationsAppendResult","payload":{\
                        "status":"started","conversationId":"conv-resume-1",\
                        "turnId":"turn-1","runId":"run-replay","baseSeq":0,"nextSeq":2,\
                        "resumeMode":"new","clientTurnId":"device:resume-idempotent"}}
                        """.utf8)
                    )
                }
            }
        }

        let request = appendRequest(clientTurnId: "device:resume-idempotent")
        let response = try await bridge.relayAppendConversation(request)
        #expect(response.status == "started")
        #expect(response.runId == "run-replay")
        #expect(client.bypassedSendCountForTesting == 2)
    }

    @Test("same-id late attempt-1 result may resolve attempt-2")
    func sameIdLateAttempt1ResolvesAttempt2() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(50))
        defer { bridge.stop() }

        var firstAttemptTimedOut = false
        client.onBypassSendForTesting = { [client] type in
            guard type == "agentConversationsAppend" else { return }
            if client.bypassedSendCountForTesting == 1 {
                Task { @MainActor in
                    // Arrive after attempt-1 timeout / during attempt-2 wait.
                    try? await Task.sleep(for: .milliseconds(80))
                    firstAttemptTimedOut = true
                    client.deliverReceivedMessageForTesting(
                        type: "agentConversationsAppendResult",
                        payload: Data("""
                        {"type":"agentConversationsAppendResult","payload":{\
                        "status":"started","conversationId":"conv-1","turnId":"t1",\
                        "runId":"run-late-same","baseSeq":0,"nextSeq":2,"resumeMode":"new",\
                        "clientTurnId":"device:same-late"}}
                        """.utf8)
                    )
                }
            }
        }

        let response = try await bridge.relayAppendConversation(
            appendRequest(clientTurnId: "device:same-late")
        )
        #expect(response.runId == "run-late-same")
        #expect(client.bypassedSendCountForTesting == 2)
        #expect(firstAttemptTimedOut)
    }

    @Test("late A during wait B is dropped — B still times out")
    func lateADuringBDoesNotResolveWrongWaiter() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(50), armRetry: false)
        defer { bridge.stop() }

        let first = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:A"))
        }
        await #expect(throws: E2EError.timedOut) {
            _ = try await first.value
        }
        #expect(client.bypassedSendCountForTesting == 1)

        let second = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:B"))
        }
        try await Task.sleep(for: .milliseconds(10))
        // Late result for A while B is waiting — must not complete B.
        await deliverAppendResult(client, clientTurnId: "device:A", runId: "run-late-A")

        await #expect(throws: E2EError.timedOut) {
            _ = try await second.value
        }
        #expect(client.bypassedSendCountForTesting == 2)
    }

    @Test("echoed host error with matching clientTurnId resumes as RelayConversationError.host")
    func echoedHostErrorWithMatchingClientTurnIdResumesPromptly() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .seconds(2), armRetry: false)
        defer { bridge.stop() }

        let pending = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:host-err"))
        }
        try await Task.sleep(for: .milliseconds(15))
        client.deliverReceivedMessageForTesting(
            type: "agentConversationsAppendResult",
            payload: appendErrorResultPayload(
                clientTurnId: "device:host-err",
                error: "cwd must be an absolute path"
            )
        )
        for _ in 0..<10 { await Task.yield() }

        do {
            _ = try await pending.value
            Issue.record("expected RelayConversationError.host, got success")
        } catch let RelayConversationError.host(message) {
            #expect(message == "cwd must be an absolute path")
        } catch {
            Issue.record("expected RelayConversationError.host, got \(error)")
        }
    }

    @Test("host error without clientTurnId echo still times out (fail-closed)")
    func hostErrorWithoutClientTurnIdEchoStillTimesOut() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(60), armRetry: false)
        defer { bridge.stop() }

        let pending = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:legacy-err"))
        }
        try await Task.sleep(for: .milliseconds(15))
        client.deliverReceivedMessageForTesting(
            type: "agentConversationsAppendResult",
            payload: appendErrorResultPayload(
                clientTurnId: nil,
                error: "conversation store unavailable"
            )
        )
        for _ in 0..<10 { await Task.yield() }

        await #expect(throws: E2EError.timedOut) {
            _ = try await pending.value
        }
    }

    @Test("missing clientTurnId on result is fail-closed (does not resolve waiter)")
    func missingClientTurnIdDoesNotResolveWaiter() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(60), armRetry: false)
        defer { bridge.stop() }

        let pending = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:legacy"))
        }
        try await Task.sleep(for: .milliseconds(15))
        await deliverAppendResult(client, clientTurnId: nil, runId: "run-legacy")

        await #expect(throws: E2EError.timedOut) {
            _ = try await pending.value
        }
    }

    @Test("mismatched clientTurnId on result is dropped")
    func mismatchedClientTurnIdIsDropped() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .milliseconds(60), armRetry: false)
        defer { bridge.stop() }

        let pending = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:expected"))
        }
        try await Task.sleep(for: .milliseconds(15))
        await deliverAppendResult(client, clientTurnId: "device:other", runId: "run-mismatch")

        await #expect(throws: E2EError.timedOut) {
            _ = try await pending.value
        }
    }

    @Test("stop releases an in-flight append waiter exactly once")
    func stopReleasesAppendWaiter() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .seconds(5), armRetry: false)

        let pending = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:stop"))
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(client.bypassedSendCountForTesting == 1)

        bridge.stop()

        await #expect(throws: E2EError.notPaired) {
            _ = try await pending.value
        }
    }

    @Test("two sequential appends each require their own matching result")
    func twoSequentialAppendsAreDeterministic() async throws {
        let (client, bridge) = await makePairedBridge(appendTimeout: .seconds(2), armRetry: false)
        defer { bridge.stop() }

        let first = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:seq-1"))
        }
        try await Task.sleep(for: .milliseconds(15))
        await deliverAppendResult(client, clientTurnId: "device:seq-1", runId: "run-1")
        let r1 = try await first.value
        #expect(r1.runId == "run-1")

        let second = Task {
            try await bridge.relayAppendConversation(appendRequest(clientTurnId: "device:seq-2"))
        }
        try await Task.sleep(for: .milliseconds(15))
        await deliverAppendResult(client, clientTurnId: "device:seq-2", runId: "run-2")
        let r2 = try await second.value
        #expect(r2.runId == "run-2")
        #expect(client.bypassedSendCountForTesting == 2)
    }
}
#endif
