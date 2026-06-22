import Foundation
import GRDB
import LancerCore

// Both Foundation (NetService) and some GRDB symbols collide with the
// shorthand name `Host`. We standardize on the LancerCore value type by
// fully qualifying every reference.

public actor HostRepository {
    private let db: AppDatabase
    public init(_ db: AppDatabase) { self.db = db }

    public func all() async throws -> [LancerCore.Host] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM hosts ORDER BY name COLLATE NOCASE")
            return try rows.map(Self.decode)
        }
    }

    public func upsert(_ host: LancerCore.Host) async throws {
        try await upsertInternal(host, modifiedAt: .now)
    }

    /// Called by SyncEngine to apply a remote record, preserving its modifiedAt timestamp.
    /// Also clears any pending tombstone for this ID (remote re-creation wins over local deletion).
    public func upsertSync(_ host: LancerCore.Host) async throws {
        try await upsertInternal(host, modifiedAt: host.modifiedAt, clearTombstone: true)
    }

    private func upsertInternal(
        _ host: LancerCore.Host,
        modifiedAt: Date,
        clearTombstone: Bool = false
    ) async throws {
        let tagsJSON = (try? String(data: JSONEncoder().encode(host.tags), encoding: .utf8)) ?? "[]"
        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO hosts (id, name, hostname, port, username, authMethodType, authMethodKeyTag,
                                   tags, hostKeyFingerprint, preferredShell, tmuxSessionName,
                                   startupCommand, autoResume,
                                   createdAt, lastConnectedAt, modifiedAt, syncedKeyHint)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name=excluded.name, hostname=excluded.hostname, port=excluded.port,
                  username=excluded.username, authMethodType=excluded.authMethodType,
                  authMethodKeyTag=excluded.authMethodKeyTag, tags=excluded.tags,
                  hostKeyFingerprint=excluded.hostKeyFingerprint,
                  preferredShell=excluded.preferredShell, tmuxSessionName=excluded.tmuxSessionName,
                  startupCommand=excluded.startupCommand, autoResume=excluded.autoResume,
                  lastConnectedAt=excluded.lastConnectedAt,
                  modifiedAt=excluded.modifiedAt, syncedKeyHint=excluded.syncedKeyHint
            """, arguments: [
                host.id.uuidString,
                host.name,
                host.hostname,
                host.port,
                host.username,
                Self.authType(host.authMethod),
                Self.authKeyTag(host.authMethod),
                tagsJSON,
                host.hostKeyFingerprint,
                host.preferredShell,
                host.tmuxSessionName,
                host.startupCommand,
                host.autoResume,
                host.createdAt,
                host.lastConnectedAt,
                modifiedAt,
                host.syncedKeyHint,
            ])
            if clearTombstone {
                try db.execute(
                    sql: "DELETE FROM sync_tombstones WHERE id = ? AND recordType = 'Host'",
                    arguments: [host.id.uuidString]
                )
            }
        }
    }

    /// User-initiated delete: removes the record and records a tombstone for sync propagation.
    public func delete(id: HostID) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM hosts WHERE id = ?", arguments: [id.uuidString])
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_tombstones(id, recordType, deletedAt) VALUES (?, 'Host', ?)",
                arguments: [id.uuidString, Date.now]
            )
        }
    }

    /// Sync-driven delete: removes the record without adding a tombstone (remote already deleted it).
    public func deleteFromSync(id: HostID) async throws {
        try await db.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM hosts WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func touch(id: HostID, at time: Date = .now) async throws {
        _ = try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE hosts SET lastConnectedAt = ? WHERE id = ?",
                arguments: [time, id.uuidString]
            )
        }
    }

    /// Updates the `tmuxSessionName` column for the given host.
    /// Pass `nil` to clear any stored session name.
    public func updateTmuxName(id: HostID, _ name: String?) async throws {
        _ = try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE hosts SET tmuxSessionName = ? WHERE id = ?",
                arguments: [name, id.uuidString]
            )
        }
    }

    // MARK: - Row decoding

    private static func decode(_ row: Row) throws -> LancerCore.Host {
        guard
            let uuidString: String = row["id"],
            let uuid = UUID(uuidString: uuidString)
        else { throw LancerError.databaseFailure(detail: "bad host id") }

        let tagsJSON: String = row["tags"] ?? "[]"
        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
        let auth = try decodeAuth(typeStr: row["authMethodType"] ?? "password",
                                   keyTag: row["authMethodKeyTag"])

        let createdAt: Date = row["createdAt"] ?? .now
        return LancerCore.Host(
            id: HostID(uuid),
            name: row["name"] ?? "",
            hostname: row["hostname"] ?? "",
            port: row["port"] ?? 22,
            username: row["username"] ?? "",
            authMethod: auth,
            tags: tags,
            hostKeyFingerprint: row["hostKeyFingerprint"],
            preferredShell: row["preferredShell"],
            tmuxSessionName: row["tmuxSessionName"],
            startupCommand: row["startupCommand"],
            autoResume: row["autoResume"] ?? true,
            createdAt: createdAt,
            lastConnectedAt: row["lastConnectedAt"],
            modifiedAt: row["modifiedAt"] ?? createdAt,
            syncedKeyHint: row["syncedKeyHint"]
        )
    }

    private static func decodeAuth(typeStr: String, keyTag: String?) throws -> LancerCore.Host.AuthMethod {
        switch typeStr {
        case "password": return .password
        case "agent":    return .agent
        case "ed25519":
            guard let keyTag, let uuid = UUID(uuidString: keyTag) else {
                throw LancerError.databaseFailure(detail: "ed25519 missing key tag")
            }
            return .ed25519(keyID: KeyID(uuid))
        default: return .password
        }
    }

    private static func authType(_ m: LancerCore.Host.AuthMethod) -> String {
        switch m {
        case .password:   "password"
        case .ed25519:    "ed25519"
        case .agent:      "agent"
        }
    }

    private static func authKeyTag(_ m: LancerCore.Host.AuthMethod) -> String? {
        if case let .ed25519(keyID) = m { return keyID.uuidString }
        return nil
    }
}
