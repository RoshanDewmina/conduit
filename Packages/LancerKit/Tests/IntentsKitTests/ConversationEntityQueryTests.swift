#if canImport(AppIntents)
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

@Suite("ConversationEntityQuery")
struct ConversationEntityQueryTests {
  @Test("exact ID resolves the conversation")
  func exactIDHit() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let conv = try await ChatConversationRepository(db).createConversation(
        title: "Refactor auth middleware",
        agentID: "claude",
        hostName: "mac-studio",
        hostID: nil,
        cwd: "/repo"
      )

      let hits = try await ConversationEntityQuery().entities(for: [conv.id])
      #expect(hits.count == 1)
      #expect(hits[0].title == "Refactor auth middleware")
    }
  }

  @Test("fuzzy title matches FTS-backed conversation")
  func fuzzyTitleHit() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let repo = ChatConversationRepository(db)
      _ = try await repo.createConversation(
        title: "Refactor auth middleware",
        agentID: "claude",
        hostName: "mac-studio",
        hostID: nil,
        cwd: "/repo"
      )

      let hits = try await ConversationEntityQuery().entities(matching: "auth")
      #expect(hits.count == 1)
      #expect(hits[0].title.contains("auth"))
    }
  }

  @Test("ambiguous query returns multiple conversations")
  func ambiguousMultiple() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let repo = ChatConversationRepository(db)
      _ = try await repo.createConversation(
        title: "Fix auth bug",
        agentID: "claude",
        hostName: "mac-studio",
        hostID: nil,
        cwd: "/repo"
      )
      _ = try await repo.createConversation(
        title: "Auth refactor plan",
        agentID: "claude",
        hostName: "mac-studio",
        hostID: nil,
        cwd: "/repo"
      )

      let hits = try await ConversationEntityQuery().entities(matching: "auth")
      #expect(hits.count == 2)
    }
  }

  @Test("empty store returns no conversations")
  func emptyStore() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      let query = ConversationEntityQuery()
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
