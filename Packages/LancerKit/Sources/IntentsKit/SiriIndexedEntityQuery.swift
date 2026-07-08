#if canImport(AppIntents) && canImport(CoreSpotlight)
import AppIntents
import CoreSpotlight
import Foundation

// IndexedEntityQuery conformances (I3, iOS 27+ / macOS 27+):
// `IndexedEntityQuery` is the iOS 27 evolution of `IndexedEntity` — it lets the
// system call back into our query types directly when it wants to rebuild the
// Spotlight/Apple Intelligence index for a specific index domain, rather than
// the app having to schedule its own refresh. The system provides a
// `CSSearchableIndexDescription` (carries the index's file-protection class) so
// we build a `CSSearchableIndex` with matching protection and call
// `indexAppEntities` exactly once per callback.
//
// Availability: `IndexedEntityQuery` is @available(macOS 27.0, iOS 27.0,
// visionOS 27.0) — confirmed against the installed iOS 27 SDK swiftinterface.
// All conformances below are explicitly availability-gated to match.
// `IndexedEntity` (the base) is iOS 18+ and already conformed in
// `SiriEntityIndexing.swift` — that earlier conformance is not repeated here.
//
// Secret-screening: every entity list passes through
// `SiriSpotlightSupport.safeEntities` before indexing — same gate as
// `SiriEntityIndexer` — so a prompt/command that embeds a credential never
// reaches Spotlight.
//
// ApprovalEntity is intentionally excluded here: pending approvals are
// ephemeral (they resolve within seconds to minutes) and indexing them via the
// system callback would race with their own deletion. The lighter-weight
// `SiriEntityIndexer.refreshPendingApprovals()` (called on every
// `SiriSurfaceBootstrap.refresh()`) is the right cadence for those.

// Guarded by `#if swift(>=6.4)`, not just `@available(iOS 27.0, *)`: these
// protocols/types don't exist in the iOS 26 SDK at all, so a toolchain/SDK that
// predates iOS 27 can't type-check this code regardless of runtime availability.
#if swift(>=6.4)

// MARK: - ConversationEntityQuery

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension ConversationEntityQuery: IndexedEntityQuery {
    public func reindexAllEntities(
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let all = try await suggestedEntities()
        let safe = SiriSpotlightSupport.safeEntities(all, indexableText: \.title)
        guard !safe.isEmpty else { return }
        try await spotlightIndex(for: indexDescription).indexAppEntities(safe)
    }

    public func reindexEntities(
        for identifiers: [ConversationEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        guard !identifiers.isEmpty else { return }
        let fetched = try await entities(for: identifiers)
        let safe = SiriSpotlightSupport.safeEntities(fetched, indexableText: \.title)
        guard !safe.isEmpty else { return }
        try await spotlightIndex(for: indexDescription).indexAppEntities(safe)
    }
}

// MARK: - RunEntityQuery

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension RunEntityQuery: IndexedEntityQuery {
    public func reindexAllEntities(
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let all = try await suggestedEntities()
        let safe = SiriSpotlightSupport.safeEntities(all, indexableText: \.title)
        guard !safe.isEmpty else { return }
        try await spotlightIndex(for: indexDescription).indexAppEntities(safe)
    }

    public func reindexEntities(
        for identifiers: [RunEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        guard !identifiers.isEmpty else { return }
        let fetched = try await entities(for: identifiers)
        let safe = SiriSpotlightSupport.safeEntities(fetched, indexableText: \.title)
        guard !safe.isEmpty else { return }
        try await spotlightIndex(for: indexDescription).indexAppEntities(safe)
    }
}

// MARK: - MachineEntityQuery

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension MachineEntityQuery: IndexedEntityQuery {
    public func reindexAllEntities(
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let all = try await suggestedEntities()
        let safe = SiriSpotlightSupport.safeEntities(all, indexableText: \.name)
        guard !safe.isEmpty else { return }
        try await spotlightIndex(for: indexDescription).indexAppEntities(safe)
    }

    public func reindexEntities(
        for identifiers: [MachineEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        guard !identifiers.isEmpty else { return }
        let fetched = try await entities(for: identifiers)
        let safe = SiriSpotlightSupport.safeEntities(fetched, indexableText: \.name)
        guard !safe.isEmpty else { return }
        try await spotlightIndex(for: indexDescription).indexAppEntities(safe)
    }
}

// MARK: - WorkspaceEntityQuery

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension WorkspaceEntityQuery: IndexedEntityQuery {
    public func reindexAllEntities(
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let all = try await suggestedEntities()
        let safe = SiriSpotlightSupport.safeEntities(all, indexableText: \.name)
        guard !safe.isEmpty else { return }
        try await spotlightIndex(for: indexDescription).indexAppEntities(safe)
    }

    public func reindexEntities(
        for identifiers: [WorkspaceEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        guard !identifiers.isEmpty else { return }
        let fetched = try await entities(for: identifiers)
        let safe = SiriSpotlightSupport.safeEntities(fetched, indexableText: \.name)
        guard !safe.isEmpty else { return }
        try await spotlightIndex(for: indexDescription).indexAppEntities(safe)
    }
}

// MARK: - Index factory

/// Creates a `CSSearchableIndex` whose file-protection class matches the one
/// the system requested via `indexDescription`. The protection class controls
/// which file-vault tier the Spotlight data is stored under — e.g.
/// `.completeUntilFirstUserAuthentication` for a lock-screen search surface.
/// Falls back to our named domain index when the description carries no class.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
private func spotlightIndex(
    for description: CSSearchableIndexDescription
) -> CSSearchableIndex {
    CSSearchableIndex(
        name: SiriSpotlightSupport.spotlightDomain,
        protectionClass: description.protectionClass
    )
}

#endif // swift(>=6.4)

#endif
