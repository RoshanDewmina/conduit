import Foundation
import GRDB

/// Tracks locally-deleted records so SyncEngine can propagate deletions to CloudKit.
/// Tombstones are cleared after a successful push.
public actor SyncTombstoneRepository {
    private let db: AppDatabase

    public init(_ db: AppDatabase) { self.db = db }

    public func insert(id: String, recordType: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_tombstones(id, recordType, deletedAt) VALUES (?, ?, ?)",
                arguments: [id, recordType, Date.now]
            )
        }
    }

    public func pending(recordType: String) async throws -> [String] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM sync_tombstones WHERE recordType = ? ORDER BY deletedAt",
                arguments: [recordType]
            )
            return rows.compactMap { $0["id"] as String? }
        }
    }

    public func remove(ids: [String], recordType: String) async throws {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let args = StatementArguments([recordType] + ids)
        try await db.dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM sync_tombstones WHERE recordType = ? AND id IN (\(placeholders))",
                arguments: args
            )
        }
    }
}
