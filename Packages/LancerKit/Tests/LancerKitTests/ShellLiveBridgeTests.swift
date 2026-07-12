#if os(iOS)
import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import AppFeature
@testable import SessionFeature

/// Regressions for the lane-V chat-loop robustness review:
/// 1. stale in-flight poll must not repopulate transcript after `resetForNewThread`
/// 2. rapid concurrent `retryLastAttempt` must single-flight (one dispatch)
@MainActor
@Suite("ShellLiveBridge")
struct ShellLiveBridgeTests {

    private func makeBridge(repo: ChatConversationRepository) -> ShellLiveBridge {
        ShellLiveBridge(
            relayFleetStore: RelayFleetStore(connectionStates: ConnectionStateStore()),
            conversationSyncCoordinator: ConversationSyncCoordinator(chatRepo: repo),
            chatRepo: repo
        )
    }

    private func seedRunningTurn(
        repo: ChatConversationRepository,
        conversationID: String = "conv-stale",
        runID: String = "run-stale"
    ) async throws {
        _ = try await repo.upsertConversationMirror(
            ChatConversation(
                id: conversationID,
                title: "T",
                agentID: "claudeCode",
                hostName: "h",
                hostID: nil,
                cwd: "/proj"
            ),
            lastHostSeq: 2,
            syncState: .synced
        )
        _ = try await repo.upsertTurnMirror(
            ChatTurn(
                id: "turn-stale",
                conversationID: conversationID,
                ordinal: 0,
                prompt: "hello",
                runID: runID,
                status: .running,
                assistantText: "partial"
            ),
            vendorSessionID: nil,
            hostSeqStart: nil,
            hostSeqEnd: nil
        )
    }

    @Test("stale poll refresh does not repopulate transcriptTurns after resetForNewThread")
    func stalePollDoesNotRepopulateTranscriptAfterReset() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        try await seedRunningTurn(repo: repo)
        let bridge = makeBridge(repo: repo)

        let holdEntered = AsyncGate()
        let allowWrite = AsyncGate()
        bridge.testPostTranscriptFetchHold = {
            await holdEntered.open()
            await allowWrite.wait()
        }

        let conversationID = "conv-stale"
        let runID = "run-stale"
        let transport = ConversationTransport(
            append: { _ in
                ConversationAppendResponse(status: "started", conversationId: conversationID)
            },
            fetch: { _ in
                // Force the refresh path into the catch so the loop still
                // reaches refreshTranscript on the first tick.
                struct TestRefreshError: Error {}
                throw TestRefreshError()
            },
            archive: { req in
                ConversationArchiveResponse(ok: true, conversationId: req.conversationId)
            }
        )

        let pollTask = Task { @MainActor in
            await bridge.testPollUntilTerminal(
                runID: runID,
                conversationID: conversationID,
                transport: transport
            )
        }

        await holdEntered.wait()
        #expect(bridge.testSessionEpoch == 0)
        bridge.resetForNewThread()
        #expect(bridge.transcriptTurns.isEmpty)
        #expect(bridge.testSessionEpoch == 1)

        await allowWrite.open()
        pollTask.cancel()
        await pollTask.value

        #expect(bridge.transcriptTurns.isEmpty)
        #expect(bridge.sendState == .idle)
    }

    @Test("concurrent retryLastAttempt claims the dispatch gate once")
    func concurrentRetrySingleFlights() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let bridge = makeBridge(repo: repo)
        bridge.markHydrated()
        bridge.testArmLastAttempt(.newConversation(prompt: "retry me", cwd: "/proj"))

        let gateClaimed = AsyncGate()
        let allowDispatch = AsyncGate()
        bridge.testAfterRetryGateClaimed = {
            await gateClaimed.open()
            await allowDispatch.wait()
        }

        async let first: Void = bridge.retryLastAttempt()
        await gateClaimed.wait()

        async let second: Void = bridge.retryLastAttempt()
        // Let the second attempt observe the in-flight gate before releasing.
        try await Task.sleep(nanoseconds: 50_000_000)
        await allowDispatch.open()

        await first
        await second

        #expect(bridge.testRetryGateClaimCount == 1)
        // No paired machine → single dispatch fails closed once.
        guard case .failed = bridge.sendState else {
            Issue.record("expected .failed after the single retry dispatch, got \(bridge.sendState)")
            return
        }
    }
}

/// One-shot async gate for coordinating MainActor test races.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
#endif
