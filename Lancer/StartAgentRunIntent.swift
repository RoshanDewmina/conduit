import AppIntents
import Foundation
import IntentsKit
import SessionFeature

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// "Start Claude Code on my Mac Studio in Lancer" — the one intent that
/// dispatches a NEW agent run by voice, not just controls/queries an existing
/// one. Deliberately NOT an approval: it kicks off work that then flows
/// through the same governed-approval loop every other run does — the agent
/// still can't touch anything without a human tapping Approve. Always
/// confirms machine/agent/workspace/prompt before dispatching
/// (`requestConfirmation`), and only ever targets a relay-paired machine
/// (`StartAgentRunPreparer` rejects SSH hosts with an explicit dialog — see
/// its header comment for why).
///
/// Uses `LongRunningIntent` / `CancellableIntent` / `ProgressReportingIntent`
/// (iOS 27+) so Siri can show "your agent is working on it" background
/// execution. The app deployment target is iOS 27.0, so this path is
/// unconditional.
@available(iOS 17.0, *)
public struct StartAgentRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Agent Run"
    public static let description = IntentDescription(
        "Start a governed agent run on a relay-paired machine. You'll confirm machine, agent, workspace, and prompt before anything runs."
    )
    public static let openAppWhenRun: Bool = true

    @Parameter(
        title: "Machine",
        requestValueDialog: IntentDialog("Which machine should run this?")
    )
    public var machine: MachineEntity

    @Parameter(
        title: "Agent",
        requestValueDialog: IntentDialog("Which agent — Claude Code, Codex, OpenCode, or Kimi?")
    )
    public var agent: AgentVendorAppEnum

    @Parameter(
        title: "Prompt",
        requestValueDialog: IntentDialog("What should the agent work on?")
    )
    public var prompt: String

    @Parameter(
        title: "Workspace",
        requestValueDialog: IntentDialog("Which workspace — or say \"most recent\" to use the last one you worked in?")
    )
    public var workspace: WorkspaceEntity?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await performLongRunning()
    }

    private func performLongRunning() async throws -> some IntentResult & ProvidesDialog {
        switch try await StartAgentRunSupport.prepare(
            machine: machine,
            agent: agent,
            prompt: prompt,
            workspace: workspace
        ) {
        case .dialog(let message):
            return .result(dialog: IntentDialog(stringLiteral: message))
        case .ready(let prepared):
            try await requestConfirmation(
                actionName: .start,
                dialog: StartAgentRunSupport.confirmationDialog(for: prepared)
            )

            let outcome = try await performBackgroundTask(
                operation: {
                    try Task.checkCancellation()
                    progress.totalUnitCount = 5
                    progress.localizedDescription = "Starting agent run"

                    func report(_ stage: StartAgentRunSupport.Stage, completed: Int64) {
                        progress.completedUnitCount = completed
                        progress.localizedAdditionalDescription = stage.rawValue
                    }

                    report(.resolvingMachine, completed: 1)

                    let (result, summary) = await StartAgentRunSupport.dispatch(prepared) { stage in
                        switch stage {
                        case .resolvingMachine: report(stage, completed: 1)
                        case .checkingConnection: report(stage, completed: 2)
                        case .creatingRun: report(stage, completed: 3)
                        case .dispatchingAgent: report(stage, completed: 4)
                        case .waitingForFirstState: report(stage, completed: 5)
                        }
                    }

                    switch result {
                    case .started(_, _, let dispatchSummary):
                        return summary ?? dispatchSummary
                    case .blocked(let message), .unavailable(let message):
                        return message
                    }
                },
                onCancel: { _ in
                    Task { await RunDispatchService.shared.cancelInFlight() }
                }
            )

            return .result(
                dialog: IntentDialog(
                    stringLiteral: "Agent run started. \(outcome) Open Lancer to follow progress — the agent hasn't finished your task yet."
                )
            )
        }
    }
}

extension StartAgentRunIntent: LongRunningIntent, CancellableIntent, ProgressReportingIntent {}
