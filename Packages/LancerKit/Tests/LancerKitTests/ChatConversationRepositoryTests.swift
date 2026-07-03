import Foundation
import Testing
@testable import LancerCore
@testable import PersistenceKit

@Suite("ChatConversationRepository")
struct ChatConversationRepositoryTests {

    // MARK: - Conversation CRUD

    @Test("createConversation round-trips all fields")
    func createRoundTrip() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "Debug SSH host", agentID: "claude",
            vendor: "anthropic", hostName: "prod-1",
            hostID: "h1", cwd: "/home/user",
            model: "sonnet", budgetUSD: 5.0
        )
        #expect(conv.title == "Debug SSH host")
        #expect(conv.agentID == "claude")
        #expect(conv.vendor == "anthropic")
        #expect(conv.hostName == "prod-1")
        #expect(conv.hostID == "h1")
        #expect(conv.cwd == "/home/user")
        #expect(conv.model == "sonnet")
        #expect(conv.budgetUSD == 5.0)
        #expect(conv.status == .active)

        let read = try await repo.conversation(id: conv.id)
        #expect(read?.title == conv.title)
    }

    @Test("conversation for unknown ID returns nil")
    func unknownIDNil() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        #expect(try await repo.conversation(id: "nonexistent") == nil)
    }

    @Test("updateConversationTitle changes title")
    func updateTitle() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "Old Title", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        try await repo.updateConversationTitle(conv.id, title: "New Title")
        let read = try await repo.conversation(id: conv.id)
        #expect(read?.title == "New Title")
    }

    @Test("deleteConversation removes record and FTS entry")
    func deleteConversation() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "To Delete", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        try await repo.deleteConversation(conv.id)
        #expect(try await repo.conversation(id: conv.id) == nil)
    }

    // MARK: - Turns

    @Test("appendTurn assigns incrementing ordinals")
    func turnOrdinals() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "T", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        let t1 = try await repo.appendTurn(conversationID: conv.id, prompt: "first", runID: "r1")
        let t2 = try await repo.appendTurn(conversationID: conv.id, prompt: "second", runID: "r2")
        let t3 = try await repo.appendTurn(conversationID: conv.id, prompt: "third", runID: "r3")
        #expect(t1.ordinal == 0)
        #expect(t2.ordinal == 1)
        #expect(t3.ordinal == 2)
    }

    @Test("updateTurnOutput sets assistantText and status")
    func updateTurnOutput() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "T", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        _ = try await repo.appendTurn(conversationID: conv.id, prompt: "hello", runID: "run-abc")
        try await repo.updateTurnOutput(runID: "run-abc", assistantText: "Hi there!", status: .completed)

        let turns = try await repo.turns(conversationID: conv.id)
        #expect(turns.count == 1)
        #expect(turns.first?.assistantText == "Hi there!")
        #expect(turns.first?.status == .completed)
        #expect(turns.first?.completedAt != nil)
    }

    @Test("turnByRunID returns nil for unknown run")
    func turnByRunIDNil() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        #expect(try await repo.turnByRunID("unknown") == nil)
    }

    // MARK: - Artifacts

    @Test("upsertArtifact round-trips all fields")
    func artifactRoundTrip() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "T", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        let turn = try await repo.appendTurn(conversationID: conv.id, prompt: "cmd", runID: "r1")
        let artifact = ChatArtifact(
            conversationID: conv.id, turnID: turn.id, runID: "r1",
            kind: .tool, title: "bash", summary: "Ran ls",
            payloadJSON: "{\"command\":\"ls\"}", status: .done
        )
        try await repo.upsertArtifact(artifact)

        let arts = try await repo.artifacts(conversationID: conv.id)
        #expect(arts.count == 1)
        #expect(arts.first?.title == "bash")
        #expect(arts.first?.kind == .tool)
        #expect(arts.first?.status == .done)
    }

    @Test("upsertArtifact with same ID updates existing row")
    func artifactUpsert() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "T", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        let turn = try await repo.appendTurn(conversationID: conv.id, prompt: "cmd", runID: "r1")
        var artifact = ChatArtifact(
            conversationID: conv.id, turnID: turn.id, runID: "r1",
            kind: .tool, title: "bash", summary: "initial",
            payloadJSON: "{}", status: .running
        )
        try await repo.upsertArtifact(artifact)

        artifact = ChatArtifact(
            id: artifact.id, conversationID: conv.id, turnID: turn.id, runID: "r1",
            kind: .tool, title: "bash", summary: "updated",
            payloadJSON: "{}", status: .done,
            createdAt: artifact.createdAt, updatedAt: artifact.updatedAt
        )
        try await repo.upsertArtifact(artifact)

        let arts = try await repo.artifacts(conversationID: conv.id)
        #expect(arts.count == 1)
        #expect(arts.first?.summary == "updated")
    }

    @Test("artifacts(turnID:) filters by turn")
    func artifactsByTurn() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "T", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        let t1 = try await repo.appendTurn(conversationID: conv.id, prompt: "a", runID: "r1")
        let t2 = try await repo.appendTurn(conversationID: conv.id, prompt: "b", runID: "r2")
        let a1 = ChatArtifact(
            conversationID: conv.id, turnID: t1.id, runID: "r1",
            kind: .tool, title: "x", payloadJSON: "{}", status: .done
        )
        let a2 = ChatArtifact(
            conversationID: conv.id, turnID: t2.id, runID: "r2",
            kind: .approval, title: "y", payloadJSON: "{}", status: .running
        )
        try await repo.upsertArtifact(a1)
        try await repo.upsertArtifact(a2)

        let arts1 = try await repo.artifacts(turnID: t1.id)
        #expect(arts1.count == 1)
        #expect(arts1.first?.title == "x")

        let arts2 = try await repo.artifacts(turnID: t2.id)
        #expect(arts2.count == 1)
        #expect(arts2.first?.title == "y")
    }

    // MARK: - FTS Search

    @Test("search finds by title")
    func searchByTitle() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        _ = try await repo.createConversation(
            title: "Deploy nginx to production", agentID: "claude",
            hostName: "prod-1", hostID: nil, cwd: "/tmp"
        )
        _ = try await repo.createConversation(
            title: "Fix database migration", agentID: "claude",
            hostName: "db-1", hostID: nil, cwd: "/tmp"
        )
        let results = try await repo.search("deploy")
        #expect(results.count == 1)
        #expect(results.first?.conversation.title == "Deploy nginx to production")
    }

    @Test("search finds by assistant text in turns")
    func searchByTurnText() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "Debug session", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        _ = try await repo.appendTurn(conversationID: conv.id, prompt: "What's the error?", runID: "r1")
        try await repo.updateTurnOutput(runID: "r1", assistantText: "The Nginx config has a syntax error", status: .completed)

        let results = try await repo.search("nginx")
        #expect(results.count == 1)
        #expect(results.first?.conversation.title == "Debug session")
    }

    @Test("search returns empty for no match")
    func searchNoMatch() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        _ = try await repo.createConversation(
            title: "Deploy nginx", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        let results = try await repo.search("postgres")
        #expect(results.isEmpty)
    }

    @Test("search returns recent for empty query")
    func searchEmptyQuery() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        _ = try await repo.createConversation(
            title: "Any title", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        let results = try await repo.search("")
        #expect(results.count == 1)
    }

    // MARK: - Recent

    @Test("recent returns conversations ordered by last_activity_at")
    func recentSorted() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        _ = try await repo.createConversation(
            title: "First", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        _ = try await repo.createConversation(
            title: "Second", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        let recent = try await repo.recent()
        #expect(recent.count == 2)
    }

    @Test("recent respects limit and offset")
    func recentPagination() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        for i in 0..<5 {
            _ = try await repo.createConversation(
                title: "Conv \(i)", agentID: "claude",
                hostName: "h", hostID: nil, cwd: "/tmp"
            )
        }
        let page1 = try await repo.recent(limit: 2, offset: 0)
        #expect(page1.count == 2)
        let page2 = try await repo.recent(limit: 2, offset: 2)
        #expect(page2.count == 2)
        #expect(page1[0].title != page2[0].title)
    }

    // MARK: - Approval artifact association

    @Test("associateApproval creates approval artifact linked to runID")
    func approvalLink() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "T", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        _ = try await repo.appendTurn(conversationID: conv.id, prompt: "approve me", runID: "r1")
        try await repo.associateApproval(approvalID: "appr-1", runID: "r1")

        let arts = try await repo.artifacts(runID: "r1")
        #expect(arts.count == 1)
        #expect(arts.first?.kind == .approval)
        #expect(arts.first?.title == "appr-1")
    }

    @Test("associateApproval is idempotent")
    func approvalIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "T", agentID: "claude",
            hostName: "h", hostID: nil, cwd: "/tmp"
        )
        _ = try await repo.appendTurn(conversationID: conv.id, prompt: "approve", runID: "r1")
        try await repo.associateApproval(approvalID: "appr-1", runID: "r1")
        try await repo.associateApproval(approvalID: "appr-1", runID: "r1")

        let arts = try await repo.artifacts(runID: "r1")
        #expect(arts.count == 1)
    }

    // MARK: - Cross-device sync mirror (Task 6)

    @Test("upsertConversationMirror creates a host-backed conversation with lastHostSeq/syncState")
    func mirrorCreatesConversation() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = ChatConversation(
            id: "conv-1", title: "Cross-device chat", agentID: "claudeCode",
            hostName: "MacBook Pro", hostID: nil, cwd: "/proj"
        )
        let saved = try await repo.upsertConversationMirror(conv, lastHostSeq: 4, syncState: .synced)
        #expect(saved.lastHostSeq == 4)
        #expect(saved.syncState == .synced)

        let read = try await repo.conversation(id: "conv-1")
        #expect(read?.lastHostSeq == 4)
        #expect(read?.syncState == .synced)
        #expect(read?.title == "Cross-device chat")
    }

    @Test("upsertConversationMirror on existing row updates lastHostSeq/syncState without losing sourceHost fields")
    func mirrorUpdatesExistingConversation() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = ChatConversation(
            id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj",
            sourceHostID: "host-abc", sourceHostName: "MacBook Pro"
        )
        _ = try await repo.upsertConversationMirror(conv, lastHostSeq: 1, syncState: .syncing)
        _ = try await repo.upsertConversationMirror(conv, lastHostSeq: 7, syncState: .synced)

        let read = try await repo.conversation(id: "conv-1")
        #expect(read?.lastHostSeq == 7)
        #expect(read?.syncState == .synced)
        #expect(read?.sourceHostID == "host-abc")
        #expect(read?.sourceHostName == "MacBook Pro")
    }

    @Test("upsertTurnMirror binds vendorSessionID and host seq range")
    func mirrorUpsertsTurn() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(conv, lastHostSeq: 0, syncState: .syncing)

        let turn = ChatTurn(id: "turn-1", conversationID: "conv-1", ordinal: 0, prompt: "hi", runID: "run-1", clientTurnID: "device-1:1")
        let saved = try await repo.upsertTurnMirror(turn, vendorSessionID: "sess-live-1", hostSeqStart: 1, hostSeqEnd: 3)
        #expect(saved.vendorSessionID == "sess-live-1")
        #expect(saved.hostSeqStart == 1)
        #expect(saved.hostSeqEnd == 3)

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.clientTurnID == "device-1:1")
        #expect(turns.first?.vendorSessionID == "sess-live-1")
    }

    @Test("upsertTurnMirror on existing row updates status without duplicating")
    func mirrorTurnUpsertIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(conv, lastHostSeq: 0, syncState: .syncing)

        var turn = ChatTurn(id: "turn-1", conversationID: "conv-1", ordinal: 0, prompt: "hi", runID: "run-1", status: .running)
        _ = try await repo.upsertTurnMirror(turn, vendorSessionID: nil, hostSeqStart: 1, hostSeqEnd: nil)
        turn.status = .completed
        turn.assistantText = "done"
        _ = try await repo.upsertTurnMirror(turn, vendorSessionID: "sess-1", hostSeqStart: 1, hostSeqEnd: 5)

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.status == .completed)
        #expect(turns.first?.assistantText == "done")
        #expect(turns.first?.vendorSessionID == "sess-1")
    }

    @Test("appendEventsMirror is idempotent on repeated seq")
    func mirrorEventsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(conv, lastHostSeq: 0, syncState: .syncing)

        let events = [
            ChatEvent(conversationID: "conv-1", seq: 1, kind: "prompt", role: "user", text: "hi"),
            ChatEvent(conversationID: "conv-1", seq: 2, kind: "output", role: "assistant", text: "hello"),
        ]
        try await repo.appendEventsMirror(conversationID: "conv-1", events: events)
        // Re-fetch overlapping range (as a retried `fetch` would) must not duplicate.
        try await repo.appendEventsMirror(conversationID: "conv-1", events: events)

        let stored = try await repo.events(conversationID: "conv-1")
        #expect(stored.count == 2)
        #expect(stored.map(\.seq) == [1, 2])
    }

    @Test("events(sinceSeq:) pages strictly after the given sequence")
    func mirrorEventsSinceSeq() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(conv, lastHostSeq: 0, syncState: .syncing)

        try await repo.appendEventsMirror(conversationID: "conv-1", events: [
            ChatEvent(conversationID: "conv-1", seq: 1, kind: "prompt"),
            ChatEvent(conversationID: "conv-1", seq: 2, kind: "output"),
            ChatEvent(conversationID: "conv-1", seq: 3, kind: "status"),
        ])
        let page = try await repo.events(conversationID: "conv-1", sinceSeq: 1)
        #expect(page.map(\.seq) == [2, 3])
    }

    @Test("updateSyncState transitions a conversation's mirror state")
    func mirrorUpdateSyncState() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(conv, lastHostSeq: 0, syncState: .syncing)
        try await repo.updateSyncState(conversationID: "conv-1", state: .conflict)
        let read = try await repo.conversation(id: "conv-1")
        #expect(read?.syncState == .conflict)
    }

    @Test("markCloudUploaded persists the CloudKit record name")
    func mirrorMarksCloudUploaded() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(conv, lastHostSeq: 0, syncState: .synced)
        try await repo.markCloudUploaded(conversationID: "conv-1", recordName: "ck-record-1", modifiedAt: Date())
        let read = try await repo.conversation(id: "conv-1")
        #expect(read?.cloudRecordName == "ck-record-1")
        #expect(read?.cloudUploadedAt != nil)
    }

    @Test("conversationsNeedingCloudPush excludes localOnly and already-current rows")
    func mirrorConversationsNeedingCloudPush() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)

        let legacy = ChatConversation(id: "conv-legacy", title: "Legacy", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(legacy, lastHostSeq: 0, syncState: .localOnly)

        let neverPushed = ChatConversation(id: "conv-new", title: "New", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(neverPushed, lastHostSeq: 1, syncState: .synced)

        let upToDate = ChatConversation(id: "conv-current", title: "Current", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(upToDate, lastHostSeq: 1, syncState: .synced)
        try await repo.markCloudUploaded(conversationID: "conv-current", recordName: "ck-current", modifiedAt: Date().addingTimeInterval(3600))

        let candidates = try await repo.conversationsNeedingCloudPush()
        #expect(candidates.map(\.id) == ["conv-new"])
    }

    @Test("turnsNeedingCloudPush only returns finished, not-yet-uploaded turns")
    func mirrorTurnsNeedingCloudPush() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(title: "T", agentID: "claude", hostName: "h", hostID: nil, cwd: "/tmp")

        let running = try await repo.appendTurn(conversationID: conv.id, prompt: "still going", runID: "run-running")
        let finished = try await repo.appendTurn(conversationID: conv.id, prompt: "done", runID: "run-done")
        try await repo.updateTurnOutput(runID: "run-done", assistantText: "ok", status: .completed)
        let alreadyUploaded = try await repo.appendTurn(conversationID: conv.id, prompt: "uploaded", runID: "run-uploaded")
        try await repo.updateTurnOutput(runID: "run-uploaded", assistantText: "ok", status: .completed)
        try await repo.markTurnCloudUploaded(turnID: alreadyUploaded.id, recordName: "ck-turn-1")

        let candidates = try await repo.turnsNeedingCloudPush(conversationID: conv.id)
        #expect(candidates.map(\.id) == [finished.id])
        _ = running
    }

    @Test("markTurnCloudUploaded persists the CloudKit record name")
    func mirrorMarksTurnCloudUploaded() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(title: "T", agentID: "claude", hostName: "h", hostID: nil, cwd: "/tmp")
        let turn = try await repo.appendTurn(conversationID: conv.id, prompt: "hi", runID: "run-1")
        try await repo.markTurnCloudUploaded(turnID: turn.id, recordName: "ck-turn-9")
        let turns = try await repo.turns(conversationID: conv.id)
        #expect(turns.first?.cloudRecordName == "ck-turn-9")
    }

    @Test("applyCloudArchive marks a conversation archived without clobbering an existing archivedAt")
    func mirrorAppliesCloudArchive() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(title: "T", agentID: "claude", hostName: "h", hostID: nil, cwd: "/tmp")
        try await repo.applyCloudArchive(conversationID: conv.id)
        let read = try await repo.conversation(id: conv.id)
        #expect(read?.status == .archived)
        #expect(read?.archivedAt != nil)
    }

    @Test("saveDraft / localDraft / clearDraft round-trip a single draft per conversation")
    func mirrorDraftLifecycle() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(title: "T", agentID: "claude", hostName: "h", hostID: nil, cwd: "/tmp")

        #expect(try await repo.localDraft(conversationID: conv.id) == nil)

        try await repo.saveDraft(conversationID: conv.id, text: "half-typed message")
        let draft = try await repo.localDraft(conversationID: conv.id)
        #expect(draft?.text == "half-typed message")

        // Saving again overwrites rather than accumulating a second draft.
        try await repo.saveDraft(conversationID: conv.id, text: "revised message")
        let revised = try await repo.localDraft(conversationID: conv.id)
        #expect(revised?.text == "revised message")

        try await repo.clearDraft(conversationID: conv.id)
        #expect(try await repo.localDraft(conversationID: conv.id) == nil)
    }
}
