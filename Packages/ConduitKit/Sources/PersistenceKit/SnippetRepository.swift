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
        let hostTags = (try? JSONDecoder().decode([String].self, from: Data(hostTagsJSON.utf8))) ?? []
        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []

        self.init(
            id: SnippetID(idUUID),
            name: row["name"] ?? "",
            body: row["body"] ?? "",
            hostTags: hostTags,
            tags: tags,
            createdAt: row["createdAt"] ?? .now,
            lastUsedAt: row["lastUsedAt"]
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

    /// Inserts or updates a snippet.
    public func upsert(_ snippet: Snippet) async throws {
        let hostTagsJSON = (try? String(data: JSONEncoder().encode(snippet.hostTags), encoding: .utf8)) ?? "[]"
        let tagsJSON = (try? String(data: JSONEncoder().encode(snippet.tags), encoding: .utf8)) ?? "[]"
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO snippets (id, name, body, hostTags, tags, createdAt, lastUsedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name=excluded.name,
                  body=excluded.body,
                  hostTags=excluded.hostTags,
                  tags=excluded.tags,
                  lastUsedAt=excluded.lastUsedAt
            """, arguments: [
                snippet.id.uuidString,
                snippet.name,
                snippet.body,
                hostTagsJSON,
                tagsJSON,
                snippet.createdAt,
                snippet.lastUsedAt,
            ])
        }
    }

    /// Deletes the snippet with the given id.
    public func delete(id: SnippetID) async throws {
        _ = try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Bumps the lastUsedAt timestamp for the given snippet.
    /// Note: the `snippets` table does not have a `useCount` column in the v1 migration.
    /// Once the migration is updated to add `useCount` (see m8-existing-file-patches.md),
    /// this method will also increment that column.
    public func markUsed(id: SnippetID, at time: Date = .now) async throws {
        _ = try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE snippets SET lastUsedAt = ? WHERE id = ?",
                arguments: [time, id.uuidString]
            )
        }
    }
}
