import AppIntents
import Foundation
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// Wraps an active run ID from `ActiveRunRegistry`. `EntityStringQuery`, not
/// `IndexedEntity`: active runs are as ephemeral as pending approvals, so
/// there's nothing worth indexing — resolve fresh against the registry's
/// current snapshot every time.
///
/// `title` is whatever `ActiveRunRegistry.ActiveRun.title` had at dispatch
/// time (e.g. "Relay · claude", a conversation's title) — real metadata
/// `AppFeature` already has on hand, not invented. It can be empty for a run
/// registered before this metadata existed on a given code path; the display
/// representation falls back to a short ID prefix in that case rather than
/// showing nothing.
@available(iOS 17.0, *)
public struct RunEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Agent Run")
    public static let defaultQuery = RunEntityQuery()

    public let id: String
    let title: String

    public var displayRepresentation: DisplayRepresentation {
        if title.isEmpty {
            return DisplayRepresentation(title: "Run \(id.prefix(8))")
        }
        return DisplayRepresentation(title: "\(title)")
    }

    init(activeRun: ActiveRunRegistry.ActiveRun) {
        self.id = activeRun.runId
        self.title = activeRun.title
    }
}

@available(iOS 17.0, *)
public struct RunEntityQuery: EntityStringQuery {
    public init() {}

    // `ActiveRunRegistry` is `@MainActor`-isolated (SessionFeature convention —
    // see `RunControlIntents.swift`'s `resolveSoleActiveRun()`); `EntityQuery`'s
    // requirements are plain nonisolated `async`, so hop explicitly via
    // `MainActor.run` rather than marking these methods `@MainActor` (which
    // cannot satisfy a nonisolated protocol requirement under strict concurrency).
    public func entities(for identifiers: [String]) async throws -> [RunEntity] {
        await MainActor.run {
            let active = ActiveRunRegistry.shared.activeRuns
            return identifiers.compactMap { id in
                active.first(where: { $0.runId == id }).map(RunEntity.init)
            }
        }
    }

    public func entities(matching string: String) async throws -> [RunEntity] {
        try await suggestedEntities().filter {
            $0.title.localizedCaseInsensitiveContains(string)
        }
    }

    public func suggestedEntities() async throws -> [RunEntity] {
        await MainActor.run { ActiveRunRegistry.shared.activeRuns.map(RunEntity.init) }
    }
}
