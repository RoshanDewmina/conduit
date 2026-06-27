import Foundation
@preconcurrency import GRDB
import LancerCore

public actor AuditRepository {
    private let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    public func record(
        hostID: HostID,
        type: AuditEvent.EventType,
        metadata: [String: String] = [:]
    ) async throws {
        let metadataJSON = (try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)) ?? "{}"
        let event = AuditEvent(hostID: hostID, type: type, metadata: metadata)
        try await db.dbWriter.write { db in
            try db.execute(
                sql: """
                    INSERT INTO audit_events (id, hostId, type, metadata, createdAt)
                    VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    event.id.uuidString,
                    event.hostID.uuidString,
                    event.type.rawValue,
                    metadataJSON,
                    event.createdAt,
                ]
            )
        }
    }

    public func recent(limit: Int = 500) async throws -> [AuditEvent] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, hostId, type, metadata, createdAt
                    FROM audit_events
                    ORDER BY createdAt DESC
                    LIMIT ?
                """,
                arguments: [max(1, limit)]
            )
            return rows.compactMap(Self.decode)
        }
    }

    public func exportJSON(limit: Int = 2_000) async throws -> Data {
        let events = try await recent(limit: limit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(events)
    }

    private static func decode(_ row: Row) -> AuditEvent? {
        guard let idStr: String = row["id"],
              let id = UUID(uuidString: idStr),
              let hostIDStr: String = row["hostId"],
              let hostUUID = UUID(uuidString: hostIDStr),
              let typeRaw: String = row["type"],
              let type = AuditEvent.EventType(rawValue: typeRaw) else {
            return nil
        }

        let metadataRaw: String = row["metadata"] ?? "{}"
        let metadataData = Data(metadataRaw.utf8)
        let metadata = (try? JSONDecoder().decode([String: String].self, from: metadataData)) ?? [:]
        let createdAt: Date = row["createdAt"] ?? .now

        return AuditEvent(
            id: id,
            hostID: HostID(hostUUID),
            type: type,
            metadata: metadata,
            createdAt: createdAt
        )
    }
}
