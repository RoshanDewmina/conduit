import Foundation
import GRDB
import ConduitCore
import AgentKit

public actor ChatConversationRepository {
    private let db: AppDatabase
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
        transportKind: String = "ssh"
    ) async throws -> ChatTurn {
        let nextOrdinal: Int = try await db.dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT MAX(ordinal) as maxOrd FROM chat_turns WHERE conversation_id = ?
            """, arguments: [conversationID])
            return ((row?["maxOrd"] as Int?) ?? -1) + 1
        }
        let turn = ChatTurn(
            conversationID: conversationID, ordinal: nextOrdinal,
            prompt: prompt, runID: runID, transportKind: transportKind
        )
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO chat_turns
                    (id, conversation_id, ordinal, prompt, run_id, transport_kind,
                     status, assistant_text, error_message, created_at, completed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                turn.id, turn.conversationID, turn.ordinal, turn.prompt,
                turn.runID, turn.transportKind, turn.status.rawValue,
                turn.assistantText, turn.errorMessage, turn.createdAt, turn.completedAt,
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
            }
        }
    }

    public func turnByRunID(_ runID: String) async throws -> ChatTurn? {
        try await db.dbWriter.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM chat_turns WHERE run_id = ?", arguments: [runID]) else {
                return nil
            }
            return Self.decodeTurn(row)
        }
    }

    public func turns(conversationID: String) async throws -> [ChatTurn] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM chat_turns WHERE conversation_id = ?
                ORDER BY ordinal ASC
            """, arguments: [conversationID])
            return rows.compactMap(Self.decodeTurn)
        }
    }

    // MARK: - Artifacts

    public func upsertArtifact(_ artifact: ChatArtifact) async throws {
        try await db.dbWriter.write { db in
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
                artifact.summary, artifact.payloadJSON, artifact.status.rawValue,
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
            lastActivityAt: row["last_activity_at"] ?? .now
        )
    }

    private static func decodeTurn(_ row: Row) -> ChatTurn? {
        ChatTurn(
            id: row["id"] ?? "", conversationID: row["conversation_id"] ?? "",
            ordinal: row["ordinal"] ?? 0, prompt: row["prompt"] ?? "",
            runID: row["run_id"] ?? "", transportKind: row["transport_kind"] ?? "ssh",
            status: ChatTurn.Status(rawValue: row["status"] ?? "running") ?? .running,
            assistantText: row["assistant_text"] ?? "", errorMessage: row["error_message"],
            createdAt: row["created_at"] ?? .now, completedAt: row["completed_at"]
        )
    }

    private static func decodeArtifact(_ row: Row) -> ChatArtifact? {
        ChatArtifact(
            id: row["id"] ?? "", conversationID: row["conversation_id"] ?? "",
            turnID: row["turn_id"] ?? "", runID: row["run_id"] ?? "",
            kind: ChatArtifact.Kind(rawValue: row["kind"] ?? "tool") ?? .tool,
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
