#if os(iOS)
import Foundation

/// Tracks which dispatched run IDs are currently non-terminal.
///
/// `RunOutputStore` (AppFeature) is the source of truth for a run's streamed
/// output/status, but `SessionFeature` cannot depend on `AppFeature` (features
/// don't depend on each other — `agent-contract.md` §1). AppIntents driven by
/// `CommandGateway` (`PauseRunIntent`/`StopRunIntent`) live in `SessionFeature`
/// and have no live view model in scope, so they need *some* way to know
/// "is anything running" without reaching into `AppFeature`. This registry is
/// the minimal mirror of that one signal: `AppFeature`'s `RunOutputStore`
/// reports into it as runs start/finish; `SessionFeature` only ever reads it.
@MainActor
public final class ActiveRunRegistry {
    public static let shared = ActiveRunRegistry()

    private var activeIDs: Set<String> = []

    /// Internal (not private) so tests can construct a fresh instance instead of
    /// mutating the shared singleton.
    public init() {}

    public func markActive(runId: String) {
        activeIDs.insert(runId)
    }

    public func markTerminal(runId: String) {
        activeIDs.remove(runId)
    }

    public var activeRunIDs: [String] { Array(activeIDs) }
}
#endif
