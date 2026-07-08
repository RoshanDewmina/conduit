#if canImport(AppIntents)
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

@Suite("ApprovalEntityQuery")
struct ApprovalEntityQueryTests {
  private func seedApproval(
    db: AppDatabase,
    command: String,
    hostName: String
  ) async throws -> Approval {
    let sessionID = SessionID()
    let approval = Approval(
      sessionID: sessionID,
      agent: .claudeCode,
      kind: .command,
      command: command,
      cwd: "/repo",
      risk: .high
    )
    try await ApprovalRepository(db).upsert(approval)
    try await BlockRepository(db).persist(
      Block(
        sessionID: sessionID,
        prompt: Block.PromptInfo(cwd: "/repo", hostName: hostName),
        command: command
      )
    )
    return approval
  }

  @Test("exact ID resolves the pending approval")
  func exactIDHit() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let approval = try await seedApproval(db: db, command: "rm -rf build", hostName: "mac-studio")

      let hits = try await ApprovalEntityQuery().entities(for: [approval.id.uuidString])
      #expect(hits.count == 1)
      #expect(hits[0].title == "'rm -rf build' · high · mac-studio")
    }
  }

  @Test("fuzzy title matches command text")
  func fuzzyTitleHit() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      _ = try await seedApproval(db: db, command: "rm -rf build", hostName: "mac-studio")

      let hits = try await ApprovalEntityQuery().entities(matching: "build")
      #expect(hits.count == 1)
      #expect(hits[0].title.contains("rm -rf build"))
    }
  }

  @Test("ambiguous query returns multiple pending approvals")
  func ambiguousMultiple() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      _ = try await seedApproval(db: db, command: "rm -rf build", hostName: "mac-studio")
      _ = try await seedApproval(db: db, command: "rm -rf dist", hostName: "mac-studio")

      let hits = try await ApprovalEntityQuery().entities(matching: "rm")
      #expect(hits.count == 2)
    }
  }

  @Test("empty store returns no approvals")
  func emptyStore() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      let query = ApprovalEntityQuery()
      let suggested = try await query.suggestedEntities()
      let byID = try await query.entities(for: ["missing"])
      let byTitle = try await query.entities(matching: "anything")
      #expect(suggested.isEmpty)
      #expect(byID.isEmpty)
      #expect(byTitle.isEmpty)
    }
  }
}
#endif
