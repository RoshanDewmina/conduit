import AppIntents
import Foundation
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// Resolves which run a "pause/stop the session" phrase applies to. When the
/// user names a run (or Siri already disambiguated via `RunEntityQuery`'s
/// `suggestedEntities()` — the picker it shows when more than one run is
/// active), `run` arrives non-nil and is used directly. Otherwise this falls
/// back to the original single-run fast path: exactly one active run acts on
/// it directly; zero or more than one (with no entity resolved) returns a
/// clear dialog instead of guessing — the same conservative behavior as
/// before `RunEntity` existed, now only a fallback rather than the whole story.
private enum RunResolution {
    case success(String)
    case failure(IntentDialog)
}

@available(iOS 17.0, *)
@MainActor
private func resolveTargetRun(_ run: RunEntity?) -> RunResolution {
    if let run {
        return .success(run.id)
    }
    let active = ActiveRunRegistry.shared.activeRunIDs
    if active.isEmpty {
        return .failure(IntentDialog("No agent runs are currently active."))
    }
    if active.count > 1 {
        return .failure(IntentDialog("More than one agent is running — say which one, or open Lancer to choose."))
    }
    return .success(active[0])
}

@available(iOS 17.0, *)
public struct PauseRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pause Agent Run"
    public static let description = IntentDescription("Pause the active agent run.")

    @Parameter(title: "Run")
    public var run: RunEntity?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch resolveTargetRun(run) {
        case .failure(let dialog):
            return .result(dialog: dialog)
        case .success(let runId):
            switch await CommandGateway.shared.execute(.pause(runId: runId)) {
            case .ok: return .result(dialog: "Paused.")
            case .transportUnavailable: return .result(dialog: "Lancer isn't connected to a machine right now.")
            default: return .result(dialog: "Couldn't pause the run.")
            }
        }
    }
}

@available(iOS 17.0, *)
public struct StopRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Agent Run"
    public static let description = IntentDescription("Stop the active agent run.")

    @Parameter(title: "Run")
    public var run: RunEntity?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch resolveTargetRun(run) {
        case .failure(let dialog):
            return .result(dialog: dialog)
        case .success(let runId):
            switch await CommandGateway.shared.execute(.cancel(runId: runId)) {
            case .ok: return .result(dialog: "Stopped.")
            case .transportUnavailable: return .result(dialog: "Lancer isn't connected to a machine right now.")
            default: return .result(dialog: "Couldn't stop the run.")
            }
        }
    }
}
