import AppIntents
import Foundation
import LancerCore
import NotificationsKit
import PersistenceKit
import SessionFeature

/// Shared start-run validation and dispatch used by `StartAgentRunIntent`
/// (iOS 26 path and iOS 27 long-running path).
@available(iOS 17.0, *)
enum StartAgentRunSupport {
    enum Stage: String, Sendable {
        case resolvingMachine
        case checkingConnection
        case creatingRun
        case dispatchingAgent
        case waitingForFirstState
    }

    struct PreparedRun: Sendable {
        let relayUUID: String
        let machineRecordID: String
        let displayName: String
        let cwd: String
        let workspaceLabel: String
        let agentName: String
        let vendor: String
        let trimmedPrompt: String
    }

    enum PrepareResult: Sendable {
        case ready(PreparedRun)
        case dialog(String)
    }

    static func prepare(
        machine: MachineEntity,
        agent: AgentVendorAppEnum,
        prompt: String,
        workspace: WorkspaceEntity?,
        onProgress: ((Stage) -> Void)? = nil
    ) async throws -> PrepareResult {
        onProgress?(.resolvingMachine)

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return .dialog("What should the agent work on?")
        }

        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        let machines = try await catalog.machines(relayMachines: relay)
        guard !machines.isEmpty else {
            return .dialog("No machines are paired yet. Open Lancer to connect one.")
        }

        guard let record = try await catalog.machine(id: machine.id, relayMachines: relay) else {
            return .dialog("That machine isn't paired anymore.")
        }

        guard record.kind == .relayMachine else {
            return .dialog("Starting runs by voice needs a relay-paired machine. Open Lancer to connect over relay.")
        }

        guard let relayUUID = SiriIntentSupport.relayMachineUUID(from: record.id),
              let uuid = UUID(uuidString: relayUUID)
        else {
            return .dialog("Couldn't resolve that machine.")
        }

        onProgress?(.checkingConnection)

        let relayID = RelayMachineID(uuid)
        let bridgeActive = await MainActor.run {
            ApprovalRelay.shared.relayBridges[relayID]?.isActive == true
        }
        let online = SiriIntentSupport.machineConnectivityLabel(record) == "online" || bridgeActive
        guard online else {
            let message = record.displayName.isEmpty
                ? "Lancer isn't connected to a machine right now. Open Lancer to reconnect."
                : "\(record.displayName) isn't connected right now. Open Lancer to reconnect."
            return .dialog(message)
        }

        let cwd: String
        if let workspace {
            guard let ws = try await catalog.workspaces(machineID: relayUUID).first(where: { $0.id == workspace.id }) else {
                return .dialog("That workspace isn't available on this machine anymore.")
            }
            cwd = ws.path
        } else {
            let workspaces = try await catalog.workspaces(machineID: relayUUID)
            guard let mru = workspaces.first else {
                return .dialog("No workspace is set up on \(record.displayName). Open Lancer to pick a project folder first.")
            }
            cwd = mru.path
        }

        let workspaceLabel = URL(fileURLWithPath: cwd).lastPathComponent
        let agentName: String = {
            switch agent {
            case .claudeCode: return "Claude Code"
            case .codex: return "Codex"
            case .opencode: return "OpenCode"
            case .kimi: return "Kimi"
            }
        }()

        return .ready(
            PreparedRun(
                relayUUID: relayUUID,
                machineRecordID: record.id,
                displayName: record.displayName,
                cwd: cwd,
                workspaceLabel: workspaceLabel,
                agentName: agentName,
                vendor: agent.relayVendor,
                trimmedPrompt: trimmedPrompt
            )
        )
    }

    static func dispatch(
        _ prepared: PreparedRun,
        onProgress: ((Stage) -> Void)? = nil
    ) async -> (RunDispatchResult, String?) {
        onProgress?(.creatingRun)
        onProgress?(.dispatchingAgent)

        let result = await RunDispatchService.shared.startRun(
            machineID: prepared.relayUUID,
            vendor: prepared.vendor,
            cwd: prepared.cwd,
            prompt: prepared.trimmedPrompt
        )

        onProgress?(.waitingForFirstState)

        switch result {
        case .started(let runId, let conversationId, let summary):
            if let conversationId {
                SiriIntentSupport.postNavigation(.openConversation, conversationId: conversationId)
            } else {
                SiriIntentSupport.postNavigation(.openMachine, machineId: prepared.machineRecordID)
            }
            await MainActor.run { ActiveRunRegistry.shared.markActive(runId: runId) }
            NotificationCenter.default.post(name: .lancerSiriSurfaceRefresh, object: nil)
            return (result, summary)
        case .blocked, .unavailable:
            return (result, nil)
        }
    }

    static func confirmationDialog(for prepared: PreparedRun) -> IntentDialog {
        IntentDialog(
            "Start \(prepared.agentName) on \(prepared.displayName) in \(prepared.workspaceLabel)? Prompt: \"\(SiriIntentSupport.promptExcerpt(prepared.trimmedPrompt))\". Nothing runs until you confirm."
        )
    }
}
