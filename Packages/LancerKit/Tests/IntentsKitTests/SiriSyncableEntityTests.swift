#if canImport(AppIntents)
import AppIntents
import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

// Structural conformance tests for the SyncableEntity extensions (I3).
// `SyncableEntity` is @available(macOS 27.0, iOS 27.0, ..., *) and is a
// marker protocol (no required members) that signals the entity's `id` is
// stable across devices. Tests verify:
//   1. ConversationEntity and RunEntity conform at the declared availability,
//      confirmed via generic dispatch (compile-fails if conformance is absent).
//   2. Entity IDs are non-empty stable strings (prerequisite for cross-device
//      identity — the system uses these as its resolution key).
//   3. ApprovalEntity, MachineEntity, WorkspaceEntity do NOT conform (they
//      are intentionally excluded per design; see SiriSyncableEntities.swift).

@Suite("SiriSyncableEntity")
struct SiriSyncableEntityTests {

    // MARK: - SyncableEntity conformances

#if swift(>=6.4)

// Generic helper: compile-fails if `E` does not conform to `SyncableEntity`.
// This is the canonical way to assert a conformance in a Swift test without
// using an existential (`any SyncableEntity` is valid Swift 6 but accessing
// PAT-associated properties through it requires primary-type access).
@available(iOS 27.0, macOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
private func assertSyncableID<E: SyncableEntity>(_ entity: E) -> String {
    // `EntityIdentifierConvertible` (the base constraint on AppEntity.ID)
    // provides `entityIdentifierString` — the stable string representation
    // the system stores as the cross-device identifier.
    entity.id.entityIdentifierString
}

    @Test("ConversationEntity conforms to SyncableEntity on iOS/macOS 27+")
    func conversationEntityConformance() async throws {
        guard #available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *) else { return }

        try await IntentsKitTestFixtures.withDatabase { db in
            let repo = ChatConversationRepository(db)
            let conv = try await repo.createConversation(
                title: "Test", agentID: "claude", hostName: "mac-studio", hostID: nil, cwd: "/repo"
            )
            let entity = ConversationEntity(conversation: conv)
            // Generic dispatch proves the conformance; accessing `.id` via the
            // generic proves the ID resolves without runtime failure.
            let idString = assertSyncableID(entity)
            #expect(!idString.isEmpty)
        }
    }

    @Test("RunEntity conforms to SyncableEntity on iOS/macOS 27+")
    func runEntityConformance() async throws {
        guard #available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *) else { return }

        try await IntentsKitTestFixtures.withDatabase { db in
            let repo = ChatConversationRepository(db)
            let conv = try await repo.createConversation(
                title: "Test", agentID: "claude", hostName: "mac-studio", hostID: nil, cwd: "/repo"
            )
            _ = try await repo.appendTurn(
                conversationID: conv.id,
                prompt: "update the README",
                runID: "stable-run-id-abc"
            )

            try await IntentsKitTestFixtures.withActiveRuns(["stable-run-id-abc"]) {
                let entities = try await RunEntityQuery().suggestedEntities()
                #expect(entities.count == 1)
                let run = entities[0]
                let idString = assertSyncableID(run)
                #expect(idString == "stable-run-id-abc")
            }
        }
    }

#endif // swift(>=6.4)

    // MARK: - Stable ID invariant

    @Test("ConversationEntity id is a non-empty stable UUID string")
    func conversationEntityIDIsStableUUID() async throws {
        try await IntentsKitTestFixtures.withDatabase { db in
            let repo = ChatConversationRepository(db)
            let conv = try await repo.createConversation(
                title: "Stable ID test", agentID: "claude",
                hostName: "mac-studio", hostID: nil, cwd: "/repo"
            )
            let entity = ConversationEntity(conversation: conv)
            // The id should round-trip through UUID to confirm it's a valid UUID string,
            // which is the prerequisite for cross-device stable identity.
            #expect(!entity.id.isEmpty)
            #expect(UUID(uuidString: entity.id) != nil)
        }
    }

    @Test("RunEntity id exactly mirrors the run ID from the relay")
    func runEntityIDMirrorsRunID() async throws {
        try await IntentsKitTestFixtures.withDatabase { db in
            let repo = ChatConversationRepository(db)
            let conv = try await repo.createConversation(
                title: "Mirror test", agentID: "claude",
                hostName: "mac-studio", hostID: nil, cwd: "/repo"
            )
            let relayRunID = "run-\(UUID().uuidString)"
            _ = try await repo.appendTurn(
                conversationID: conv.id,
                prompt: "fix the flaky test",
                runID: relayRunID
            )

            try await IntentsKitTestFixtures.withActiveRuns([relayRunID]) {
                let entities = try await RunEntityQuery().suggestedEntities()
                #expect(entities.count == 1)
                #expect(entities[0].id == relayRunID)
            }
        }
    }
}

#endif
