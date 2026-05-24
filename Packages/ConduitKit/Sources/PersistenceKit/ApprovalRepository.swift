import Foundation
import GRDB
import ConduitCore

// MARK: - GRDB conformance for Approval
extension Approval: FetchableRecord {
    public init(row: Row) throws {
        guard let idStr: String = row["id"], let idUUID = UUID(uuidString: idStr) else {
            throw ConduitError.databaseFailure(detail: "bad approval id")
        }
        guard let sessionIdStr: String = row["sessionId"],
              let sessionUUID = UUID(uuidString: sessionIdStr) else {
            throw ConduitError.databaseFailure(detail: "bad sessionId")
        }
        let agentStr: String = row["agent"] ?? "unknown"
        let kindStr: String = row["kind"] ?? "command"
        let decisionStr: String? = row["decision"]

        self.init(
            id: ApprovalID(idUUID),
            sessionID: SessionID(sessionUUID),
            agent: AgentSource(rawValue: agentStr) ?? .unknown,
            kind: Kind(rawValue: kindStr) ?? .command,
            command: row["command"],
            patch: row["patch"],
            cwd: row["cwd"] ?? "",
            risk: Risk(rawValue: (row["risk"] as? Int) ?? 0) ?? .low,
            createdAt: row["createdAt"] ?? .now,
            decidedAt: row["decidedAt"],
            decision: decisionStr.flatMap(Decision.init(rawValue:))
        )
    }
}

extension Approval: PersistableRecord {
    public static var databaseTableName: String { "approvals" }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.uuidString
        container["sessionId"] = sessionID.uuidString
        container["agent"] = agent.rawValue
        container["kind"] = kind.rawValue
        container["command"] = command
        container["patch"] = patch
        container["cwd"] = cwd
        container["risk"] = risk.rawValue
        container["createdAt"] = createdAt
        container["decidedAt"] = decidedAt
        container["decision"] = decision?.rawValue
    }
}

// MARK: - ApprovalRepository

public actor ApprovalRepository {
    private let db: AppDatabase

    public init(_ db: AppDatabase) {
        self.db = db
    }

    public func all() async throws -> [Approval] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM approvals ORDER BY createdAt DESC")
            return try rows.map { try Approval(row: $0) }
        }
    }

    public func pending() async throws -> [Approval] {
        try await db.dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM approvals WHERE decision IS NULL ORDER BY createdAt DESC")
            return try rows.map { try Approval(row: $0) }
        }
    }

    public func upsert(_ approval: Approval) async throws {
        try await db.dbWriter.write { db in
            try approval.save(db)
        }
    }

    public func decide(id: ApprovalID, decision: Approval.Decision) async throws {
        try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE approvals SET decision = ?, decidedAt = ? WHERE id = ?",
                arguments: [decision.rawValue, Date(), id.uuidString]
            )
        }
    }

    // Returns a stream that emits the full approvals list whenever the DB changes.
    // Uses GRDB ValueObservation via callback API.
    public func observe() -> AsyncThrowingStream<[Approval], Error> {
        let writer = db.dbWriter
        let (stream, cont) = AsyncThrowingStream<[Approval], Error>.makeStream()
        let observation = ValueObservation.tracking { db -> [Approval] in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM approvals ORDER BY createdAt DESC")
            return try rows.map { try Approval(row: $0) }
        }
        let cancellable = observation.start(in: writer,
            onError: { cont.finish(throwing: $0) },
            onChange: { cont.yield($0) }
        )
        cont.onTermination = { _ in cancellable.cancel() }
        return stream
    }
}
