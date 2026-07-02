import AppIntents
import Foundation
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// Resolves which run a bare "pause/stop the session" phrase applies to, without
/// full `AppEntity`/`EntityQuery` disambiguation. `ActiveRunRegistry` only tracks
/// IDs (no per-machine/title metadata is visible to SessionFeature — that lives
/// in AppFeature's `RunOutputStore`), so a genuine "which one?" picker isn't
/// buildable here without inverting the Feature dependency graph. Scoped per the
/// plan's own guidance: exactly one active run acts on it directly; zero or more
/// than one returns a clear dialog instead of guessing. Full disambiguation is a
/// fast follow if multi-run Siri control turns out to matter in practice.
private enum SoleActiveRunResolution {
    case success(String)
    case failure(IntentDialog)
}

@available(iOS 17.0, *)
@MainActor
private func resolveSoleActiveRun() -> SoleActiveRunResolution {
    let active = ActiveRunRegistry.shared.activeRunIDs
    if active.isEmpty {
        return .failure(IntentDialog("No agent runs are currently active."))
    }
    if active.count > 1 {
        return .failure(IntentDialog("More than one agent is running — open Lancer to choose which one."))
    }
    return .success(active[0])
}

@available(iOS 17.0, *)
public struct PauseRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pause Agent Run"
    public static let description = IntentDescription("Pause the active agent run.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch resolveSoleActiveRun() {
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

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch resolveSoleActiveRun() {
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
