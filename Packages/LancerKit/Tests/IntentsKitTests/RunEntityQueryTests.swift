#if canImport(AppIntents)
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

@Suite("RunEntityQuery")
struct RunEntityQueryTests {
  @Test("exact ID resolves the active run")
  func exactIDHit() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      try await IntentsKitTestFixtures.withActiveRuns(["run-exact"]) {
        let hits = try await RunEntityQuery().entities(for: ["run-exact"])
        #expect(hits.count == 1)
        #expect(hits[0].id == "run-exact")
      }
    }
  }

  @Test("fuzzy title matches run prompt")
  func fuzzyTitleHit() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let conv = try await ChatConversationRepository(db).createConversation(
        title: "Run thread",
        agentID: "claude",
        hostName: "mac-studio",
        hostID: nil,
        cwd: "/repo"
      )
      _ = try await ChatConversationRepository(db).appendTurn(
        conversationID: conv.id,
        prompt: "fix flaky tests",
        runID: "run-fuzzy"
      )

      try await IntentsKitTestFixtures.withActiveRuns(["run-fuzzy"]) {
        let hits = try await RunEntityQuery().entities(matching: "flaky")
        #expect(hits.count == 1)
        #expect(hits[0].title == "fix flaky tests")
      }
    }
  }

  @Test("ambiguous query returns multiple active runs")
  func ambiguousMultiple() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let repo = ChatConversationRepository(db)
      let conv = try await repo.createConversation(
        title: "Runs",
        agentID: "claude",
        hostName: "mac-studio",
        hostID: nil,
        cwd: "/repo"
      )
      _ = try await repo.appendTurn(conversationID: conv.id, prompt: "fix auth tests", runID: "run-a")
      _ = try await repo.appendTurn(conversationID: conv.id, prompt: "fix api tests", runID: "run-b")

      try await IntentsKitTestFixtures.withActiveRuns(["run-a", "run-b"]) {
        let hits = try await RunEntityQuery().entities(matching: "tests")
        #expect(hits.count == 2)
      }
    }
  }

  @Test("empty store returns no runs")
  func emptyStore() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      try await IntentsKitTestFixtures.withActiveRuns([]) {
        let query = RunEntityQuery()
        let suggested = try await query.suggestedEntities()
        let byID = try await query.entities(for: ["missing"])
        let byTitle = try await query.entities(matching: "anything")
        #expect(suggested.isEmpty)
        #expect(byID.isEmpty)
        #expect(byTitle.isEmpty)
      }
    }
  }
}
#endif
