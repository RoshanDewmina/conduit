import AppIntents
import Foundation
import IntentsKit
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// One-time bridge from `IntentsKit`'s synchronous dependency-injection seam
/// (`IntentsKitDependencies.activeRunIDs`, a plain `@Sendable () -> [String]`
/// closure — entity queries call it from contexts that aren't statically
/// pinned to `MainActor`) to `ActiveRunRegistry` (`@MainActor`, SessionFeature).
/// Hops onto the main thread only when not already there, so it's safe to call
/// from either side without redesigning that seam's shape or risking an
/// `assumeIsolated` trap off-main. Touched from the intents' `init()`s because
/// the system instantiates the intent BEFORE resolving its `RunEntity`
/// parameter — wiring only inside `perform()` would leave a spoken run name
/// resolving against an empty registry.
@available(iOS 17.0, *)
let wireIntentsKitActiveRuns: Void = {
    IntentsKitDependencies.activeRunIDs = {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { ActiveRunRegistry.shared.activeRunIDs }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { ActiveRunRegistry.shared.activeRunIDs }
        }
    }
}()

/// Shared "which run does a bare phrase act on" resolution for `PauseRunIntent`
/// and `StopRunIntent`: an explicitly-named `run` wins; otherwise the sole
/// active run acts directly, zero active runs (further split on whether any
/// machine is even paired) returns a dialog, and more than one active run
/// drives the framework's own disambiguation UI/voice prompt via
/// `IntentParameter.requestDisambiguation` — never a silent guess.
@available(iOS 17.0, *)
private enum RunControlResolution {
    case run(RunEntity)
    case dialog(IntentDialog)
}

@available(iOS 17.0, *)
@MainActor
private enum RunControlSupport {
    static func resolve(
        provided: RunEntity?,
        parameter: IntentParameter<RunEntity?>
    ) async throws -> RunControlResolution {
        if let provided {
            return .run(provided)
        }
        _ = wireIntentsKitActiveRuns
        switch try await RunEntityQuery().resolveActiveRun() {
        case .sole(let entity):
            return .run(entity)
        case .none:
            let machines = (try? await MachineEntityQuery().suggestedEntities()) ?? []
            if machines.isEmpty {
                return .dialog("No machines are paired with Lancer yet. Open the app to connect one.")
            }
            return .dialog("No agent runs are currently active.")
        case .ambiguous(let candidates):
            let chosen = try await parameter.requestDisambiguation(
                among: candidates,
                dialog: "Which run do you mean?"
            )
            return .run(chosen)
        }
    }
}

@available(iOS 17.0, *)
public struct PauseRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pause Agent Run"
    public static let description = IntentDescription("Pause an agent run — the active one if only one is running, or the run you name.")

    @Parameter(title: "Run")
    public var run: RunEntity?

    public init() {
        _ = wireIntentsKitActiveRuns
    }

    public init(run: RunEntity? = nil) {
        _ = wireIntentsKitActiveRuns
        self.run = run
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch try await RunControlSupport.resolve(provided: run, parameter: $run) {
        case .dialog(let dialog):
            return .result(dialog: dialog)
        case .run(let resolved):
            switch await CommandGateway.shared.execute(.pause(runId: resolved.id)) {
            case .ok: return .result(dialog: "Paused '\(resolved.title)'.")
            case .transportUnavailable: return .result(dialog: "Lancer isn't connected to a machine right now.")
            default: return .result(dialog: "Couldn't pause the run.")
            }
        }
    }
}

@available(iOS 17.0, *)
public struct StopRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Agent Run"
    public static let description = IntentDescription("Stop an agent run — the active one if only one is running, or the run you name.")

    @Parameter(title: "Run")
    public var run: RunEntity?

    public init() {
        _ = wireIntentsKitActiveRuns
    }

    public init(run: RunEntity? = nil) {
        _ = wireIntentsKitActiveRuns
        self.run = run
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch try await RunControlSupport.resolve(provided: run, parameter: $run) {
        case .dialog(let dialog):
            return .result(dialog: dialog)
        case .run(let resolved):
            // Stopping is destructive (can't be resumed) — confirm before acting,
            // unlike pause.
            try await requestConfirmation(dialog: "Stop '\(resolved.title)'? This can't be undone.")
            switch await CommandGateway.shared.execute(.cancel(runId: resolved.id)) {
            case .ok: return .result(dialog: "Stopped '\(resolved.title)'.")
            case .transportUnavailable: return .result(dialog: "Lancer isn't connected to a machine right now.")
            default: return .result(dialog: "Couldn't stop the run.")
            }
        }
    }
}
