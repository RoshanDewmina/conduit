// iOS 27 fast-follow — Core Spotlight entity donation via IntentEntityCatalog.

import AppIntents
import CoreSpotlight
import Foundation
import PersistenceKit
import SessionFeature

@available(iOS 18.0, *)
@MainActor
final class SiriEntityIndexer {
    static let shared = SiriEntityIndexer()

    private var lastApprovalIDs: Set<String> = []
    private var lastRunIDs: Set<String> = []

    private init() {}

    // MARK: - Full refresh (app launch)

    func refreshAll() async {
        do {
            try await refreshConversations()
            try await refreshMachines()
            try await refreshWorkspaces()
            try await refreshActiveRuns()
            try await refreshPendingApprovals()
        } catch {
            // Indexing is best-effort; failures must not break app launch.
        }
    }

    // MARK: - Typed refresh

    func refreshConversations() async throws {
        let catalog = try SiriIntentSupport.openCatalog()
        let records = try await catalog.conversations(limit: 100)
        let entities = records.map(SiriIndexedEntityFactory.conversation)
        try await SpotlightIndexBridge.index(entities, priority: 0)
    }

    func refreshMachines() async throws {
        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        let records = try await catalog.machines(relayMachines: relay)
        let entities = records.map(SiriIndexedEntityFactory.machine)
        try await SpotlightIndexBridge.index(entities, priority: 0)
    }

    func refreshWorkspaces() async throws {
        let catalog = try SiriIntentSupport.openCatalog()
        let records = try await catalog.workspaces()
        let entities = records.map(SiriIndexedEntityFactory.workspace)
        try await SpotlightIndexBridge.index(entities, priority: 0)
    }

    func refreshActiveRuns() async throws {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()
        let records = try await catalog.activeRuns(activeRunIDs: active)
        let newIDs = Set(records.map(\.id))
        let stale = lastRunIDs.subtracting(newIDs)
        if !stale.isEmpty {
            try await SpotlightIndexBridge.delete(identifiers: Array(stale))
        }
        lastRunIDs = newIDs
        guard !records.isEmpty else { return }
        let entities = records.map(SiriIndexedEntityFactory.run)
        try await SpotlightIndexBridge.index(entities, priority: 1)
    }

    func refreshPendingApprovals() async throws {
        let catalog = try SiriIntentSupport.openCatalog()
        let records = try await catalog.pendingApprovals()
        let newIDs = Set(records.map(\.id))
        let stale = lastApprovalIDs.subtracting(newIDs)
        if !stale.isEmpty {
            try await SpotlightIndexBridge.delete(identifiers: Array(stale))
        }
        lastApprovalIDs = newIDs
        guard !records.isEmpty else { return }
        let entities = records.map(SiriIndexedEntityFactory.approval)
        try await SpotlightIndexBridge.index(entities, priority: 2)
    }

    // MARK: - Incremental index

    func index(conversations: [ConversationEntity]) async throws {
        guard !conversations.isEmpty else { return }
        try await SpotlightIndexBridge.index(conversations, priority: 0)
    }

    func index(machines: [MachineEntity]) async throws {
        guard !machines.isEmpty else { return }
        try await SpotlightIndexBridge.index(machines, priority: 0)
    }

    func index(workspaces: [WorkspaceEntity]) async throws {
        guard !workspaces.isEmpty else { return }
        try await SpotlightIndexBridge.index(workspaces, priority: 0)
    }

    func index(runs: [RunEntity]) async throws {
        guard !runs.isEmpty else { return }
        try await SpotlightIndexBridge.index(runs, priority: 1)
    }

    func index(approvals: [ApprovalEntity]) async throws {
        guard !approvals.isEmpty else { return }
        try await SpotlightIndexBridge.index(approvals, priority: 2)
    }

    func removeApproval(id: String) async throws {
        lastApprovalIDs.remove(id)
        try await SpotlightIndexBridge.delete(identifiers: [id])
    }

    func removeRun(id: String) async throws {
        lastRunIDs.remove(id)
        try await SpotlightIndexBridge.delete(identifiers: [id])
    }

    func removeConversation(id: String) async throws {
        try await SpotlightIndexBridge.delete(identifiers: [id])
    }
}

@available(iOS 18.0, *)
private enum SpotlightIndexBridge {
    private static let indexName = IntentEntitySpotlightSupport.spotlightDomain

    static func index<T: IndexedEntity>(_ entities: [T], priority: Int) async throws {
        let index = CSSearchableIndex(name: indexName)
        try await index.indexAppEntities(entities, priority: priority)
    }

    static func delete(identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        let index = CSSearchableIndex(name: indexName)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
