#if os(iOS)
import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import AppFeature

@Suite("ConversationSyncCoordinator")
struct ConversationSyncCoordinatorTests {

    private func makeTransport(
        append: @escaping @Sendable (ConversationAppendRequest) async throws -> ConversationAppendResponse = { _ in
            ConversationAppendResponse(status: "started", conversationId: "unused")
        },
        fetch: @escaping @Sendable (ConversationFetchRequest) async throws -> ConversationFetchResponse = { req in
            ConversationFetchResponse(conversation: ConversationSummary(
                id: req.conversationId, title: "T", provider: "claudeCode", agentID: "claudeCode",
                hostName: "h", cwd: "/proj", state: "active", source: "app",
                createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T00:00:00Z",
                lastActivityAt: "2026-07-02T00:00:00Z", lastSeq: 0
            ))
        },
        archive: @escaping @Sendable (ConversationArchiveRequest) async throws -> ConversationArchiveResponse = { req in
            ConversationArchiveResponse(ok: true, conversationId: req.conversationId)
        }
    ) -> ConversationTransport {
        ConversationTransport(append: append, fetch: fetch, archive: archive)
    }

    @Test("startConversation persists a synced mirror row and returns runID")
    func startConversationSuccess() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let transport = makeTransport(append: { request in
            #expect(request.conversationId == nil)
            #expect(request.prompt == "hello")
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 0, nextSeq: 2, resumeMode: "new"
            )
        })

        let outcome = await coordinator.startConversation(
            agent: "claudeCode", cwd: "/proj", prompt: "hello", model: nil, budgetUSD: nil,
            hostName: "MacBook Pro", hostID: "host-1", clientTurnID: "device-1:1", transport: transport
        )

        guard case .started(let started) = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        #expect(started.conversationID == "conv-1")
        #expect(started.runID == "run-1")
        #expect(started.baseSeqForNextTurn == 2)
        #expect(started.resumeMode == "new")

        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.syncState == .synced)
        #expect(mirrored?.lastHostSeq == 2)
        #expect(mirrored?.hostID == "host-1")
        #expect(mirrored?.agentID == "claudeCode")

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.runID == "run-1")
        #expect(turns.first?.clientTurnID == "device-1:1")

        let state = await coordinator.currentSyncState("conv-1")
        #expect(state == .synced)
    }

    @Test("startConversation with relay routing id persists it for follow-ups")
    func startConversationPersistsRelayRoutingID() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let machineID = "557A7877-F729-5031-9606-0E04F2B67822"
        let wireVendorCapture = WireVendorCapture()
        let transport = makeTransport(append: { request in
            await wireVendorCapture.set(request.agent)
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-relay", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 0, nextSeq: 2, resumeMode: "new"
            )
        })

        let outcome = await coordinator.startConversation(
            agent: "relay|\(machineID)|claudeCode", cwd: "/proj", prompt: "hello", model: nil, budgetUSD: nil,
            hostName: "Mac", hostID: machineID, clientTurnID: "device-1:1", transport: transport
        )
        guard case .started = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        #expect(await wireVendorCapture.value == "claudeCode")
        let mirrored = try await repo.conversation(id: "conv-relay")
        #expect(mirrored?.agentID == "relay|\(machineID)|claudeCode")
        #expect(mirrored?.vendor == "claudeCode")
    }

    @Test("startConversation with latestInCwdFallback resumeMode publishes degradedResume")
    func startConversationDegradedResume() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let transport = makeTransport(append: { _ in
            ConversationAppendResponse(
                status: "started", conversationId: "conv-1", runId: "run-1",
                cwd: "/proj", nextSeq: 2, resumeMode: "latestInCwdFallback"
            )
        })
        _ = await coordinator.startConversation(
            agent: "claudeCode", cwd: "/proj", prompt: "hi", model: nil, budgetUSD: nil,
            hostName: "h", hostID: nil, clientTurnID: "d:1", transport: transport
        )
        #expect(await coordinator.currentSyncState("conv-1") == .degradedResume)
    }

    @Test("continueConversation preserves existing agentID when request omits agent")
    func continueConversationPreservesAgent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)
        _ = try await repo.upsertTurnMirror(
            ChatTurn(id: "turn-0", conversationID: "conv-1", ordinal: 0, prompt: "hi", runID: "run-0", clientTurnID: "d:1"),
            vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let transport = makeTransport(append: { request in
            #expect(request.conversationId == "conv-1")
            #expect(request.agent == nil)
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                vendorSessionId: "sess-1", cwd: "/proj", baseSeq: 2, nextSeq: 4, resumeMode: "exact"
            )
        })

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 2, prompt: "follow up", clientTurnID: "d:2",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .started = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.agentID == "claudeCode")
        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 2)
        #expect(turns.last?.vendorSessionID == "sess-1")
    }

    @Test("conflict auto-recovers: stale baseSeq refetches then retries with fresh nextSeq")
    func conflictAutoRecoversOnce() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let appendCount = Counter()
        let transport = makeTransport(
            append: { request in
                let n = await appendCount.increment()
                if n == 1 {
                    #expect(request.baseSeq == 1)
                    return ConversationAppendResponse(
                        status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 7,
                        message: "Conversation changed. Refetch before appending."
                    )
                }
                #expect(request.baseSeq == 7)
                return ConversationAppendResponse(
                    status: "started", conversationId: "conv-1", turnId: "turn-2", runId: "run-2",
                    cwd: "/proj", baseSeq: 7, nextSeq: 9, resumeMode: "exact"
                )
            },
            fetch: { req in
                ConversationFetchResponse(
                    conversation: ConversationSummary(
                        id: req.conversationId, title: "T", provider: "claudeCode", agentID: "claudeCode",
                        hostName: "h", cwd: "/proj", state: "active", source: "app",
                        createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T01:00:00Z",
                        lastActivityAt: "2026-07-02T01:00:00Z", lastSeq: 7
                    ),
                    nextSeq: 7
                )
            }
        )

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "Thank you", clientTurnID: "d:3",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .started(let started) = outcome else {
            Issue.record("expected .started after conflict recovery, got \(outcome)")
            return
        }
        #expect(started.runID == "run-2")
        #expect(started.baseSeqForNextTurn == 9)
        #expect(await appendCount.value == 2)
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.lastHostSeq == 9)
        #expect(mirrored?.syncState == .synced)
        #expect(await coordinator.currentSyncState("conv-1") == .synced)
    }

    @Test("conflict after refetch and retry still conflicts surfaces runbook blocked message")
    func conflictDoubleBlocked() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let transport = makeTransport(
            append: { _ in
                ConversationAppendResponse(
                    status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 5,
                    message: "Conversation changed. Refetch before appending."
                )
            },
            fetch: { req in
                ConversationFetchResponse(
                    conversation: ConversationSummary(
                        id: req.conversationId, title: "T", provider: "claudeCode", agentID: "claudeCode",
                        hostName: "h", cwd: "/proj", state: "active", source: "app",
                        createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T01:00:00Z",
                        lastActivityAt: "2026-07-02T01:00:00Z", lastSeq: 5
                    ),
                    nextSeq: 5
                )
            }
        )

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "stale", clientTurnID: "d:3",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .blocked(let message) = outcome else {
            Issue.record("expected .blocked, got \(outcome)")
            return
        }
        #expect(message == "This conversation changed on another device. Refresh to catch up.")
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.syncState == .conflict)
        #expect(mirrored?.lastHostSeq == 5, "refetch should advance mirror seq before the retry conflict")
        #expect(await coordinator.currentSyncState("conv-1") == .conflict)
    }

    @Test("conflict when refetch throws blocks without retrying append")
    func conflictRefetchThrows() async throws {
        struct Boom: Error {}
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let appendCount = Counter()
        let transport = makeTransport(
            append: { _ in
                await appendCount.increment()
                return ConversationAppendResponse(
                    status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 5,
                    message: "stale baseSeq"
                )
            },
            fetch: { _ in throw Boom() }
        )

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "stale", clientTurnID: "d:3",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .blocked(let message) = outcome else {
            Issue.record("expected .blocked, got \(outcome)")
            return
        }
        #expect(message == "stale baseSeq")
        #expect(await appendCount.value == 1, "must not retry append when refetch fails")
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.syncState == .conflict)
        #expect(mirrored?.lastHostSeq == 2)
        #expect(await coordinator.currentSyncState("conv-1") == .conflict)
    }

    @Test("needsApproval and denied statuses surface as blocked without changing sync state")
    func needsApprovalAndDenied() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)

        let deniedTransport = makeTransport(append: { _ in
            ConversationAppendResponse(status: "denied", conversationId: "conv-1", rule: "no-network")
        })
        let deniedOutcome = await coordinator.startConversation(
            agent: "codex", cwd: "/proj", prompt: "curl evil.com", model: nil, budgetUSD: nil,
            hostName: "h", hostID: nil, clientTurnID: "d:1", transport: deniedTransport
        )
        guard case .blocked(let deniedMessage) = deniedOutcome else {
            Issue.record("expected .blocked")
            return
        }
        #expect(deniedMessage.contains("no-network"))

        let approvalTransport = makeTransport(append: { _ in
            ConversationAppendResponse(status: "needsApproval", conversationId: "conv-2")
        })
        let approvalOutcome = await coordinator.startConversation(
            agent: "codex", cwd: "/proj", prompt: "rm -rf /", model: nil, budgetUSD: nil,
            hostName: "h", hostID: nil, clientTurnID: "d:2", transport: approvalTransport
        )
        guard case .blocked(let approvalMessage) = approvalOutcome else {
            Issue.record("expected .blocked")
            return
        }
        #expect(approvalMessage.contains("approval"))
    }

    @Test("a transport failure marks the conversation hostOffline and returns blocked")
    func transportFailureMarksHostOffline() async throws {
        struct Boom: Error {}
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let transport = makeTransport(append: { _ in throw Boom() })
        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 2, prompt: "hi", clientTurnID: "d:1",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .blocked = outcome else {
            Issue.record("expected .blocked")
            return
        }
        #expect(await coordinator.currentSyncState("conv-1") == .hostOffline)
    }

    @Test("a transient transport failure on append recovers via retry instead of going hostOffline")
    func appendRetriesTransientFailureBeforeGivingUp() async throws {
        struct Blip: Error {}
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let attemptCount = Counter()
        let transport = makeTransport(append: { _ in
            let n = await attemptCount.increment()
            if n < 2 { throw Blip() } // fails once, succeeds on the retry
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 2, nextSeq: 4, resumeMode: "exact"
            )
        })

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 2, prompt: "follow up", clientTurnID: "d:2",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .started = outcome else {
            Issue.record("expected .started after the retry recovered, got \(outcome)")
            return
        }
        #expect(await attemptCount.value == 2, "should have retried exactly once before succeeding")
        #expect(await coordinator.currentSyncState("conv-1") == .synced, "a recovered append must not leave the conversation flagged hostOffline")
    }

    private actor Counter {
        private(set) var value = 0
        @discardableResult
        func increment() -> Int { value += 1; return value }
    }

    private actor WireVendorCapture {
        private(set) var value: String?
        func set(_ vendor: String?) { value = vendor }
    }

    @Test("refreshConversation merges conversation, turns, and events into the mirror")
    func refreshMergesFetchResponse() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "Old title", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let transport = makeTransport(fetch: { req in
            #expect(req.conversationId == "conv-1")
            #expect(req.sinceSeq == 0)
            return ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-1", title: "Fresh title from another device", provider: "claudeCode",
                    agentID: "claudeCode", hostName: "MacBook Pro", cwd: "/proj", state: "active",
                    source: "app", createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T01:00:00Z",
                    lastActivityAt: "2026-07-02T01:00:00Z", lastSeq: 4
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-2:1",
                        prompt: "hi from device 2", runId: "run-remote-1", provider: "claudeCode",
                        vendorSessionId: "sess-remote-1", status: "completed", startedAt: "2026-07-02T00:30:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(conversationId: "conv-1", seq: 1, kind: "prompt", role: "user", text: "hi from device 2", createdAt: "2026-07-02T00:30:00Z"),
                    ConversationEvent(conversationId: "conv-1", seq: 2, kind: "output", role: "assistant", text: "hello!", createdAt: "2026-07-02T00:31:00Z"),
                ],
                nextSeq: 4
            )
        })

        let nextSeq = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)
        #expect(nextSeq == 4)

        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.title == "Fresh title from another device")
        #expect(mirrored?.lastHostSeq == 4)
        #expect(mirrored?.syncState == .synced)

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.vendorSessionID == "sess-remote-1")

        let events = try await repo.events(conversationID: "conv-1")
        #expect(events.map(\.seq) == [1, 2])
    }

    @Test("refreshConversation maps host 'exited' turn status to .completed (not .running)")
    func refreshMapsExitedHostStatusToCompleted() async throws {
        // Daemon persist uses process-lifecycle "exited" on success. Phone
        // ChatTurn.Status has no "exited" case — rawValue decode used to fall
        // through to .running, so onPollThread never cleared Working… after a
        // successful live run when run.status events were missed.
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "hi", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/Users/roshansilva")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let transport = makeTransport(fetch: { _ in
            ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-1", title: "hi", provider: "claudeCode", agentID: "claudeCode",
                    hostName: "h", cwd: "/Users/roshansilva", state: "active", source: "phone",
                    createdAt: "2026-07-09T19:28:33Z", updatedAt: "2026-07-09T19:28:40Z",
                    lastActivityAt: "2026-07-09T19:28:40Z", lastSeq: 6
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-1:1",
                        prompt: "hi", runId: "run-exited-1", provider: "claudeCode",
                        vendorSessionId: "sess-1", status: "exited",
                        startedAt: "2026-07-09T19:28:33Z", completedAt: "2026-07-09T19:28:40Z"
                    ),
                ],
                events: [
                    ConversationEvent(conversationId: "conv-1", seq: 1, kind: "turn_started", createdAt: "2026-07-09T19:28:33Z"),
                    ConversationEvent(
                        conversationId: "conv-1", seq: 3, turnId: "turn-1", runId: "run-exited-1",
                        kind: "output", role: "assistant", stream: "stdout",
                        text: "Hey! How can I help you today?", createdAt: "2026-07-09T19:28:38Z"
                    ),
                    ConversationEvent(
                        conversationId: "conv-1", seq: 6, turnId: "turn-1", runId: "run-exited-1",
                        kind: "status", payloadJson: "{\"status\":\"exited\",\"exitCode\":0}",
                        createdAt: "2026-07-09T19:28:40Z"
                    ),
                ],
                nextSeq: 6
            )
        })

        _ = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.status == .completed)
        #expect(turns.first?.assistantText.contains("How can I help") == true)
    }

    // --- receipt materialization on reconnect (PR #34 review finding P2) ---
    //
    // The host stores a terminal `lancer.proof/v0` receipt ONLY as a
    // `conversation_events` row (kind "receipt" — see appendRunReceipt in
    // conversation_store.go). Live delivery turns it into a `chat_artifacts`
    // row via `upsertReceipt` (AppRoot's lancerE2ERunReceipt handler), but
    // before this fix, `mergeFetchResponse` only mirrored fetched events into
    // `chat_events` — never converting a `kind == "receipt"` event into an
    // artifact — so a receipt that arrived while the phone was disconnected
    // never appeared in ReceiptCardView (which reads exclusively from
    // `chat_artifacts`) even after a refresh.

    @Test("refreshConversation materializes a receipt-kind event into a chat_artifacts .receipt row")
    func refreshConversationMaterializesReceiptArtifact() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let receiptPayload = """
        {"schema":"lancer.proof/v0","runId":"run-remote-1","conversationId":"conv-1","agent":"claudeCode","status":"completed","exitCode":0}
        """
        let transport = makeTransport(fetch: { _ in
            ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-1", title: "T", provider: "claudeCode", agentID: "claudeCode",
                    hostName: "h", cwd: "/proj", state: "active", source: "app",
                    createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
                    lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 3
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-2:1",
                        prompt: "hi while phone was offline", runId: "run-remote-1", provider: "claudeCode",
                        status: "completed", startedAt: "2026-07-08T00:00:00Z", completedAt: "2026-07-08T00:01:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(conversationId: "conv-1", seq: 1, turnId: "turn-1", runId: "run-remote-1", kind: "prompt", role: "user", text: "hi while phone was offline", createdAt: "2026-07-08T00:00:00Z"),
                    ConversationEvent(conversationId: "conv-1", seq: 2, turnId: "turn-1", runId: "run-remote-1", kind: "output", role: "assistant", text: "done!", createdAt: "2026-07-08T00:00:30Z"),
                    ConversationEvent(conversationId: "conv-1", seq: 3, turnId: "turn-1", runId: "run-remote-1", kind: "receipt", payloadJson: receiptPayload, createdAt: "2026-07-08T00:01:00Z"),
                ],
                nextSeq: 3
            )
        })

        let nextSeq = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)
        #expect(nextSeq == 3)

        let artifacts = try await repo.artifacts(runID: "run-remote-1")
        #expect(artifacts.count == 1, "expected exactly one artifact materialized from the fetched receipt event")
        #expect(artifacts.first?.kind == .receipt)
        #expect(artifacts.first?.status == .done)
        #expect(artifacts.first?.id == "receipt:run-remote-1")
        #expect(artifacts.first?.payloadJSON.contains("lancer.proof/v0") == true)

        // The receipt event itself must still be mirrored into chat_events
        // like any other fetched event — materializing the artifact is
        // additive, not a replacement for the existing event mirror.
        let events = try await repo.events(conversationID: "conv-1")
        #expect(events.map(\.seq) == [1, 2, 3])
        #expect(events.first(where: { $0.kind == "receipt" })?.runID == "run-remote-1")
    }

    @Test("refetching the same receipt event does not duplicate the materialized artifact")
    func refreshConversationReceiptMaterializationIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let receiptPayload = """
        {"schema":"lancer.proof/v0","runId":"run-remote-2","conversationId":"conv-1","agent":"claudeCode","status":"completed","exitCode":0}
        """
        @Sendable func fetchResponse() -> ConversationFetchResponse {
            ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-1", title: "T", provider: "claudeCode", agentID: "claudeCode",
                    hostName: "h", cwd: "/proj", state: "active", source: "app",
                    createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
                    lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 1
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-2:1",
                        prompt: "hi", runId: "run-remote-2", provider: "claudeCode",
                        status: "completed", startedAt: "2026-07-08T00:00:00Z", completedAt: "2026-07-08T00:01:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(conversationId: "conv-1", seq: 1, turnId: "turn-1", runId: "run-remote-2", kind: "receipt", payloadJson: receiptPayload, createdAt: "2026-07-08T00:01:00Z"),
                ],
                nextSeq: 1
            )
        }
        let transport = makeTransport(fetch: { _ in fetchResponse() })

        _ = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)
        _ = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)

        let artifacts = try await repo.artifacts(runID: "run-remote-2")
        #expect(artifacts.count == 1, "re-fetching the same receipt event twice must not duplicate the artifact row")
    }

    @Test("mergeConversationSummaries creates mirror rows for conversations discovered via list")
    func mergeConversationSummariesCreatesMirrorRows() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)

        let summaries = [
            ConversationSummary(
                id: "conv-remote-1", title: "Started on Mac", provider: "claudeCode", agentID: "claudeCode",
                hostName: "MacBook Pro", cwd: "/proj", state: "active", source: "app",
                createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:05:00Z",
                lastActivityAt: "2026-07-08T00:05:00Z", lastSeq: 6
            ),
        ]
        await coordinator.mergeConversationSummaries(summaries, hostName: "MacBook Pro", hostID: "host-1")

        let mirrored = try await repo.conversation(id: "conv-remote-1")
        #expect(mirrored?.title == "Started on Mac")
        #expect(mirrored?.hostName == "MacBook Pro")
        #expect(mirrored?.lastHostSeq == 6)
        #expect(mirrored?.syncState == .synced)
    }

    @Test("mergeConversationSummaries never regresses lastHostSeq below the existing mirror value")
    func mergeConversationSummariesDoesNotRegressSeq() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 12, syncState: .synced)

        // A stale list summary reporting a lower lastSeq than what this
        // device already mirrored from a live turn (e.g. the daemon's list
        // cache hadn't caught up yet) must not roll the mirror backward.
        let staleSummary = ConversationSummary(
            id: "conv-1", title: "T (stale)", provider: "claudeCode", agentID: "claudeCode",
            hostName: "h", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 3
        )
        await coordinator.mergeConversationSummaries([staleSummary], hostName: "h", hostID: nil)

        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.lastHostSeq == 12, "list-based merge must never regress lastHostSeq")
    }

    @Test("mergeConversationSummaries never clobbers a stored relay routing agentID with a bare provider token")
    func mergeConversationSummariesPreservesRelayRoutingID() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let machineID = "557A7877-F729-5031-9606-0E04F2B67822"
        let seed = ChatConversation(
            id: "conv-relay", title: "T", agentID: "relay|\(machineID)|claudeCode",
            hostName: "Mac", hostID: machineID, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let summary = ConversationSummary(
            id: "conv-relay", title: "T (from list)", provider: "claudeCode", agentID: "claudeCode",
            hostID: machineID, hostName: "Mac", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 5
        )
        await coordinator.mergeConversationSummaries([summary], hostName: "Mac", hostID: machineID)

        let mirrored = try await repo.conversation(id: "conv-relay")
        #expect(mirrored?.agentID == "relay|\(machineID)|claudeCode", "must not clobber the stored routing id with the bare provider token")
        #expect(mirrored?.lastHostSeq == 5)
    }

    @Test("mergeConversationSummaries applies running→failed from enriched list lastTurnStatus")
    func mergeConversationSummariesAppliesRunningToFailed() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-orphan", title: "Orphaned", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)
        let running = ChatTurn(
            id: "turn-orphan", conversationID: "conv-orphan", ordinal: 0,
            prompt: "go", runID: "run-orphan", status: .running
        )
        _ = try await repo.upsertTurnMirror(
            running, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let summary = ConversationSummary(
            id: "conv-orphan", title: "Orphaned", provider: "claudeCode", agentID: "claudeCode",
            hostName: "Mac", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 2,
            lastTurnID: "turn-orphan", lastTurnStatus: "failed"
        )
        await coordinator.mergeConversationSummaries([summary], hostName: "Mac", hostID: nil)

        let turns = try await repo.turns(conversationID: "conv-orphan")
        #expect(turns.count == 1)
        #expect(turns[0].status == .failed)
        let kind = WorkspaceRepoCatalog.statusKind(conversation: seed, lastTurn: turns[0])
        #expect(kind == .failed)
        #expect(kind != .working)
    }

    @Test("mergeConversationSummaries does not overwrite a locally-completed turn")
    func mergeConversationSummariesDoesNotRegressCompleted() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-done", title: "Done", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 4, syncState: .synced)
        let completed = ChatTurn(
            id: "turn-done", conversationID: "conv-done", ordinal: 0,
            prompt: "go", runID: "run-done", status: .completed
        )
        _ = try await repo.upsertTurnMirror(
            completed, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        // Stale/hostile host status must not regress a terminal local turn.
        let summary = ConversationSummary(
            id: "conv-done", title: "Done", provider: "claudeCode", agentID: "claudeCode",
            hostName: "Mac", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 4,
            lastTurnID: "turn-done", lastTurnStatus: "running"
        )
        await coordinator.mergeConversationSummaries([summary], hostName: "Mac", hostID: nil)

        let turns = try await repo.turns(conversationID: "conv-done")
        #expect(turns[0].status == .completed)
        let kind = WorkspaceRepoCatalog.statusKind(conversation: seed, lastTurn: turns[0])
        #expect(kind == .completed)
        #expect(kind != .working)
    }

    @Test("mergeConversationSummaries ignores summaries without lastTurn fields")
    func mergeConversationSummariesIgnoresAbsentLastTurnFields() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-old", title: "Old daemon", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 1, syncState: .synced)
        let running = ChatTurn(
            id: "turn-old", conversationID: "conv-old", ordinal: 0,
            prompt: "go", runID: "run-old", status: .running
        )
        _ = try await repo.upsertTurnMirror(
            running, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let summary = ConversationSummary(
            id: "conv-old", title: "Old daemon", provider: "claudeCode", agentID: "claudeCode",
            hostName: "Mac", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 1
        )
        await coordinator.mergeConversationSummaries([summary], hostName: "Mac", hostID: nil)

        let turns = try await repo.turns(conversationID: "conv-old")
        #expect(turns[0].status == .running, "absent lastTurn fields must not invent a status")
    }

    @Test("observeSyncState immediately yields the current state, then updates on transitions")
    func observeSyncStateStream() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let stream = await coordinator.observeSyncState(conversationID: "conv-1")
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .synced)

        let transport = makeTransport(
            append: { _ in
                ConversationAppendResponse(status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 5)
            },
            fetch: { _ in throw NSError(domain: "test", code: 1) }
        )
        async let outcome: ConversationSyncCoordinator.TurnOutcome = coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "x", clientTurnID: "d:1",
            hostName: "h", hostID: nil, transport: transport
        )
        // First transition is `.syncing` (published before the append call resolves).
        let syncing = await iterator.next()
        #expect(syncing == .syncing)
        let conflict = await iterator.next()
        #expect(conflict == .conflict)
        _ = await outcome
    }

    @Test("parseDate accepts fractional and plain ISO8601 host timestamps")
    func parseDateFractionalAndPlain() {
        let fractional = ConversationSyncCoordinator.parseDate("2026-07-12T08:30:00.123Z")
        let plain = ConversationSyncCoordinator.parseDate("2026-07-12T08:30:00Z")
        #expect(fractional != nil)
        #expect(plain != nil)
        // Same instant modulo fractional part — must not fall back to .now.
        #expect(abs((fractional?.timeIntervalSince1970 ?? 0) - (plain?.timeIntervalSince1970 ?? 0)) < 1)
        #expect(ConversationSyncCoordinator.parseDate(nil) == nil)
        #expect(ConversationSyncCoordinator.parseDate("") == nil)
        #expect(ConversationSyncCoordinator.parseDate("not-a-date") == nil)
    }
}
#endif
