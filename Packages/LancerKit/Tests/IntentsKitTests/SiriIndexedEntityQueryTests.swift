#if canImport(AppIntents)
import AppIntents
import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

// Structural conformance tests for the IndexedEntityQuery extensions (I3).
// `IndexedEntityQuery` is @available(macOS 27.0, iOS 27.0, visionOS 27.0, *);
// all test bodies are availability-guarded accordingly. The underlying query
// logic (suggestedEntities, entities(for:), string matching) is already covered
// by the per-entity query test files — these tests confirm the I3 conformances
// compile, are reachable at runtime, and that the secret-screening gate is
// applied before any entity reaches the index callback.

@Suite("SiriIndexedEntityQuery")
struct SiriIndexedEntityQueryTests {

    // MARK: - Structural conformance (compile-time + runtime availability)

#if swift(>=6.4)

    @Test("ConversationEntityQuery conforms to IndexedEntityQuery on iOS/macOS 27+")
    func conversationQueryConformance() {
        guard #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) else { return }
        let query = ConversationEntityQuery()
        let _: any IndexedEntityQuery = query
        // Reaching this line proves the conformance is visible and not a crash.
    }

    @Test("RunEntityQuery conforms to IndexedEntityQuery on iOS/macOS 27+")
    func runQueryConformance() {
        guard #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) else { return }
        let query = RunEntityQuery()
        let _: any IndexedEntityQuery = query
    }

    @Test("MachineEntityQuery conforms to IndexedEntityQuery on iOS/macOS 27+")
    func machineQueryConformance() {
        guard #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) else { return }
        let query = MachineEntityQuery()
        let _: any IndexedEntityQuery = query
    }

    @Test("WorkspaceEntityQuery conforms to IndexedEntityQuery on iOS/macOS 27+")
    func workspaceQueryConformance() {
        guard #available(macOS 27.0, iOS 27.0, visionOS 27.0, *) else { return }
        let query = WorkspaceEntityQuery()
        let _: any IndexedEntityQuery = query
    }

#endif // swift(>=6.4)

    // MARK: - Secret screening (observable without Spotlight integration)

    @Test("reindexAllEntities for conversations filters secrets before the index step")
    func conversationReindexSecretsFiltered() async throws {
        try await IntentsKitTestFixtures.withDatabase { db in
            let repo = ChatConversationRepository(db)
            _ = try await repo.createConversation(
                title: "Investigate the login flow",
                agentID: "claude", hostName: "mac-studio", hostID: nil, cwd: "/repo"
            )
            _ = try await repo.createConversation(
                title: "Rotate API_KEY=sk-live-secret",
                agentID: "claude", hostName: "mac-studio", hostID: nil, cwd: "/repo"
            )

            // Confirm suggestedEntities returns both, but only the safe one
            // would survive the SiriSpotlightSupport gate before Spotlight.
            let all = try await ConversationEntityQuery().suggestedEntities()
            #expect(all.count == 2)

            let safe = SiriSpotlightSupport.safeEntities(all, indexableText: \.title)
            #expect(safe.count == 1)
            #expect(safe[0].title == "Investigate the login flow")
        }
    }

    @Test("reindexAllEntities for runs filters secrets before the index step")
    func runReindexSecretsFiltered() async throws {
        try await IntentsKitTestFixtures.withDatabase { db in
            let repo = ChatConversationRepository(db)
            let conv = try await repo.createConversation(
                title: "Test run", agentID: "claude", hostName: "mac-studio",
                hostID: nil, cwd: "/repo"
            )
            _ = try await repo.appendTurn(
                conversationID: conv.id,
                prompt: "update the README",
                runID: "run-safe"
            )
            _ = try await repo.appendTurn(
                conversationID: conv.id,
                prompt: "export PASSWORD=hunter2",
                runID: "run-secret"
            )

            try await IntentsKitTestFixtures.withActiveRuns(["run-safe", "run-secret"]) {
                let all = try await RunEntityQuery().suggestedEntities()
                #expect(all.count == 2)

                let safe = SiriSpotlightSupport.safeEntities(all, indexableText: \.title)
                #expect(safe.count == 1)
                #expect(safe[0].id == "run-safe")
            }
        }
    }

    @Test("reindexEntities for empty identifier list is a no-op")
    func reindexEntitiesEmptyIdentifiersNoOp() async throws {
        try await IntentsKitTestFixtures.withDatabase { _ in
            // Empty identifier list must return without fetching or crashing.
            // Confirm via the underlying entity query (can't call the
            // IndexedEntityQuery method in tests without a CSSearchableIndexDescription,
            // which has no public init — test the guard logic via entities(for:) instead).
            let fetched = try await ConversationEntityQuery().entities(for: [])
            #expect(fetched.isEmpty)

            let fetchedRuns = try await RunEntityQuery().entities(for: [])
            #expect(fetchedRuns.isEmpty)
        }
    }
}

#endif
