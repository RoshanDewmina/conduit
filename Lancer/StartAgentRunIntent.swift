import AppIntents
import Foundation
import SessionFeature

@available(iOS 17.0, *)
public struct StartAgentRunIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Agent Run"
    public static let description = IntentDescription(
        "Start a governed agent run on a paired machine. You'll confirm machine, agent, workspace, and prompt before anything runs."
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
        if #available(iOS 27.0, *) {
            return try await performLongRunning()
        }
        return try await performStandard()
    }

    private func performStandard() async throws -> some IntentResult & ProvidesDialog {
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
            let (result, _) = await StartAgentRunSupport.dispatch(prepared)
            switch result {
            case .started(_, _, let summary):
                return .result(dialog: IntentDialog(stringLiteral: summary))
            case .blocked(let message):
                return .result(dialog: IntentDialog(stringLiteral: message))
            case .unavailable(let message):
                return .result(dialog: IntentDialog(stringLiteral: message))
            }
        }
    }

    @available(iOS 27.0, *)
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
                    case .started(_, _, let summary):
                        return summary
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

@available(iOS 27.0, *)
extension StartAgentRunIntent: LongRunningIntent, CancellableIntent, ProgressReportingIntent {}
