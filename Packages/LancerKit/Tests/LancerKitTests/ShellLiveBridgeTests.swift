#if os(iOS)
import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import AppFeature
@testable import SessionFeature
@testable import SSHTransport
@testable import SecurityKit

/// Regressions for the lane-V chat-loop robustness review:
/// 1. stale in-flight poll must not repopulate transcript after `resetForNewThread`
/// 2. rapid concurrent `retryLastAttempt` must single-flight (one dispatch)
/// 3. empty observed-transcript adopt exposes `.adoptedNoHistory`, not bare `.idle`
@MainActor
@Suite("ShellLiveBridge")
struct ShellLiveBridgeTests {

    private func makeBridge(
        repo: ChatConversationRepository,
        relayFleetStore: RelayFleetStore = RelayFleetStore(connectionStates: ConnectionStateStore())
    ) -> ShellLiveBridge {
        ShellLiveBridge(
            relayFleetStore: relayFleetStore,
            conversationSyncCoordinator: ConversationSyncCoordinator(chatRepo: repo),
            chatRepo: repo
        )
    }

    private func makeConnectedMachine(
        into store: RelayFleetStore
    ) -> (machine: RelayFleetStore.Machine, client: E2ERelayClient) {
        RelayMachineMigration.indexKeychain = Keychain(
            service: "dev.lancer.relay.test.\(UUID().uuidString)",
            inMemory: true
        )
        let relayURL = URL(string: "https://relay.example.com")!
        let client = E2ERelayClient(relayURL: relayURL, pairingCode: "111222")
        let bridge = E2ERelayBridge(
            relayClient: client,
            approvalRelay: ApprovalRelay(),
            machineID: client.machineID
        )
        let record = RelayMachineRecord(id: client.machineID, displayName: "Test Machine")
        let machine = RelayFleetStore.Machine(record: record, client: client, bridge: bridge)
        store.add(machine)
        client.setStateForTesting(pairing: .paired, connection: .connected)
        return (machine, client)
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
        bridge.testArmLastAttempt(
            .newConversation(prompt: "retry me", cwd: "/proj", clientTurnId: "stable-turn-1")
        )

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

    @Test("adopt with empty transcript exposes adoptedNoHistory, not bare idle")
    func adoptEmptyTranscriptExposesNoHistoryState() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        _ = makeConnectedMachine(into: store)
        let bridge = makeBridge(repo: repo, relayFleetStore: store)
        bridge.markHydrated()
        bridge.armObservedContinue(vendor: "claudeCode", sessionId: "sess-empty", cwd: "/proj")
        bridge.testRelayFetchTranscript = { sessionId, _ in
            #expect(sessionId == "sess-empty")
            return (messages: [], nextLine: 0, resetRequired: false)
        }

        await bridge.adoptArmedObservedContinue(fallbackCwd: "/proj")

        #expect(bridge.sendState == .adoptedNoHistory)
        #expect(bridge.sendState != .idle)
        #expect(bridge.transcriptTurns.isEmpty)
        #expect(bridge.activeConversationID == "observed:sess-empty")
        #expect(bridge.canAcceptFollowUp)
        #expect(!bridge.isSendInFlight)
    }

    @Test("adopt with transcript history leaves sendState idle")
    func adoptWithHistoryLeavesIdle() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        _ = makeConnectedMachine(into: store)
        let bridge = makeBridge(repo: repo, relayFleetStore: store)
        bridge.markHydrated()
        bridge.armObservedContinue(vendor: "claudeCode", sessionId: "sess-hist", cwd: "/proj")
        bridge.testRelayFetchTranscript = { _, _ in
            (
                messages: [
                    SessionMessage(role: .user, text: "hello"),
                    SessionMessage(role: .assistant, text: "hi"),
                ],
                nextLine: 2,
                resetRequired: false
            )
        }

        await bridge.adoptArmedObservedContinue(fallbackCwd: "/proj")

        #expect(bridge.sendState == .idle)
        #expect(bridge.transcriptTurns.count == 1)
        #expect(bridge.activeConversationID == "observed:sess-hist")
    }

    @Test("retry reuses the same clientTurnId and attachment refs")
    func retryPreservesClientTurnIdAndAttachments() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let bridge = makeBridge(repo: repo)
        let digest = String(repeating: "ab", count: 32)
        let refs = [
            ConversationAttachmentReference(
                id: "srv-1", name: "photo.jpg", mimeType: "image/jpeg",
                byteCount: 12, kind: .image,
                hostPath: "/host/objects/\(digest)",
                previewCacheKey: "draft-uuid",
                contentDigest: digest
            )
        ]
        let turnId = "stable-client-turn"
        bridge.testArmLastAttempt(
            .newConversation(
                prompt: "see image",
                cwd: "/proj",
                attachments: refs,
                clientTurnId: turnId
            )
        )
        if case .newConversation(_, _, let storedRefs, let storedId) = bridge.lastAttempt {
            #expect(storedId == turnId)
            #expect(storedRefs == refs)
        } else {
            Issue.record("expected armed newConversation attempt")
        }

        // Two automatic retries without a machine still leave the same attempt identity.
        await bridge.retryLastAttempt()
        await bridge.retryLastAttempt()
        if case .newConversation(let prompt, let cwd, let retryRefs, let retryId) = bridge.lastAttempt {
            #expect(prompt == "see image")
            #expect(cwd == "/proj")
            #expect(retryId == turnId)
            #expect(retryRefs == refs)
            #expect(retryRefs.first?.id == "srv-1")
            #expect(retryRefs.first?.contentDigest == digest)
            #expect(retryRefs.first?.previewCacheKey == "draft-uuid")
        } else {
            Issue.record("expected lastAttempt to retain clientTurnId after retries")
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
