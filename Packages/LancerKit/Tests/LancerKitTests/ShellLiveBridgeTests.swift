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
        // Force the legacy tail-transcript path (attach unavailable in this stub).
        bridge.testRelayAttachObservedSession = { _, _, _ in
            ConversationAttachObservedSessionResponse(error: "forced-fallback")
        }
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
        bridge.testRelayAttachObservedSession = { _, _, _ in
            ConversationAttachObservedSessionResponse(error: "forced-fallback")
        }
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

    @Test("adopt prefers attachObservedSession and hydrates ledger turns, not the tail transcript")
    func adoptPrefersAttachObservedSessionFullHistory() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conversationID = "conv-attached-full"
        _ = try await repo.upsertConversationMirror(
            ChatConversation(
                id: conversationID,
                title: "Desktop session",
                agentID: "claudeCode",
                hostName: "Mac",
                hostID: nil,
                cwd: "/proj"
            ),
            lastHostSeq: 4,
            syncState: .synced
        )
        // Seed two turns so refresh stub can return empty while local mirror
        // already holds the full history (attach already imported on host).
        _ = try await repo.upsertTurnMirror(
            ChatTurn(
                id: "turn-1",
                conversationID: conversationID,
                ordinal: 0,
                prompt: "first",
                runID: "run-1",
                status: .completed,
                assistantText: "one"
            ),
            vendorSessionID: "sess-full",
            hostSeqStart: 1,
            hostSeqEnd: 2
        )
        _ = try await repo.upsertTurnMirror(
            ChatTurn(
                id: "turn-2",
                conversationID: conversationID,
                ordinal: 1,
                prompt: "second",
                runID: "run-2",
                status: .completed,
                assistantText: "two"
            ),
            vendorSessionID: "sess-full",
            hostSeqStart: 3,
            hostSeqEnd: 4
        )

        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        _ = makeConnectedMachine(into: store)
        let bridge = makeBridge(repo: repo, relayFleetStore: store)
        bridge.markHydrated()
        bridge.armObservedContinue(vendor: "claudeCode", sessionId: "sess-full", cwd: "/proj")

        var attachCalled = false
        var transcriptCalled = false
        bridge.testRelayAttachObservedSession = { vendor, sessionId, cwd in
            attachCalled = true
            #expect(vendor == "claudeCode")
            #expect(sessionId == "sess-full")
            #expect(cwd == "/proj")
            return ConversationAttachObservedSessionResponse(
                conversationId: conversationID,
                importedEvents: 4,
                lastSeq: 4,
                alreadyAttached: false
            )
        }
        bridge.testTransportOverride = ConversationTransport(
            append: { _ in ConversationAppendResponse(status: "started", conversationId: conversationID) },
            fetch: { req in
                #expect(req.conversationId == conversationID)
                return ConversationFetchResponse(
                    conversation: ConversationSummary(
                        id: conversationID,
                        title: "Desktop session",
                        provider: "claudeCode",
                        agentID: "claudeCode",
                        hostName: "Mac",
                        cwd: "/proj",
                        state: "active",
                        source: "observed",
                        createdAt: "2026-07-16T00:00:00Z",
                        updatedAt: "2026-07-16T00:00:00Z",
                        lastActivityAt: "2026-07-16T00:00:00Z",
                        lastSeq: 4,
                        lastTurnStatus: "completed"
                    ),
                    nextSeq: 4,
                    hasMore: false
                )
            },
            archive: { req in ConversationArchiveResponse(ok: true, conversationId: req.conversationId) }
        )
        bridge.testRelayFetchTranscript = { _, _ in
            transcriptCalled = true
            // Tail would only return one turn — must not be used when attach works.
            return (
                messages: [SessionMessage(role: .user, text: "tail-only")],
                nextLine: 1,
                resetRequired: false
            )
        }

        await bridge.adoptArmedObservedContinue(fallbackCwd: "/proj")

        #expect(attachCalled)
        #expect(!transcriptCalled, "full-history attach must not fall back to tail transcript")
        #expect(bridge.sendState == .idle)
        #expect(bridge.activeConversationID == conversationID)
        #expect(bridge.transcriptTurns.count == 2)
        #expect(bridge.transcriptTurns.map(\.prompt) == ["first", "second"])
        #expect(bridge.boundObservedContinue?.sessionId == "sess-full")
        #expect(bridge.canAcceptFollowUp)
    }

    /// Regression for the 10x reconnect re-proof duplicate-prompt-bubble bug:
    /// `pollUntilTerminal` used to call `refreshTranscript` (which writes
    /// `transcriptTurns` to already show the turn `.completed`) BEFORE
    /// checking `turnByRunID` and flipping `sendState`/`inFlightPrompt` — a
    /// real await-window where `transcriptTurns` said "completed" while
    /// `sendState` still said "working". `LiveThreadView.liveTurnID`'s
    /// `.working` case resolved to `nil` in that window (no turn is
    /// `.running` anymore), so the just-finished turn rendered via BOTH the
    /// frozen-history path and the live in-flight path — duplicate prompt
    /// bubble + phantom "Working…" from one single turn.
    ///
    /// This test forces the exact ordering that used to be buggy — using
    /// `testPostTranscriptFetchHold` to pause mid-`refreshTranscript`, after
    /// the DB fetch resolves but before the `transcriptTurns` write lands —
    /// and asserts `sendState`/`inFlightPrompt` have ALREADY flipped to the
    /// terminal state by that point, proving the ordering fix rather than
    /// just a narrower race window.
    @Test("pollUntilTerminal flips sendState before the transcript write lands, closing the race")
    func pollUntilTerminalFlipsSendStateBeforeTranscriptWrite() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conversationID = "conv-race"
        let runID = "run-race"

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
                id: "turn-race",
                conversationID: conversationID,
                ordinal: 0,
                prompt: "hello",
                runID: runID,
                status: .completed,
                assistantText: "the full reply"
            ),
            vendorSessionID: nil,
            hostSeqStart: nil,
            hostSeqEnd: nil
        )

        let bridge = makeBridge(repo: repo)

        let holdEntered = AsyncGate()
        let allowWrite = AsyncGate()
        var sendStateAtHold: ShellLiveBridge.SendState?
        var inFlightPromptAtHold: String??
        var inFlightRunIDAtHold: String??
        var transcriptTurnsAtHold: [ChatTurn]?
        bridge.testPostTranscriptFetchHold = {
            sendStateAtHold = bridge.sendState
            inFlightPromptAtHold = bridge.inFlightPrompt
            inFlightRunIDAtHold = bridge.inFlightRunID
            transcriptTurnsAtHold = bridge.transcriptTurns
            await holdEntered.open()
            await allowWrite.wait()
        }

        let transport = ConversationTransport(
            append: { _ in
                ConversationAppendResponse(status: "started", conversationId: conversationID)
            },
            fetch: { _ in
                // Force the refresh path into the catch so the loop still
                // reaches the terminal-status decision on the first tick.
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

        // At the hold point, refreshTranscript's DB fetch has resolved but
        // the epoch-guarded `transcriptTurns` write has NOT happened yet
        // (transcriptTurnsAtHold is still the pre-poll empty array). Despite
        // that, sendState/inFlightPrompt must already reflect the terminal
        // turn — the fix's whole point.
        #expect(transcriptTurnsAtHold?.isEmpty == true)
        guard case .completed(let turnAtHold) = sendStateAtHold else {
            Issue.record("expected sendState already .completed at the hold, got \(String(describing: sendStateAtHold))")
            await allowWrite.open()
            pollTask.cancel()
            await pollTask.value
            return
        }
        #expect(turnAtHold.id == "turn-race")
        #expect(inFlightPromptAtHold == .some(.none))
        #expect(inFlightRunIDAtHold == .some(.none))

        await allowWrite.open()
        await pollTask.value

        #expect(bridge.sendState == .completed(turnAtHold))
        #expect(bridge.transcriptTurns.count == 1)
        #expect(bridge.transcriptTurns.first?.id == "turn-race")
        #expect(bridge.inFlightPrompt == nil)
        #expect(bridge.inFlightRunID == nil)

        // No-duplicate check mirroring LiveThreadView's liveTurnID/priorTurns
        // split: the turn bound to sendState must be excluded from the
        // "frozen history" set so it never renders twice.
        let liveTurnID = turnAtHold.id
        let priorTurns = LiveThreadTranscript.priorTurns(
            turns: bridge.transcriptTurns, liveTurnID: liveTurnID
        )
        #expect(priorTurns.isEmpty)
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

    /// Regression for the 2026-07-15 duplicate-turn investigation's Bug 2:
    /// `send`/`sendFollowUp` used to guard only on `isSendInFlight`, but
    /// `sendState` doesn't flip to `.working` until AFTER the (up to 8s)
    /// `waitForConnectedMachine` await returns — so two concurrent `send`
    /// calls could both pass the guard while `sendState` was still `.idle`
    /// and both reach the daemon. This test forces exactly that ordering
    /// (both calls parked past their dispatch-gate claim, before either
    /// resolves a machine) using `testAfterSendDispatchGateClaimed` — the
    /// same synchronization technique `concurrentRetrySingleFlights` above
    /// uses for `retryLastAttempt` — and asserts only the FIRST claims the
    /// gate and only ONE dispatch reaches the transport/coordinator.
    @Test("concurrent send() calls single-flight the dispatch, not just isSendInFlight")
    func concurrentSendSingleFlightsDispatch() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        _ = makeConnectedMachine(into: store)
        let bridge = makeBridge(repo: repo, relayFleetStore: store)
        bridge.markHydrated()

        struct DispatchTestError: Error {}
        let appendCallCount = CallCounter()
        bridge.testTransportOverride = ConversationTransport(
            append: { _ in
                await appendCallCount.increment()
                throw DispatchTestError()
            },
            fetch: { _ in throw DispatchTestError() },
            archive: { req in ConversationArchiveResponse(ok: true, conversationId: req.conversationId) }
        )

        let gateClaimed = AsyncGate()
        let allowDispatch = AsyncGate()
        bridge.testAfterSendDispatchGateClaimed = {
            await gateClaimed.open()
            await allowDispatch.wait()
        }

        async let first: Void = bridge.send(prompt: "hello", cwd: "/proj", clientTurnId: "turn-a")
        await gateClaimed.wait()

        // The second call races in while the first is parked past its gate
        // claim but before `sendState` has flipped to `.working` — exactly
        // the window Bug 2 exploited.
        async let second: Void = bridge.send(prompt: "hello", cwd: "/proj", clientTurnId: "turn-b")
        try await Task.sleep(nanoseconds: 50_000_000)
        await allowDispatch.open()

        await first
        await second

        #expect(bridge.testSendDispatchGateClaimCount == 1)
        // `ConversationSyncCoordinator.appendWithRetry` retries a throwing
        // `transport.append` up to 3 times (hardcoded `attempts: 3`) before
        // surfacing `.blocked` — so ONE logical dispatch here means exactly
        // 3 append calls. Without the Bug 2 fix, the second `send()` would
        // also have reached dispatch, doubling this to 6.
        #expect(await appendCallCount.value == 3)
    }

    @Test("needsApproval send enters awaitingApproval with runID and keeps polling")
    func needsApprovalSendEntersAwaitingApproval() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conversationID = "conv-await"
        let runID = "run-await"
        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        _ = makeConnectedMachine(into: store)
        let bridge = makeBridge(repo: repo, relayFleetStore: store)
        bridge.markHydrated()

        let holdEntered = AsyncGate()
        let allowWrite = AsyncGate()
        bridge.testPostTranscriptFetchHold = {
            await holdEntered.open()
            await allowWrite.wait()
        }

        bridge.testTransportOverride = ConversationTransport(
            append: { _ in
                ConversationAppendResponse(
                    status: "needsApproval",
                    conversationId: conversationID,
                    turnId: "turn-await",
                    runId: runID,
                    nextSeq: 1
                )
            },
            fetch: { _ in
                struct TestRefreshError: Error {}
                throw TestRefreshError()
            },
            archive: { req in
                ConversationArchiveResponse(ok: true, conversationId: req.conversationId)
            }
        )

        let sendTask = Task { @MainActor in
            await bridge.send(prompt: "rm -rf /", cwd: "/proj", clientTurnId: "client-await")
        }

        await holdEntered.wait()

        guard case .awaitingApproval(let message) = bridge.sendState else {
            Issue.record("expected .awaitingApproval, got \(bridge.sendState)")
            await allowWrite.open()
            bridge.resetForNewThread()
            await sendTask.value
            return
        }
        #expect(message.contains("approval"))
        #expect(bridge.inFlightRunID == runID)
        #expect(bridge.activeConversationID == conversationID)
        #expect(bridge.isSendInFlight)

        // Leave the turn running — poll must keep awaitingApproval (not flip to
        // .working / .failed). Then cancel so the test finishes.
        await allowWrite.open()
        try await Task.sleep(nanoseconds: 50_000_000)
        guard case .awaitingApproval = bridge.sendState else {
            Issue.record("expected still .awaitingApproval while running, got \(bridge.sendState)")
            bridge.resetForNewThread()
            await sendTask.value
            return
        }

        bridge.resetForNewThread()
        await sendTask.value
    }

    @Test("awaitingApproval poll completion flips to completed")
    func awaitingApprovalPollCompletionGoesCompleted() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conversationID = "conv-await-done"
        let runID = "run-await-done"

        _ = try await repo.upsertConversationMirror(
            ChatConversation(
                id: conversationID,
                title: "T",
                agentID: "claudeCode",
                hostName: "h",
                hostID: nil,
                cwd: "/proj"
            ),
            lastHostSeq: 1,
            syncState: .synced
        )
        _ = try await repo.upsertTurnMirror(
            ChatTurn(
                id: "turn-await-done",
                conversationID: conversationID,
                ordinal: 0,
                prompt: "hello",
                runID: runID,
                status: .completed,
                assistantText: "done after approve"
            ),
            vendorSessionID: nil,
            hostSeqStart: nil,
            hostSeqEnd: nil
        )

        let bridge = makeBridge(repo: repo)
        // Simulate the pre-poll awaiting card the send path would have set.
        bridge.testSetSendState(.awaitingApproval("Awaiting your approval — check the Inbox."))
        bridge.testSetInFlight(runID: runID, prompt: "hello")

        let transport = ConversationTransport(
            append: { _ in
                ConversationAppendResponse(status: "started", conversationId: conversationID)
            },
            fetch: { _ in
                struct TestRefreshError: Error {}
                throw TestRefreshError()
            },
            archive: { req in
                ConversationArchiveResponse(ok: true, conversationId: req.conversationId)
            }
        )

        await bridge.testPollUntilTerminal(
            runID: runID,
            conversationID: conversationID,
            transport: transport
        )

        guard case .completed(let turn) = bridge.sendState else {
            Issue.record("expected .completed, got \(bridge.sendState)")
            return
        }
        #expect(turn.runID == runID)
        #expect(turn.assistantText == "done after approve")
        #expect(bridge.inFlightRunID == nil)
    }

    @Test("awaitingApproval poll deny flips to failed with honest message")
    func awaitingApprovalPollDenyGoesFailed() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conversationID = "conv-await-deny"
        let runID = "run-await-deny"

        _ = try await repo.upsertConversationMirror(
            ChatConversation(
                id: conversationID,
                title: "T",
                agentID: "claudeCode",
                hostName: "h",
                hostID: nil,
                cwd: "/proj"
            ),
            lastHostSeq: 1,
            syncState: .synced
        )
        _ = try await repo.upsertTurnMirror(
            ChatTurn(
                id: "turn-await-deny",
                conversationID: conversationID,
                ordinal: 0,
                prompt: "rm -rf /",
                runID: runID,
                status: .failed,
                errorMessage: "Approval denied"
            ),
            vendorSessionID: nil,
            hostSeqStart: nil,
            hostSeqEnd: nil
        )

        let bridge = makeBridge(repo: repo)
        bridge.testSetSendState(.awaitingApproval("Awaiting your approval — check the Inbox."))
        bridge.testSetInFlight(runID: runID, prompt: "rm -rf /")

        let transport = ConversationTransport(
            append: { _ in
                ConversationAppendResponse(status: "started", conversationId: conversationID)
            },
            fetch: { _ in
                struct TestRefreshError: Error {}
                throw TestRefreshError()
            },
            archive: { req in
                ConversationArchiveResponse(ok: true, conversationId: req.conversationId)
            }
        )

        await bridge.testPollUntilTerminal(
            runID: runID,
            conversationID: conversationID,
            transport: transport
        )

        guard case .failed(let message) = bridge.sendState else {
            Issue.record("expected .failed, got \(bridge.sendState)")
            return
        }
        #expect(message == "Approval denied")
        #expect(bridge.inFlightRunID == nil)

        // Negative check: an unresolved awaiting state is NOT `.failed`.
        // If the deny path never resolved, this expectation would fail —
        // proving the test detects the bug it guards.
        let unresolved = ShellLiveBridge.SendState.awaitingApproval(
            "Awaiting your approval — check the Inbox."
        )
        #expect({
            if case .failed = unresolved { return true }
            return false
        }() == false)
        #expect(unresolved != bridge.sendState)
    }

    /// WP1 perf fix (2026-07-17): `refreshTranscript` used to reassign
    /// `transcriptTurns` on every `pollUntilTerminal` tick (~1s cadence)
    /// regardless of whether the DB read actually changed, republishing the
    /// whole transcript and re-triggering every downstream `@Observable`
    /// reader (e.g. `LiveThreadView`'s `receiptRefreshToken`, which itself
    /// re-fetches up to 10k events) even during a long-running live-follow
    /// where the host has nothing new to report. This proves the fix: over
    /// several real poll ticks of an unchanging `.running` turn, exactly one
    /// tick publishes (the first) and the rest are skipped.
    @Test("unchanging running turn: only the first poll tick republishes transcriptTurns")
    func unchangingRunningTurnSkipsRepublishAfterFirstTick() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conversationID = "conv-steady"
        let runID = "run-steady"

        _ = try await repo.upsertConversationMirror(
            ChatConversation(
                id: conversationID,
                title: "T",
                agentID: "claudeCode",
                hostName: "h",
                hostID: nil,
                cwd: "/proj"
            ),
            lastHostSeq: 1,
            syncState: .synced
        )
        _ = try await repo.upsertTurnMirror(
            ChatTurn(
                id: "turn-steady",
                conversationID: conversationID,
                ordinal: 0,
                prompt: "long-running task",
                runID: runID,
                status: .running,
                assistantText: ""
            ),
            vendorSessionID: nil,
            hostSeqStart: nil,
            hostSeqEnd: nil
        )

        let bridge = makeBridge(repo: repo)
        bridge.testSetSendState(.working)
        bridge.testSetInFlight(runID: runID, prompt: "long-running task")

        // Never mutates the DB — the turn stays `.running` with the same
        // content across every tick, exactly the "nothing new to report"
        // live-follow case the fix targets.
        let transport = ConversationTransport(
            append: { _ in
                ConversationAppendResponse(status: "started", conversationId: conversationID)
            },
            fetch: { _ in
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

        // LivePollPolicy.pollIntervalNanoseconds is 1s — sleep past several
        // ticks to observe real repeated polling, not just the first call.
        try await Task.sleep(nanoseconds: 3_300_000_000)
        bridge.resetForNewThread()
        pollTask.cancel()
        _ = await pollTask.value

        #expect(bridge.testTranscriptRefreshPublishCount == 1)
        #expect(bridge.testTranscriptRefreshSkipCount >= 2)
    }

    @Test("observed follow appends desktop-side activity to an open thread")
    func observedFollowAppendsDesktopActivity() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        _ = makeConnectedMachine(into: store)
        let bridge = makeBridge(repo: repo, relayFleetStore: store)
        bridge.markHydrated()
        bridge.testObservedFollowIntervalNanoseconds = 20_000_000
        bridge.armObservedContinue(vendor: "claudeCode", sessionId: "sess-follow", cwd: "/proj")
        bridge.testRelayAttachObservedSession = { _, _, _ in
            ConversationAttachObservedSessionResponse(error: "forced-fallback")
        }
        let initial = [
            SessionMessage(role: .user, text: "hello"),
            SessionMessage(role: .assistant, text: "hi"),
        ]
        let growth = [
            SessionMessage(role: .user, text: "desk follow-up"),
            SessionMessage(role: .assistant, text: "desk answer"),
        ]
        let served = ServedGrowth()
        bridge.testRelayFetchTranscript = { _, sinceLine in
            if sinceLine == 0 {
                return (messages: initial, nextLine: 2, resetRequired: false)
            }
            if sinceLine == 2, await served.claim() {
                return (messages: growth, nextLine: 4, resetRequired: false)
            }
            return (messages: [], nextLine: max(sinceLine, 4), resetRequired: false)
        }

        await bridge.adoptArmedObservedContinue(fallbackCwd: "/proj")
        #expect(bridge.transcriptTurns.count == 1)

        // Follow loop: baseline tick, then the growth tick appends a new turn.
        for _ in 0..<200 where bridge.transcriptTurns.count < 2 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(bridge.transcriptTurns.count == 2)
        let appended = try #require(bridge.transcriptTurns.last)
        #expect(appended.prompt == "desk follow-up")
        #expect(appended.assistantText == "desk answer")
        #expect(appended.id == "observedFollow:sess-follow:1")

        // Leaving the thread cancels the follow so no zombie poll survives.
        bridge.resetForNewThread()
        #expect(bridge.transcriptTurns.isEmpty)
    }
}

