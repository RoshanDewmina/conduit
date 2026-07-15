import Foundation
import GRDB
import LancerCore
import AgentKit
import OSLog

public enum ChatConversationRepositoryError: Error, Equatable, Sendable {
    case attachmentsEncodeFailed
    case attachmentsDecodeFailed
}

public actor ChatConversationRepository {
    private let db: AppDatabase
    private static let logger = Logger(subsystem: "dev.lancer.mobile", category: "ChatConversationRepository")

    public init(_ db: AppDatabase) { self.db = db }

    // MARK: - Conversation CRUD

    public func createConversation(
        title: String,
        agentID: String,
        vendor: String? = nil,
        hostName: String,
        hostID: String? = nil,
        cwd: String,
        model: String? = nil,
        budgetUSD: Double? = nil
    ) async throws -> ChatConversation {
        let now = Date()
        let conversation = ChatConversation(
            title: title, agentID: agentID, vendor: vendor,
            hostName: hostName, hostID: hostID, cwd: cwd,
            model: model, budgetUSD: budgetUSD, status: .active,
            createdAt: now, updatedAt: now, lastActivityAt: now
        )
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO chat_conversations
                    (id, title, agent_id, vendor, host_name, host_id, cwd, model, budget_usd,
                     status, created_at, updated_at, last_activity_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                conversation.id, conversation.title, conversation.agentID,
                conversation.vendor, conversation.hostName, conversation.hostID,
                conversation.cwd, conversation.model, conversation.budgetUSD,
                conversation.status.rawValue, conversation.createdAt,
                conversation.updatedAt, conversation.lastActivityAt,
            ])
            try Self.syncFTS(db, conversationID: conversation.id)
        }
        return conversation
    }

    public func conversation(id: String) async throws -> ChatConversation? {
        try await db.dbWriter.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM chat_conversations WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return Self.decodeConversation(row)
        }
    }

    public func updateConversationTitle(_ id: String, title: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                UPDATE chat_conversations SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
            """, arguments: [title, id])
            try Self.syncFTS(db, conversationID: id)
        }
    }

    public func updateConversationStatus(_ id: String, status: ChatConversation.Status) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                UPDATE chat_conversations SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
            """, arguments: [status.rawValue, id])
        }
    }

    public func deleteConversation(_ id: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM chat_conversations WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM chat_fts WHERE conversation_id = ?", arguments: [id])
        }
    }

    // MARK: - Turns

    public func appendTurn(
        conversationID: String,
        prompt: String,
        runID: String,
        transportKind: String = "ssh",
        attachments: [ConversationAttachmentReference] = []
    ) async throws -> ChatTurn {
        let nextOrdinal: Int = try await db.dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT MAX(ordinal) as maxOrd FROM chat_turns WHERE conversation_id = ?
            """, arguments: [conversationID])
            return ((row?["maxOrd"] as Int?) ?? -1) + 1
        }
        let turn = ChatTurn(
            conversationID: conversationID, ordinal: nextOrdinal,
            prompt: prompt, runID: runID, transportKind: transportKind,
            attachments: attachments
        )
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO chat_turns
                    (id, conversation_id, ordinal, prompt, run_id, transport_kind,
                     status, assistant_text, error_message, created_at, completed_at,
                     attachments_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                turn.id, turn.conversationID, turn.ordinal, turn.prompt,
                turn.runID, turn.transportKind, turn.status.rawValue,
                turn.assistantText, turn.errorMessage, turn.createdAt, turn.completedAt,
                try Self.encodeAttachments(turn.attachments),
            ])
            try db.execute(sql: """
                UPDATE chat_conversations SET last_activity_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?
            """, arguments: [conversationID])
            try Self.syncFTS(db, conversationID: conversationID)
        }
        return turn
    }

    public func updateTurnOutput(
        runID: String,
        assistantText: String,
        status: ChatTurn.Status,
        errorMessage: String? = nil
    ) async throws {
        try await db.dbWriter.write { db in
            let redacted: String
            if Self.redactionEnabled {
                redacted = Redactor.shared.redact(assistantText).redacted
            } else {
                redacted = assistantText
            }
            try db.execute(sql: """
                UPDATE chat_turns SET
                    assistant_text = ?,
                    status = ?,
                    error_message = ?,
                    completed_at = CASE WHEN ? IN ('completed', 'failed') THEN CURRENT_TIMESTAMP ELSE completed_at END
                WHERE run_id = ?
            """, arguments: [redacted, status.rawValue, errorMessage, status.rawValue, runID])
            if let turn = try Row.fetchOne(db, sql: "SELECT conversation_id FROM chat_turns WHERE run_id = ?", arguments: [runID]),
               let convID: String = turn["conversation_id"] {
                try Self.syncFTS(db, conversationID: convID)
                // The conversation itself is created with status=active and,
                // before this, nothing ever moved it out of that state — every
                // conversation showed a perpetual "Working" attention badge
                // forever, even ones from days earlier, because nothing wrote
                // back here once its run actually finished. Mirror the turn's
                // terminal status onto the parent conversation in the same
                // transaction so CursorThreadAttention reflects reality.
                if status == .completed || status == .failed {
                    let conversationStatus: ChatConversation.Status = status == .completed ? .completed : .failed
                    try db.execute(sql: """
                        UPDATE chat_conversations SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
                    """, arguments: [conversationStatus.rawValue, convID])
                }
            }
        }
    }

    public func turnByRunID(_ runID: String) async throws -> ChatTurn? {
        try await db.dbWriter.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM chat_turns WHERE run_id = ?", arguments: [runID]) else {
                return nil
            }
            return try Self.decodeTurn(row)
        }
    }

    public func turns(conversationID: String) async throws -> [ChatTurn] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_turns WHERE conversation_id = ?
                ORDER BY ordinal ASC
            """, arguments: [conversationID])
            return try rows.map { try Self.decodeTurn($0) }
        }
    }

    // MARK: - Artifacts

    public func upsertArtifact(_ artifact: ChatArtifact) async throws {
        try await db.dbWriter.write { db in
            let cappedPayload = String(artifact.payloadJSON.prefix(64 * 1024))
            let payload = Self.redactionEnabled ? Redactor.shared.redact(cappedPayload).redacted : cappedPayload
            try db.execute(sql: """
                INSERT INTO chat_artifacts
                    (id, conversation_id, turn_id, run_id, kind, title, summary,
                     payload_json, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title, summary = excluded.summary,
                    payload_json = excluded.payload_json, status = excluded.status,
                    updated_at = CURRENT_TIMESTAMP
            """, arguments: [
                artifact.id, artifact.conversationID, artifact.turnID,
                artifact.runID, artifact.kind.rawValue, artifact.title,
                artifact.summary, payload, artifact.status.rawValue,
                artifact.createdAt, artifact.updatedAt,
            ])
            try Self.syncFTS(db, conversationID: artifact.conversationID)
        }
    }

    public func updateArtifactStatus(id: String, status: ChatArtifact.Status) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                UPDATE chat_artifacts SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?
            """, arguments: [status.rawValue, id])
        }
    }

    /// Completes every still-running artifact for a run when lancerd emits the
    /// terminal run lifecycle event. Tool adapters do not all have individual
    /// completion records, but the run result is authoritative for their state.
    public func updateArtifactStatuses(runID: String, status: ChatArtifact.Status) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                UPDATE chat_artifacts
                SET status = ?, updated_at = CURRENT_TIMESTAMP
                WHERE run_id = ? AND status = 'running'
            """, arguments: [status.rawValue, runID])
        }
    }

    public func artifacts(conversationID: String) async throws -> [ChatArtifact] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_artifacts WHERE conversation_id = ?
                ORDER BY created_at ASC
            """, arguments: [conversationID])
            return rows.compactMap(Self.decodeArtifact)
        }
    }

    public func artifacts(turnID: String) async throws -> [ChatArtifact] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_artifacts WHERE turn_id = ?
                ORDER BY created_at ASC
            """, arguments: [turnID])
            return rows.compactMap(Self.decodeArtifact)
        }
    }

    public func artifacts(runID: String) async throws -> [ChatArtifact] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_artifacts WHERE run_id = ?
                ORDER BY created_at ASC
            """, arguments: [runID])
            return rows.compactMap(Self.decodeArtifact)
        }
    }

    /// The most recent `.question` artifact with no submitted answer yet,
    /// across all conversations — used by the voice-answer Siri intent
    /// (`AnswerQuestionIntent`, `Lancer` app target), which has no specific
    /// conversation/artifact in scope to look up from (mirrors
    /// `ApprovalRepository.pending()`'s bare-repository pattern used by
    /// `DenyLatestApprovalIntent`). Answered state is decoded and checked in
    /// Swift rather than via a `json_extract` SQL filter, matching every
    /// other artifact query in this repository (all of which decode-then-
    /// filter) — this never assumes SQLite's JSON1 extension is compiled
    /// into the bundled database.
    public func latestUnansweredQuestion() async throws -> ChatArtifact? {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_artifacts WHERE kind = 'question'
                ORDER BY created_at DESC LIMIT 200
            """)
            for row in rows {
                guard let artifact = Self.decodeArtifact(row),
                      let data = artifact.payloadJSON.data(using: .utf8),
                      let payload = try? JSONDecoder().decode(QuestionArtifactPayload.self, from: data)
                else { continue }
                if payload.answer == nil { return artifact }
            }
            return nil
        }
    }

    /// A single artifact row by id, or `nil` if none exists. Mirrors
    /// `conversation(id:)`; used by `CommandGateway.answerQuestion` to
    /// re-fetch the exact artifact a Siri intent resolved against (by id)
    /// before merging its answer into the stored payload, since
    /// `CommandRequest.answerQuestion` only carries the artifact id.
    public func artifact(id: String) async throws -> ChatArtifact? {
        try await db.dbWriter.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM chat_artifacts WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return Self.decodeArtifact(row)
        }
    }

    public func associateApproval(approvalID: String, runID: String) async throws {
        try await db.dbWriter.write { db in
            guard let turn = try Row.fetchOne(db, sql: "SELECT * FROM chat_turns WHERE run_id = ?", arguments: [runID]) else { return }
            let convID: String = turn["conversation_id"]
            if let _ = try Row.fetchOne(db, sql: "SELECT id FROM chat_artifacts WHERE run_id = ? AND kind = 'approval' AND title = ?", arguments: [runID, approvalID]) {
                return
            }
            let artifact = ChatArtifact(
                conversationID: convID, turnID: turn["id"], runID: runID,
                kind: .approval, title: approvalID, payloadJSON: "{}", status: .running
            )
            try db.execute(sql: """
                INSERT INTO chat_artifacts
                    (id, conversation_id, turn_id, run_id, kind, title, summary,
                     payload_json, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                artifact.id, artifact.conversationID, artifact.turnID,
                artifact.runID, artifact.kind.rawValue, artifact.title,
                artifact.summary, artifact.payloadJSON, artifact.status.rawValue,
                artifact.createdAt, artifact.updatedAt,
            ])
            try Self.syncFTS(db, conversationID: convID)
        }
    }

    /// Persists the terminal run proof (`lancer.proof/v0`) as a done receipt
    /// artifact on the turn that owns `runID`. Idempotent by stable artifact id.
    @discardableResult
    public func upsertReceipt(runID: String, payloadJSON: String) async throws -> String? {
        try await db.dbWriter.write { db in
            guard let turn = try Row.fetchOne(db, sql: "SELECT * FROM chat_turns WHERE run_id = ?", arguments: [runID]) else {
                return nil
            }
            let convID: String = turn["conversation_id"]
            let turnID: String = turn["id"]
            let cappedPayload = String(payloadJSON.prefix(64 * 1024))
            let payload = Self.redactionEnabled ? Redactor.shared.redact(cappedPayload).redacted : cappedPayload
            let artifact = ChatArtifact(
                id: "receipt:\(runID)",
                conversationID: convID,
                turnID: turnID,
                runID: runID,
                kind: .receipt,
                title: "Run proof",
                payloadJSON: payload,
                status: .done
            )
            try db.execute(sql: """
                INSERT INTO chat_artifacts
                    (id, conversation_id, turn_id, run_id, kind, title, summary,
                     payload_json, status, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    payload_json = excluded.payload_json,
                    status = excluded.status,
                    updated_at = CURRENT_TIMESTAMP
            """, arguments: [
                artifact.id, artifact.conversationID, artifact.turnID,
                artifact.runID, artifact.kind.rawValue, artifact.title,
                artifact.summary, payload, artifact.status.rawValue,
                artifact.createdAt, artifact.updatedAt,
            ])
            try Self.syncFTS(db, conversationID: convID)
            return convID
        }
    }

    // MARK: - Cross-device sync mirror (Task 6)
    //
    // These APIs are the ONLY way UI/sync code should write host-authoritative
    // conversation/turn/event state locally — see the build handoff's
    // "Existing Code Surfaces" note: "Add mirror/upsert APIs. Do not make UI
    // code write host-authoritative rows directly except drafts." Mapping
    // from the wire types (ConversationSummary etc.) into these calls' plain
    // Swift/Foundation parameters happens in the sync coordinator (Task 7),
    // keeping this repository free of LancerDProtocol's ISO8601-string dates.

    /// Creates or updates a conversation's mirror row from host-fetched data.
    /// Upserts by `id` — a host-backed conversation never changes ID once
    /// created (`beginTurn` mints it once). `lastHostSeq`/`syncState` are
    /// always overwritten (they reflect the freshest state this device has
    /// observed); other fields fall back to their current value on conflict
    /// only where the caller passes `nil`, so a partial refresh cannot
    /// silently blank out data (e.g. title) it didn't fetch.
    @discardableResult
    public func upsertConversationMirror(
        _ conversation: ChatConversation,
        lastHostSeq: Int,
        syncState: ChatConversation.SyncState
    ) async throws -> ChatConversation {
        let merged: ChatConversation = {
            var c = conversation
            c.lastHostSeq = lastHostSeq
            c.syncState = syncState
            return c
        }()
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO chat_conversations
                    (id, title, agent_id, vendor, host_name, host_id, cwd, model, budget_usd,
                     status, created_at, updated_at, last_activity_at,
                     source_host_id, source_host_name, last_host_seq, sync_state,
                     cloud_record_name, cloud_uploaded_at, cloud_modified_at, archived_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    status = excluded.status,
                    updated_at = MAX(updated_at, excluded.updated_at),
                    last_activity_at = MAX(last_activity_at, excluded.last_activity_at),
                    source_host_id = excluded.source_host_id,
                    source_host_name = excluded.source_host_name,
                    last_host_seq = excluded.last_host_seq,
                    sync_state = excluded.sync_state,
                    archived_at = excluded.archived_at
            """, arguments: [
                merged.id, merged.title, merged.agentID, merged.vendor,
                merged.hostName, merged.hostID, merged.cwd, merged.model, merged.budgetUSD,
                merged.status.rawValue, merged.createdAt, merged.updatedAt, merged.lastActivityAt,
                merged.sourceHostID, merged.sourceHostName, merged.lastHostSeq, merged.syncState.rawValue,
                merged.cloudRecordName, merged.cloudUploadedAt, merged.cloudModifiedAt, merged.archivedAt,
            ])
            try Self.syncFTS(db, conversationID: merged.id)
        }
        return merged
    }

    /// Creates or updates a turn's mirror row keyed by `id` (the host's
    /// `conversationTurn.id`, not the runID `chat_turns` was historically
    /// keyed toward locally — a host-backed turn always has both).
    @discardableResult
    public func upsertTurnMirror(
        _ turn: ChatTurn,
        vendorSessionID: String?,
        hostSeqStart: Int?,
        hostSeqEnd: Int?
    ) async throws -> ChatTurn {
        let merged: ChatTurn = {
            var t = turn
            t.vendorSessionID = vendorSessionID
            t.hostSeqStart = hostSeqStart
            t.hostSeqEnd = hostSeqEnd
            return t
        }()
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO chat_turns
                    (id, conversation_id, ordinal, prompt, run_id, transport_kind,
                     status, assistant_text, error_message, created_at, completed_at,
                     client_turn_id, vendor_session_id, host_seq_start, host_seq_end, cloud_record_name,
                     attachments_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    status = excluded.status,
                    assistant_text = excluded.assistant_text,
                    error_message = excluded.error_message,
                    completed_at = excluded.completed_at,
                    vendor_session_id = excluded.vendor_session_id,
                    host_seq_start = excluded.host_seq_start,
                    host_seq_end = excluded.host_seq_end,
                    attachments_json = CASE
                        WHEN excluded.attachments_json IS NULL OR excluded.attachments_json = '[]'
                        THEN chat_turns.attachments_json
                        ELSE excluded.attachments_json
                    END
            """, arguments: [
                merged.id, merged.conversationID, merged.ordinal, merged.prompt,
                merged.runID, merged.transportKind, merged.status.rawValue,
                merged.assistantText, merged.errorMessage, merged.createdAt, merged.completedAt,
                merged.clientTurnID, merged.vendorSessionID, merged.hostSeqStart, merged.hostSeqEnd,
                merged.cloudRecordName,
                try Self.encodeAttachments(merged.attachments),
            ])
            try db.execute(sql: """
                UPDATE chat_conversations SET last_activity_at = CURRENT_TIMESTAMP WHERE id = ?
            """, arguments: [merged.conversationID])
            try Self.syncFTS(db, conversationID: merged.conversationID)
        }
        return merged
    }

    /// Appends host-ledger events into the local mirror. Idempotent by
    /// `(conversationID, seq)` — re-fetching an overlapping range (e.g. after
    /// a retried `fetch` call) is always safe to call again.
    public func appendEventsMirror(conversationID: String, events: [ChatEvent]) async throws {
        guard !events.isEmpty else { return }
        try await db.dbWriter.write { db in
            for event in events {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO chat_events
                        (conversation_id, seq, turn_id, run_id, kind, role, stream, text, payload_json, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    conversationID, event.seq, event.turnID, event.runID,
                    event.kind, event.role, event.stream, event.text,
                    event.payloadJSON, event.createdAt,
                ])
            }
        }
    }

    /// Events mirrored locally for a conversation, strictly after `sinceSeq`,
    /// ordered ascending — the same paging contract as the host's
    /// `agent.conversations.fetch`.
    public func events(conversationID: String, sinceSeq: Int = 0, limit: Int = 2000) async throws -> [ChatEvent] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_events
                WHERE conversation_id = ? AND seq > ?
                ORDER BY seq ASC LIMIT ?
            """, arguments: [conversationID, sinceSeq, limit])
            return rows.compactMap(Self.decodeEvent)
        }
    }

    /// Highest contiguous host sequence hydrated into the local event mirror.
    /// CloudKit turn chunks can arrive out of order, so `MAX(seq)` is unsafe:
    /// a later chunk must not cause host fetches to skip an earlier hole.
    public func hydratedEventCursor(conversationID: String) async throws -> Int {
        try await db.dbWriter.read { db in
            let sequences = try Int.fetchAll(
                db,
                sql: "SELECT seq FROM chat_events WHERE conversation_id = ? ORDER BY seq ASC",
                arguments: [conversationID]
            )
            var cursor = 0
            for sequence in sequences {
                guard sequence == cursor + 1 else { break }
                cursor = sequence
            }
            return cursor
        }
    }

    public func updateSyncState(conversationID: String, state: ChatConversation.SyncState) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                UPDATE chat_conversations SET sync_state = ? WHERE id = ?
            """, arguments: [state.rawValue, conversationID])
        }
    }

    /// Records that this conversation's mirror row has been pushed to
    /// CloudKit (Task 8) as `recordName`, so the sync engine's next pull
    /// cycle can tell its own prior push apart from a genuine remote change.
    public func markCloudUploaded(conversationID: String, recordName: String, modifiedAt: Date?) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                UPDATE chat_conversations SET
                    cloud_record_name = ?, cloud_uploaded_at = CURRENT_TIMESTAMP, cloud_modified_at = ?
                WHERE id = ?
            """, arguments: [recordName, modifiedAt, conversationID])
        }
    }

    /// Ledger-backed conversations (`syncState != .localOnly`) whose metadata
    /// has changed since it was last pushed to CloudKit — i.e. never
    /// uploaded, or `updated_at` has moved past `cloud_modified_at`.
    /// `ConversationSyncEngine` (Task 8) drives its push cycle from this.
    public func conversationsNeedingCloudPush() async throws -> [ChatConversation] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_conversations
                WHERE sync_state != 'localOnly'
                  AND (cloud_uploaded_at IS NULL OR cloud_modified_at IS NULL OR updated_at > cloud_modified_at)
                ORDER BY updated_at ASC
            """)
            return rows.compactMap(Self.decodeConversation)
        }
    }

    /// Finished turns (never `running` — a turn's transcript isn't final
    /// until then) that have no CloudKit record yet. Turn chunks are
    /// immutable once uploaded, so this only ever returns each turn once.
    public func turnsNeedingCloudPush(conversationID: String) async throws -> [ChatTurn] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_turns
                WHERE conversation_id = ? AND cloud_record_name IS NULL AND status != 'running'
                ORDER BY ordinal ASC
            """, arguments: [conversationID])
            return try rows.map { try Self.decodeTurn($0) }
        }
    }

    /// Records that a turn's immutable event-chunk record has been pushed to
    /// CloudKit, so it is never re-uploaded by a later push cycle.
    public func markTurnCloudUploaded(turnID: String, recordName: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "UPDATE chat_turns SET cloud_record_name = ? WHERE id = ?", arguments: [recordName, turnID])
        }
    }

    /// Applies a CloudKit-side deletion of a conversation's metadata record
    /// (e.g. removed via the CloudKit dashboard) as a local archive rather
    /// than a hard delete, so any already-mirrored turns/events are kept.
    public func applyCloudArchive(conversationID: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                UPDATE chat_conversations SET status = 'archived', archived_at = COALESCE(archived_at, CURRENT_TIMESTAMP)
                WHERE id = ?
            """, arguments: [conversationID])
        }
    }

    // MARK: - Drafts (offline sends — never auto-sent, see ChatDraft's doc comment)

    public func saveDraft(conversationID: String, text: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO chat_drafts (conversation_id, text, saved_at) VALUES (?, ?, CURRENT_TIMESTAMP)
                ON CONFLICT(conversation_id) DO UPDATE SET text = excluded.text, saved_at = CURRENT_TIMESTAMP
            """, arguments: [conversationID, text])
        }
    }

    public func localDraft(conversationID: String) async throws -> ChatDraft? {
        try await db.dbWriter.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM chat_drafts WHERE conversation_id = ?", arguments: [conversationID]) else {
                return nil
            }
            return ChatDraft(conversationID: row["conversation_id"], text: row["text"] ?? "", savedAt: row["saved_at"] ?? .now)
        }
    }

    public func clearDraft(conversationID: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM chat_drafts WHERE conversation_id = ?", arguments: [conversationID])
        }
    }

    // MARK: - Recent + Search

    public func recent(limit: Int = 50, offset: Int = 0) async throws -> [ChatConversation] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_conversations
                ORDER BY last_activity_at DESC LIMIT ? OFFSET ?
            """, arguments: [limit, offset])
            return rows.compactMap(Self.decodeConversation)
        }
    }

    public func search(_ query: String, limit: Int = 50) async throws -> [ChatConversationSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let convs = try await recent(limit: limit)
            return convs.map { ChatConversationSearchResult(conversation: $0, snippet: $0.title) }
        }
        let ftsQuery = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .appending("*")
        return try await db.dbWriter.read { db in
            let ftsRows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT conversation_id
                FROM chat_fts
                WHERE chat_fts MATCH ?
                ORDER BY rowid DESC
                LIMIT ?
            """, arguments: [ftsQuery, limit])
            var results: [ChatConversationSearchResult] = []
            for ftsRow in ftsRows {
                guard let convID: String = ftsRow["conversation_id"],
                      let convRow = try Row.fetchOne(db, sql: "SELECT * FROM chat_conversations WHERE id = ?", arguments: [convID]),
                      let conv = Self.decodeConversation(convRow) else { continue }
                results.append(ChatConversationSearchResult(conversation: conv, snippet: conv.title))
            }
            return results
        }
    }

    // MARK: - FTS sync (rebuilds the single FTS row for a conversation)

    private static func syncFTS(_ db: Database, conversationID: String) throws {
        try db.execute(sql: "DELETE FROM chat_fts WHERE conversation_id = ?", arguments: [conversationID])
        let title: String = {
            let row = try? Row.fetchOne(db, sql: "SELECT title FROM chat_conversations WHERE id = ?", arguments: [conversationID])
            return row?["title"] as? String ?? ""
        }()
        var allTexts: [String] = [title]
        let turnRows = try Row.fetchAll(db, sql: """
            SELECT prompt, assistant_text FROM chat_turns WHERE conversation_id = ? ORDER BY ordinal ASC
        """, arguments: [conversationID])
        for tRow in turnRows {
            if let p: String = tRow["prompt"], !p.isEmpty { allTexts.append(p) }
            if let a: String = tRow["assistant_text"], !a.isEmpty { allTexts.append(a) }
        }
        let artRows = try Row.fetchAll(db, sql: """
            SELECT title, summary FROM chat_artifacts WHERE conversation_id = ?
        """, arguments: [conversationID])
        for aRow in artRows {
            let t: String = aRow["title"] ?? ""
            let s: String = aRow["summary"] ?? ""
            let combined = "\(t) \(s)".trimmingCharacters(in: .whitespaces)
            if !combined.isEmpty { allTexts.append(combined) }
        }
        let joined = allTexts.joined(separator: "\n")
        try db.execute(sql: "INSERT INTO chat_fts (conversation_id, title, prompt, assistant_text, artifact_text) VALUES (?, ?, ?, ?, ?)",
                        arguments: [conversationID, title, joined, joined, joined])
    }

    // MARK: - Decode helpers

    private static func decodeConversation(_ row: Row) -> ChatConversation? {
        ChatConversation(
            id: row["id"] ?? "", title: row["title"] ?? "",
            agentID: row["agent_id"] ?? "", vendor: row["vendor"],
            hostName: row["host_name"] ?? "", hostID: row["host_id"],
            cwd: row["cwd"] ?? "", model: row["model"],
            budgetUSD: row["budget_usd"],
            status: ChatConversation.Status(rawValue: row["status"] ?? "active") ?? .active,
            createdAt: row["created_at"] ?? .now, updatedAt: row["updated_at"] ?? .now,
            lastActivityAt: row["last_activity_at"] ?? .now,
            sourceHostID: row["source_host_id"], sourceHostName: row["source_host_name"],
            lastHostSeq: row["last_host_seq"] ?? 0,
            syncState: ChatConversation.SyncState(rawValue: row["sync_state"] ?? "localOnly") ?? .localOnly,
            cloudRecordName: row["cloud_record_name"],
            cloudUploadedAt: row["cloud_uploaded_at"], cloudModifiedAt: row["cloud_modified_at"],
            archivedAt: row["archived_at"]
        )
    }

    private static func decodeTurn(_ row: Row) throws -> ChatTurn {
        ChatTurn(
            id: row["id"] ?? "", conversationID: row["conversation_id"] ?? "",
            ordinal: row["ordinal"] ?? 0, prompt: row["prompt"] ?? "",
            runID: row["run_id"] ?? "", transportKind: row["transport_kind"] ?? "ssh",
            status: ChatTurn.Status.fromHostStatus(row["status"] ?? "running"),
            assistantText: row["assistant_text"] ?? "", errorMessage: row["error_message"],
            createdAt: row["created_at"] ?? .now, completedAt: row["completed_at"],
            clientTurnID: row["client_turn_id"], vendorSessionID: row["vendor_session_id"],
            hostSeqStart: row["host_seq_start"], hostSeqEnd: row["host_seq_end"],
            cloudRecordName: row["cloud_record_name"],
            attachments: try decodeAttachments(row["attachments_json"])
        )
    }

    private static func encodeAttachments(_ attachments: [ConversationAttachmentReference]) throws -> String {
        if attachments.isEmpty { return "[]" }
        do {
            let data = try JSONEncoder().encode(attachments)
            guard let json = String(data: data, encoding: .utf8) else {
                logger.error("attachments encode produced non-UTF8 payload; refusing empty wipe")
                throw ChatConversationRepositoryError.attachmentsEncodeFailed
            }
            return json
        } catch let error as ChatConversationRepositoryError {
            throw error
        } catch {
            // Never replace nonempty metadata with [] on encode failure.
            logger.error("attachments encode failed; preserving caller transaction by failing closed")
            throw ChatConversationRepositoryError.attachmentsEncodeFailed
        }
    }

    private static func decodeAttachments(_ raw: String?) throws -> [ConversationAttachmentReference] {
        guard let raw else { return [] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" || trimmed == "null" { return [] }
        guard let data = trimmed.data(using: .utf8) else {
            logger.error("attachments_json was nonempty but not UTF-8; failing closed")
            throw ChatConversationRepositoryError.attachmentsDecodeFailed
        }
        do {
            return try JSONDecoder().decode([ConversationAttachmentReference].self, from: data)
        } catch {
            // Corrupt / semantically invalid JSON must not silently become [].
            logger.error("attachments_json decode failed; failing closed without wiping metadata")
            throw ChatConversationRepositoryError.attachmentsDecodeFailed
        }
    }

    private static func decodeEvent(_ row: Row) -> ChatEvent? {
        ChatEvent(
            conversationID: row["conversation_id"] ?? "", seq: row["seq"] ?? 0,
            turnID: row["turn_id"], runID: row["run_id"], kind: row["kind"] ?? "",
            role: row["role"], stream: row["stream"], text: row["text"],
            payloadJSON: row["payload_json"], createdAt: row["created_at"] ?? .now
        )
    }

    private static func decodeArtifact(_ row: Row) -> ChatArtifact? {
        guard let kindRaw: String = row["kind"],
              let kind = ChatArtifact.Kind(rawValue: kindRaw) else {
            // Unknown artifact kinds are skipped (not thrown) for forward compat.
            return nil
        }
        return ChatArtifact(
            id: row["id"] ?? "", conversationID: row["conversation_id"] ?? "",
            turnID: row["turn_id"] ?? "", runID: row["run_id"] ?? "",
            kind: kind,
            title: row["title"] ?? "", summary: row["summary"],
            payloadJSON: row["payload_json"] ?? "{}",
            status: ChatArtifact.Status(rawValue: row["status"] ?? "running") ?? .running,
            createdAt: row["created_at"] ?? .now, updatedAt: row["updated_at"] ?? .now
        )
    }

    private static var redactionEnabled: Bool {
        UserDefaults.standard.bool(forKey: "redactSavedHistory")
    }
}
