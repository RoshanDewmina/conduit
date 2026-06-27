// One-snapshot-per-host CRUD. Overwrites on each successful capture; reads
// from `SessionViewModel.connect()` to decide whether to issue an agent
// resume command via `AgentResumeBuilder`.

import Foundation
import GRDB
import LancerCore

public actor SessionSnapshotRepository {
    private let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    /// Read the snapshot for a single host. Returns nil when no record exists.
    public func snapshot(for hostID: HostID) async throws -> SessionSnapshot? {
        try await db.dbWriter.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM session_snapshots WHERE hostID = ?",
                arguments: [hostID.uuidString]
            ).flatMap(Self.decode)
        }
    }

    /// Read all snapshots, most-recently-used first. Used by "Resume last
    /// session" sheets and the Workspaces sort order.
    public func allRecent() async throws -> [SessionSnapshot] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM session_snapshots ORDER BY lastUsedTime DESC"
            )
            return rows.compactMap(Self.decode)
        }
    }

    /// Insert or replace this host's snapshot.
    public func upsert(_ snapshot: SessionSnapshot) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO session_snapshots
                    (hostID, lastUsedTime, agentID, agentSessionID, agentWorkingDirectory, tmuxSessionName)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(hostID) DO UPDATE SET
                  lastUsedTime=excluded.lastUsedTime,
                  agentID=excluded.agentID,
                  agentSessionID=excluded.agentSessionID,
                  agentWorkingDirectory=excluded.agentWorkingDirectory,
                  tmuxSessionName=excluded.tmuxSessionName
            """, arguments: [
                snapshot.hostID.uuidString,
                snapshot.lastUsedTime,
                snapshot.agentID,
                snapshot.agentSessionID,
                snapshot.agentWorkingDirectory,
                snapshot.tmuxSessionName,
            ])
        }
    }

    /// Update only `lastUsedTime` (used after a heartbeat — keeps row warm
    /// without touching the agent fields).
    public func touch(hostID: HostID, at time: Date = .now) async throws {
        _ = try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO session_snapshots (hostID, lastUsedTime)
                VALUES (?, ?)
                ON CONFLICT(hostID) DO UPDATE SET lastUsedTime = excluded.lastUsedTime
            """, arguments: [hostID.uuidString, time])
        }
    }

    /// Drop the snapshot (e.g. user toggles off auto-resume).
    public func delete(hostID: HostID) async throws {
        _ = try await db.dbWriter.write { db in
            try db.execute(
                sql: "DELETE FROM session_snapshots WHERE hostID = ?",
                arguments: [hostID.uuidString]
            )
        }
    }

    // MARK: - Decode

    private static func decode(_ row: Row) -> SessionSnapshot? {
        guard
            let uuidString: String = row["hostID"],
            let uuid = UUID(uuidString: uuidString),
            let time: Date = row["lastUsedTime"]
        else { return nil }
        return SessionSnapshot(
            hostID: HostID(uuid),
            lastUsedTime: time,
            agentID: row["agentID"],
            agentSessionID: row["agentSessionID"],
            agentWorkingDirectory: row["agentWorkingDirectory"],
            tmuxSessionName: row["tmuxSessionName"]
        )
    }
}
