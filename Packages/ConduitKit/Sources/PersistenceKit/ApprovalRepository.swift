import Foundation
@preconcurrency import GRDB
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

        // Governed-approvals context (MAJOR-7): blast radius + choices are stored
        // as JSON text columns; decode them back into the model so the governance
        // banner / ask-question UI survives the DB round-trip. A nil / malformed
        // value decodes to nil rather than failing the whole row.
        let blastRadiusJSON: String? = row["blast_radius"]
        let blastRadius = blastRadiusJSON
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(ApprovalBlastRadius.self, from: $0) }
        let choicesJSON: String? = row["choices"]
        let choices = choicesJSON
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }

        self.init(
            id: ApprovalID(idUUID),
            sessionID: SessionID(sessionUUID),
            agent: AgentSource(rawValue: agentStr) ?? .unknown,
            kind: Kind(rawValue: kindStr) ?? .command,
            command: row["command"],
            patch: row["patch"],
            cwd: row["cwd"] ?? "",
            risk: Risk(rawValue: row["risk"] ?? 0) ?? .low,
            createdAt: row["createdAt"] ?? .now,
            decidedAt: row["decidedAt"],
            decision: decisionStr.flatMap(Decision.init(rawValue:)),
            question: row["question"],
            choices: choices,
            answeredChoice: row["answered_choice"],
            toolName: row["tool_name"],
            toolUseID: row["tool_use_id"],
            agentSessionID: row["agent_session_id"],
            toolInput: row["tool_input"],
            blastRadius: blastRadius
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
        container["tool_name"] = toolName
        container["tool_use_id"] = toolUseID
        container["agent_session_id"] = agentSessionID
        container["tool_input"] = toolInput
        // Governed-approvals context (MAJOR-7): persist blast radius + choices as
        // JSON text so the governance banner / ask-question UI rehydrates from the
        // DB (the live VM re-reads rows via observe(), discarding the in-memory
        // ingest object). Without this the banner silently never renders.
        container["blast_radius"] = blastRadius
            .flatMap { try? JSONEncoder().encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) }
        container["question"] = question
        container["choices"] = choices
            .flatMap { try? JSONEncoder().encode($0) }
            .flatMap { String(data: $0, encoding: .utf8) }
        container["answered_choice"] = answeredChoice
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

    /// Whether a row exists for `id`. Combined with `decide`'s return value this
    /// distinguishes "already resolved" (exists && !changed) from "no local row
    /// yet" (cold-launch push-only) so the relay forwards the latter but never
    /// re-resolves the former.
    public func exists(id: ApprovalID) async throws -> Bool {
        try await db.dbWriter.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM approvals WHERE id = ?)",
                arguments: [id.uuidString]
            ) ?? false
        }
    }

    public func upsert(_ approval: Approval) async throws {
        try await db.dbWriter.write { db in
            try approval.save(db)
        }
    }

    /// Apply a first-decision-wins update. The `decision IS NULL` guard makes the
    /// first decision authoritative: a lingering lock-screen banner (or a
    /// double-tap) can never flip an already-resolved gate. Returns `true` only
    /// when this call actually resolved a still-pending row, so callers fire the
    /// wire `respond(...)` / audit exactly once.
    @discardableResult
    public func decide(id: ApprovalID, decision: Approval.Decision) async throws -> Bool {
        try await db.dbWriter.write { db in
            try db.execute(
                sql: "UPDATE approvals SET decision = ?, decidedAt = ? WHERE id = ? AND decision IS NULL",
                arguments: [decision.rawValue, Date(), id.uuidString]
            )
            return db.changesCount > 0
        }
    }

    // Returns a stream that emits the full approvals list whenever the DB changes.
    // Uses GRDB ValueObservation via callback API.
    public func observe() -> AsyncThrowingStream<[Approval], any Error> {
        let writer = db.dbWriter
        let (stream, cont) = AsyncThrowingStream<[Approval], any Error>.makeStream()
        let observation = ValueObservation.tracking { db -> [Approval] in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM approvals ORDER BY createdAt DESC")
            return try rows.map { try Approval(row: $0) }
        }
        // Use nonisolated(unsafe) to satisfy @Sendable closure capture for
        // AnyDatabaseCancellable which predates Sendable conformance in GRDB.
        nonisolated(unsafe) let cancellable = observation.start(in: writer,
            onError: { cont.finish(throwing: $0) },
            onChange: { cont.yield($0) }
        )
        cont.onTermination = { _ in cancellable.cancel() }
        return stream
    }
}
