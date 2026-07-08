#if canImport(AppIntents) && canImport(CoreSpotlight)
import AppIntents
import CoreSpotlight
import Foundation

// CoreSpotlight indexing (I2, ported from the parked
// `cursor/siri-phase2-fixes-9257` branch's `Lancer/SiriEntityIndexing.swift`,
// rewired onto the current `IntentsKit` entity types (D1-D3, I1) instead of
// that branch's now-superseded `IntentEntityCatalog`). Not available on
// watchOS (`CoreSpotlight` doesn't exist there), hence the `canImport` guard
// alongside the existing `canImport(AppIntents)` one this file's siblings use.

@available(iOS 18.0, *)
extension ConversationEntity: IndexedEntity {}
@available(iOS 18.0, *)
extension MachineEntity: IndexedEntity {}
@available(iOS 18.0, *)
extension WorkspaceEntity: IndexedEntity {}
@available(iOS 18.0, *)
extension RunEntity: IndexedEntity {}
@available(iOS 18.0, *)
extension ApprovalEntity: IndexedEntity {}

/// Indexes `IntentsKit`'s existing entity types into the app's Spotlight
/// index so Siri/Spotlight search (and, on iOS 27+, Apple Intelligence) can
/// surface conversations, machines, workspaces, active runs, and pending
/// approvals without a matching voice phrase — plugs into the entity/query
/// model D1-D3/I1 already established rather than inventing a parallel one.
///
/// Every entity's indexable text is run through
/// `SiriSpotlightSupport.containsForbiddenIndexMaterial` before indexing
/// (see that type's doc comment) — indexing is otherwise best-effort and
/// never throws out of `refreshAll()`, matching the old branch's stance that
/// a Spotlight refresh failure must not break app launch.
@available(iOS 18.0, *)
@MainActor
public final class SiriEntityIndexer {
    public static let shared = SiriEntityIndexer()

    private var lastRunIDs: Set<String> = []
    private var lastApprovalIDs: Set<String> = []

    private init() {}

    /// Full refresh — call at launch and whenever the Siri surface should
    /// reflect current state (mirrors `SiriRelevanceCoordinator.refresh`'s
    /// call cadence via `SiriSurfaceBootstrap`, the app target's shared
    /// launch/refresh hook for both relevance donations and this indexer).
    public func refreshAll() async {
        do {
            try await refreshConversations()
            try await refreshMachines()
            try await refreshWorkspaces()
            try await refreshActiveRuns()
            try await refreshPendingApprovals()
        } catch {
            // Indexing is best-effort; failures must not break app launch/refresh.
        }
    }

    public func refreshConversations() async throws {
        let entities = SiriSpotlightSupport.safeEntities(
            try await ConversationEntityQuery().suggestedEntities(),
            indexableText: \.title
        )
        try await index(entities)
    }

    public func refreshMachines() async throws {
        let entities = SiriSpotlightSupport.safeEntities(
            try await MachineEntityQuery().suggestedEntities(),
            indexableText: \.name
        )
        try await index(entities)
    }

    public func refreshWorkspaces() async throws {
        let entities = SiriSpotlightSupport.safeEntities(
            try await WorkspaceEntityQuery().suggestedEntities(),
            indexableText: \.name
        )
        try await index(entities)
    }

    public func refreshActiveRuns() async throws {
        let entities = SiriSpotlightSupport.safeEntities(
            try await RunEntityQuery().suggestedEntities(),
            indexableText: \.title
        )
        let currentIDs = Set(entities.map(\.id))
        try await removeStale(currentIDs: currentIDs, previousIDs: lastRunIDs, type: RunEntity.self)
        lastRunIDs = currentIDs
        try await index(entities)
    }

    public func refreshPendingApprovals() async throws {
        let entities = SiriSpotlightSupport.safeEntities(
            try await ApprovalEntityQuery().suggestedEntities(),
            indexableText: \.title
        )
        let currentIDs = Set(entities.map(\.id))
        try await removeStale(currentIDs: currentIDs, previousIDs: lastApprovalIDs, type: ApprovalEntity.self)
        lastApprovalIDs = currentIDs
        try await index(entities)
    }

    // MARK: - Index / reconcile

    private func index<T: IndexedEntity>(_ entities: [T]) async throws {
        guard !entities.isEmpty else { return }
        let index = CSSearchableIndex(name: SiriSpotlightSupport.spotlightDomain)
        try await index.indexAppEntities(entities)
    }

    /// Active runs and pending approvals churn fast (a run finishes, an
    /// approval gets decided) — without removing entries no longer present in
    /// the latest snapshot, resolved/finished items would stay searchable in
    /// Spotlight indefinitely. Conversations/machines/workspaces don't need
    /// this: they're not deleted by normal use, only ever added to or renamed.
    /// Takes plain (non-`inout`) sets — the caller reassigns its stored
    /// property after this returns — since an actor-isolated property can't
    /// be passed `inout` across the `await` inside this call.
    private func removeStale<Entity: IndexedEntity>(
        currentIDs: Set<String>,
        previousIDs: Set<String>,
        type: Entity.Type
    ) async throws where Entity.ID == String {
        let stale = previousIDs.subtracting(currentIDs)
        guard !stale.isEmpty else { return }
        let index = CSSearchableIndex(name: SiriSpotlightSupport.spotlightDomain)
        try await index.deleteAppEntities(identifiedBy: Array(stale), ofType: type)
    }
}

#endif
