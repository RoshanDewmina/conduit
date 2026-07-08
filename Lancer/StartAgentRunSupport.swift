import AppIntents
import Foundation
import IntentsKit
import LancerCore
import PersistenceKit
import SessionFeature
import os.log

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// Shared start-run validation and dispatch used by `StartAgentRunIntent`
/// (iOS 26 path and iOS 27 long-running path). Bridges `IntentsKit`'s entity
/// types to the pure, package-level `StartAgentRunPreparer` (SessionFeature).
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
    /// to finish before this treats the machine as offline — same shape as
    /// `RunControlSupport`'s bridge polling in `RunControlIntents.swift`.
    @MainActor
    private static func pollBridgeActive(relayMachineID: RelayMachineID, attempts: Int = 6) async -> Bool {
        for attempt in 0..<attempts {
            if ApprovalRelay.shared.relayBridges[relayMachineID]?.isActive == true {
                return true
            }
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
        guard let db = try? IntentsKitDependencies.database() else {
            return .dialog("Couldn't reach Lancer's database.")
        }
        let relayMachines = await IntentsKitDependencies.relayMachineSnapshots()
        let relayMachineIDString = machine.relayMachineID?.uuidString

        return try await StartAgentRunPreparer.prepare(
            relayMachineID: relayMachineIDString,
            relayMachines: relayMachines,
            agentDisplayName: agent.displayName,
            vendor: agent.relayVendor,
            prompt: prompt,
            workspaceID: workspace?.id,
            workspaceRepository: WorkspaceRepository(db),
            conversationRepository: ChatConversationRepository(db),
            bridgeActive: { relayMachineID in
                await pollBridgeActive(relayMachineID: relayMachineID)
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
            machineID: prepared.relayMachineID.uuidString,
            vendor: prepared.vendor,
            cwd: prepared.cwd,
            prompt: prepared.trimmedPrompt
        )

        onProgress?(.waitingForFirstState)

        switch result {
        case .started(let runId, _, let summary):
            await MainActor.run { ActiveRunRegistry.shared.markActive(runId: runId) }
            return (result, summary)
        case .blocked, .unavailable:
            return (result, nil)
        }
    }

    static func confirmationDialog(for prepared: PreparedRun) -> IntentDialog {
        IntentDialog(
            "Ready to start \(prepared.agentName) on \(prepared.displayName), in \(prepared.workspaceLabel), with: \"\(promptExcerpt(prepared.trimmedPrompt))\". Want me to go ahead?"
        )
    }

    static func promptExcerpt(_ prompt: String, maxLength: Int = 80) -> String {
        if prompt.count <= maxLength { return prompt }
        return String(prompt.prefix(maxLength)) + "…"
    }
}
