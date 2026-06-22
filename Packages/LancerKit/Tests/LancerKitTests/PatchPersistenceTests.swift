import Testing
import Foundation
import GRDB
@testable import PersistenceKit
@testable import LancerCore

@Suite("Patch persistence")
struct PatchPersistenceTests {
    @Test func patchTableExists() async throws {
        let db = try AppDatabase.inMemory()
        let tableExists = try await db.dbWriter.read { db in
            try db.tableExists("patches")
        }
        #expect(tableExists == true)
    }

    @Test func insertAndRead() async throws {
        let db = try AppDatabase.inMemory()
        let patchId = UUID().uuidString
        let sessionId = UUID().uuidString

        try await db.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO patches (id, sessionId, agent, unifiedDiff, createdAt)
                VALUES (?, ?, ?, ?, ?)
            """, arguments: [patchId, sessionId, "claude-code", "--- a/file\n+++ b/file\n", Date()])
        }

        let row = try await db.dbWriter.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM patches WHERE id = ?", arguments: [patchId])
        }
        #expect(row != nil)
        #expect((row?["agent"] as String?) == "claude-code")

        let repo = ApprovalRepository(db)
        let approval = Approval(
            sessionID: SessionID(),
            agent: .claudeCode,
            kind: .command,
            command: "rm -rf /",
            cwd: "/",
            risk: .critical
        )

        try await repo.upsert(approval)
        let stored = try await repo.pending()

        #expect(stored.count == 1)
        #expect(stored[0].risk == .critical)
    }
}
