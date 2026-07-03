import Foundation
import GRDB
import LancerCore

/// CRUD for persisted `Workspace` records, scoped by owning machine. Follows
/// `ChatConversationRepository`'s actor + async/throws shape.
public actor WorkspaceRepository {
    private let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    @discardableResult
    public func create(
        name: String,
        machineID: RelayMachineID,
        path: String,
        lastBranch: String? = nil
    ) async throws -> Workspace {
        let workspace = Workspace(name: name, machineID: machineID, path: path, lastBranch: lastBranch)
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO workspaces (id, name, machine_id, path, last_branch, created_at, last_used_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                workspace.id, workspace.name, workspace.machineID.uuidString,
                workspace.path, workspace.lastBranch, workspace.createdAt, workspace.lastUsedAt,
            ])
        }
        return workspace
    }

    public func workspace(id: String) async throws -> Workspace? {
        try await db.dbWriter.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM workspaces WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return Self.decode(row)
        }
    }

    /// All workspaces belonging to `machineID`, most-recently-used first. Never
    /// returns another machine's workspaces.
    public func list(machineID: RelayMachineID) async throws -> [Workspace] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM workspaces WHERE machine_id = ? ORDER BY last_used_at DESC
            """, arguments: [machineID.uuidString])
            return rows.compactMap(Self.decode)
        }
    }

    public func rename(_ id: String, name: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "UPDATE workspaces SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    /// Bumps `lastUsedAt` to now — called whenever a workspace is picked for a
    /// new run, so the list stays sorted by recency. Binds a precise `Date()`
    /// rather than SQL `CURRENT_TIMESTAMP`, which truncates to whole seconds and
    /// can compare as *earlier* than a sub-second `createdAt`/`lastUsedAt` from
    /// the same instant.
    public func touch(_ id: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "UPDATE workspaces SET last_used_at = ? WHERE id = ?", arguments: [Date(), id])
        }
    }

    public func updateLastBranch(_ id: String, branch: String?) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "UPDATE workspaces SET last_branch = ? WHERE id = ?", arguments: [branch, id])
        }
    }

    public func delete(_ id: String) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM workspaces WHERE id = ?", arguments: [id])
        }
    }

    private static func decode(_ row: Row) -> Workspace? {
        guard let machineIDString: String = row["machine_id"],
              let machineUUID = UUID(uuidString: machineIDString) else {
            return nil
        }
        return Workspace(
            id: row["id"] ?? "",
            name: row["name"] ?? "",
            machineID: RelayMachineID(machineUUID),
            path: row["path"] ?? "",
            lastBranch: row["last_branch"],
            createdAt: row["created_at"] ?? .now,
            lastUsedAt: row["last_used_at"] ?? .now
        )
    }
}
