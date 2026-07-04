import AppIntents
import Foundation
import LancerCore
import NotificationsKit
import PersistenceKit
import SessionFeature
import os.log

/// Shared start-run validation and dispatch used by `StartAgentRunIntent`
/// (iOS 26 path and iOS 27 long-running path).
@available(iOS 17.0, *)
enum StartAgentRunSupport {
    private static let logger = Logger(subsystem: "dev.lancer.mobile", category: "StartAgentRunSupport")

    enum Stage: String, Sendable {
        case resolvingMachine
        case checkingConnection
        case creatingRun
        case dispatchingAgent
        case waitingForFirstState
    }

    typealias PreparedRun = StartAgentRunPreparer.PreparedRun
    typealias PrepareResult = StartAgentRunPreparer.PrepareResult

    /// Polls `ApprovalRelay.shared.relayBridges` for up to ~3 seconds so a
    /// cold-launch reconnect (triggered by Siri's `openAppWhenRun`) has time
    /// to finish before this treats the machine as offline.
    private static func pollBridgeActive(relayID: RelayMachineID, attempts: Int = 6) async -> Bool {
        for attempt in 0..<attempts {
            let active = await MainActor.run {
                ApprovalRelay.shared.relayBridges[relayID]?.isActive == true
            }
            if active { return true }
            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return false
    }

    static func prepare(
        machine: MachineEntity,
        agent: AgentVendorAppEnum,
        prompt: String,
        workspace: WorkspaceEntity?,
        onProgress: ((Stage) -> Void)? = nil
    ) async throws -> PrepareResult {
        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        let agentName: String = {
            switch agent {
            case .claudeCode: return "Claude Code"
            case .codex: return "Codex"
            case .opencode: return "OpenCode"
            case .kimi: return "Kimi"
            }
        }()

        return try await StartAgentRunPreparer.prepare(
            catalog: catalog,
            relayMachines: relay,
            machineID: machine.id,
            vendor: agent.relayVendor,
            agentDisplayName: agentName,
            prompt: prompt,
            workspaceID: workspace?.id,
            bridgeActive: { relayID in
                await pollBridgeActive(relayID: RelayMachineID(relayID))
            },
            onProgress: { stage in
                switch stage {
                case .resolvingMachine: onProgress?(.resolvingMachine)
                case .checkingConnection: onProgress?(.checkingConnection)
                }
            }
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
            "Ready to start \(prepared.agentName) on \(prepared.displayName), in \(prepared.workspaceLabel), with: \"\(SiriIntentSupport.promptExcerpt(prepared.trimmedPrompt))\". Want me to go ahead?"
        )
    }
}
