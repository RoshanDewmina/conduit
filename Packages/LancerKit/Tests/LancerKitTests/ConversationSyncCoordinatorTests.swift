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

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.runID == "run-1")
        #expect(turns.first?.clientTurnID == "device-1:1")

        let state = await coordinator.currentSyncState("conv-1")
        #expect(state == .synced)
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

    @Test("conflict status marks the conversation conflict and does not touch the mirror row's seq")
    func conflictStatus() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let transport = makeTransport(append: { _ in
            ConversationAppendResponse(status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 5, message: "stale baseSeq")
        })
        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "stale", clientTurnID: "d:3",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .blocked(let message) = outcome else {
            Issue.record("expected .blocked, got \(outcome)")
            return
        }
        #expect(message == "stale baseSeq")
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.syncState == .conflict)
        #expect(mirrored?.lastHostSeq == 2, "a conflict response must not advance the mirror's seq")
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

        let transport = makeTransport(append: { _ in
            ConversationAppendResponse(status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 5)
        })
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
}
#endif
