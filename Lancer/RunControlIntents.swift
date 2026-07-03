import AppIntents
import Foundation
import PersistenceKit
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

@available(iOS 17.0, *)
public struct PauseRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pause Agent Run"
    public static let description = IntentDescription("Pause an active agent run.")

    @Parameter(title: "Run")
    public var run: RunEntity?

    public init() {}
    public init(run: RunEntity) { self.run = run }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()

        let resolved: IntentRunRecord?
        if let run {
            resolved = try await catalog.run(id: run.id, activeRunIDs: active)
            guard let resolved else {
                return .result(dialog: "That run isn't active anymore.")
            }
        } else if active.count == 1, let only = try await catalog.activeRuns(activeRunIDs: active).first {
            resolved = only
        } else if active.isEmpty {
            return .result(dialog: "No agent runs are currently active.")
        } else {
            return .result(dialog: "More than one agent is running — pick which run to pause.")
        }

        guard let resolved else {
            return .result(dialog: "Couldn't find that run.")
        }

        switch await CommandGateway.shared.execute(.pause(runId: resolved.id)) {
        case .ok:
            return .result(dialog: SiriIntentDialogs.pauseSuccess(resolved))
        case .transportUnavailable:
            return .result(dialog: SiriIntentDialogs.transportUnavailable(machine: resolved.hostName))
        default:
            return .result(dialog: "Couldn't pause \(SiriIntentSupport.runDialogSubject(resolved)).")
        }
    }
}

@available(iOS 17.0, *)
public struct StopRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Agent Run"
    public static let description = IntentDescription("Stop an active agent run.")

    @Parameter(title: "Run")
    public var run: RunEntity?

    public init() {}
    public init(run: RunEntity) { self.run = run }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let catalog = try SiriIntentSupport.openCatalog()
        let active = SiriIntentSupport.activeRunIDs()

        let resolved: IntentRunRecord?
        if let run {
            resolved = try await catalog.run(id: run.id, activeRunIDs: active)
            guard let resolved else {
                return .result(dialog: "That run isn't active anymore.")
            }
        } else if active.count == 1, let only = try await catalog.activeRuns(activeRunIDs: active).first {
            resolved = only
        } else if active.isEmpty {
            return .result(dialog: "No agent runs are currently active.")
        } else {
            return .result(dialog: "More than one agent is running — pick which run to stop.")
        }

        guard let resolved else {
            return .result(dialog: "Couldn't find that run.")
        }

        switch await CommandGateway.shared.execute(.cancel(runId: resolved.id)) {
        case .ok:
            return .result(dialog: SiriIntentDialogs.stopSuccess(resolved))
        case .transportUnavailable:
            return .result(dialog: SiriIntentDialogs.transportUnavailable(machine: resolved.hostName))
        default:
            return .result(dialog: "Couldn't stop \(SiriIntentSupport.runDialogSubject(resolved)).")
        }
    }
}