/// Serves observed-follow growth exactly once, actor-isolated for the Sendable
/// test transcript closure.
private actor ServedGrowth {
    private var served = false
    func claim() -> Bool {
        if served { return false }
        served = true
        return true
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
    @Test("liveActivityStatus maps in-flight states to running and terminals to nil")
    func liveActivityStatusMapping() {
        #expect(ShellLiveBridge.liveActivityStatus(for: .working) == "running")
        #expect(ShellLiveBridge.liveActivityStatus(for: .awaitingApproval("hold")) == "running")
        let turn = ChatTurn(
            id: "t1",
            conversationID: "c1",
            ordinal: 0,
            prompt: "p",
            runID: "r1",
            status: .running,
            assistantText: "partial"
        )
        #expect(ShellLiveBridge.liveActivityStatus(for: .streaming(turn)) == "running")
        #expect(ShellLiveBridge.liveActivityStatus(for: .degraded(message: "stale", turn: turn)) == "running")
        #expect(ShellLiveBridge.liveActivityStatus(for: .idle) == nil)
        #expect(ShellLiveBridge.liveActivityStatus(for: .adoptedNoHistory) == nil)
        #expect(ShellLiveBridge.liveActivityStatus(for: .completed(turn)) == nil)
        #expect(ShellLiveBridge.liveActivityStatus(for: .failed("boom")) == nil)
    }
}

/// Thread-safe call counter for asserting a transport closure fired exactly once.
private actor CallCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
#endif
