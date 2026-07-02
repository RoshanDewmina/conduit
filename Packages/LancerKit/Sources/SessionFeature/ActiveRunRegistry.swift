#if os(iOS)
import Foundation

/// Tracks which dispatched run IDs are currently non-terminal, with a small
/// display title for each (e.g. "Relay · claude" or a conversation's title).
///
/// `RunOutputStore` (AppFeature) is the source of truth for a run's streamed
/// output/status, but `SessionFeature` cannot depend on `AppFeature` (features
/// don't depend on each other — `agent-contract.md` §1). AppIntents driven by
/// `CommandGateway` (`PauseRunIntent`/`StopRunIntent`, now in the `Lancer` app
/// target — see `Lancer/RunControlIntents.swift`) have no live view model in
/// scope, so they need *some* way to know "what is running and what should I
/// call it when I ask the user which one" without reaching into `AppFeature`.
/// This registry is the minimal mirror of that: `AppFeature`'s `RunOutputStore`
/// reports into it (with whatever title it already has on hand at dispatch
/// time) as runs start/finish; `SessionFeature`/`Lancer` only ever read it.
/// `title` is best-effort — an empty string is a valid, honest "no title yet".
@MainActor
public final class ActiveRunRegistry {
    public static let shared = ActiveRunRegistry()

    public struct ActiveRun: Identifiable, Sendable {
        public let runId: String
        public let title: String
        public var id: String { runId }

        public init(runId: String, title: String) {
            self.runId = runId
            self.title = title
        }
    }

    private var active: [String: String] = [:]

    /// Internal (not private) so tests can construct a fresh instance instead of
    /// mutating the shared singleton.
    public init() {}

    public func markActive(runId: String, title: String = "") {
        active[runId] = title
    }

    public func markTerminal(runId: String) {
        active[runId] = nil
    }

    public var activeRunIDs: [String] { Array(active.keys) }

    public var activeRuns: [ActiveRun] {
        active.map { ActiveRun(runId: $0.key, title: $0.value) }
    }
}
#endif
