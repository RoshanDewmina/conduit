import Foundation
import GRDB
import ConduitCore

// MARK: - GRDB record conformance for Snippet

extension Snippet: FetchableRecord {
    public init(row: Row) throws {
        guard
            let idStr: String = row["id"],
            let idUUID = UUID(uuidString: idStr)
        else { throw ConduitError.databaseFailure(detail: "bad snippet id") }

        let hostTagsJSON: String = row["hostTags"] ?? "[]"
        let tagsJSON: String = row["tags"] ?? "[]"
        let argumentsJSON: String = row["arguments"] ?? "[]"
        let hostTags = (try? JSONDecoder().decode([String].self, from: Data(hostTagsJSON.utf8))) ?? []
        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
        let arguments = (try? JSONDecoder().decode([SnippetArgument].self, from: Data(argumentsJSON.utf8))) ?? []
        let createdAt: Date = row["createdAt"] ?? .now

        self.init(
            id: SnippetID(idUUID),
            name: row["name"] ?? "",
            body: row["body"] ?? "",
            hostTags: hostTags,
            tags: tags,
            arguments: arguments,
            useCount: row["useCount"] ?? 0,
            createdAt: createdAt,
            lastUsedAt: row["lastUsedAt"],
            modifiedAt: row["modifiedAt"] ?? createdAt
        )
    }
}

// MARK: - SnippetRepository

public actor SnippetRepository {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    /// Returns all snippets ordered by name.
    public func all() async throws -> [Snippet] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM snippets ORDER BY name COLLATE NOCASE")
            return try rows.map { try Snippet(row: $0) }
        }
    }

    /// Returns snippets whose name or body contains `query` (case-insensitive).
    public func search(_ query: String) async throws -> [Snippet] {
        guard !query.isEmpty else { return try await all() }
        let pattern = "%\(query)%"
        return try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM snippets WHERE name LIKE ? OR body LIKE ? ORDER BY name COLLATE NOCASE",
                arguments: [pattern, pattern]
            )
            return try rows.map { try Snippet(row: $0) }
        }
    }

    /// Inserts or updates a snippet, bumping modifiedAt to now.
    public func upsert(_ snippet: Snippet) async throws {
        try await upsertInternal(snippet, modifiedAt: .now)
    }

    /// Called by SyncEngine to apply a remote record, preserving its modifiedAt timestamp.
    public func upsertSync(_ snippet: Snippet) async throws {
        try await upsertInternal(snippet, modifiedAt: snippet.modifiedAt, clearTombstone: true)
    }

    private func upsertInternal(
        _ snippet: Snippet,
        modifiedAt: Date,
        clearTombstone: Bool = false
    ) async throws {
        let hostTagsJSON = (try? String(data: JSONEncoder().encode(snippet.hostTags), encoding: .utf8)) ?? "[]"
        let tagsJSON = (try? String(data: JSONEncoder().encode(snippet.tags), encoding: .utf8)) ?? "[]"
        let argumentsJSON = (try? String(data: JSONEncoder().encode(snippet.arguments), encoding: .utf8)) ?? "[]"
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO snippets (id, name, body, hostTags, tags, arguments, useCount, createdAt, lastUsedAt, modifiedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name=excluded.name,
                  body=excluded.body,
                  hostTags=excluded.hostTags,
                  tags=excluded.tags,
                  arguments=excluded.arguments,
                  useCount=excluded.useCount,
                  lastUsedAt=excluded.lastUsedAt,
                  modifiedAt=excluded.modifiedAt
            """, arguments: [
                snippet.id.uuidString,
                snippet.name,
                snippet.body,
                hostTagsJSON,
                tagsJSON,
                argumentsJSON,
                snippet.useCount,
                snippet.createdAt,
                snippet.lastUsedAt,
                modifiedAt,
            ])
            if clearTombstone {
                try db.execute(
                    sql: "DELETE FROM sync_tombstones WHERE id = ? AND recordType = 'Snippet'",
                    arguments: [snippet.id.uuidString]
                )
            }
        }
    }

    /// User-initiated delete: removes the record and records a tombstone for sync propagation.
    public func delete(id: SnippetID) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id.uuidString])
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_tombstones(id, recordType, deletedAt) VALUES (?, 'Snippet', ?)",
                arguments: [id.uuidString, Date.now]
            )
        }
    }

    /// Sync-driven delete: removes the record without adding a tombstone.
    public func deleteFromSync(id: SnippetID) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Bumps the lastUsedAt timestamp + increments useCount. Tier 2.4 uses
    /// `useCount * recencyDecay` for palette ranking.
    public func markUsed(id: SnippetID, at time: Date = .now) async throws {
        _ = try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE snippets SET lastUsedAt = ?, useCount = useCount + 1 WHERE id = ?",
                arguments: [time, id.uuidString]
            )
        }
    }

    /// Tier 2.4: snippets sorted by `recency × frequency` — the higher the
    /// useCount and the more recently used, the higher in the list.
    public func rankedForPalette(hostTags: [String] = []) async throws -> [Snippet] {
        let normalizedHostTags = Set(hostTags.map { $0.lowercased() })
        let all = try await self.all()
        let filtered = all.filter { snippet in
            if snippet.hostTags.isEmpty { return true }
            let snippetTags = Set(snippet.hostTags.map { $0.lowercased() })
            return !normalizedHostTags.isDisjoint(with: snippetTags)
        }
        let now = Date.timeIntervalSinceReferenceDate
        return filtered.sorted { a, b in
            score(a, now: now) > score(b, now: now)
        }
    }

    /// Recency × frequency score. Decays roughly e-fold per week of disuse.
    private func score(_ s: Snippet, now: TimeInterval) -> Double {
        let lastUsed = s.lastUsedAt?.timeIntervalSinceReferenceDate ?? s.createdAt.timeIntervalSinceReferenceDate
        let ageSeconds = max(0, now - lastUsed)
        let oneWeek: Double = 7 * 24 * 60 * 60
        let recency = exp(-ageSeconds / oneWeek)
        let frequency = log1p(Double(s.useCount))
        return recency * (1.0 + frequency)
    }
}
