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

    /// The working directory of this host's most recently active
    /// conversation — Home's actual definition of "has a workspace" for
    /// display purposes, independent of whether an explicit `Workspace` row
    /// exists. See the call site comment for the bug this closes.
    private static func mostRecentConversationCwd(hostName: String, catalog: IntentEntityCatalog) async throws -> String? {
        try await catalog.conversations()
            .first { $0.hostName == hostName }?
            .workspacePath
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
            return .dialog("Sure — what should the agent work on?")
        }

        let catalog = try SiriIntentSupport.openCatalog()
        let relay = await SiriIntentSupport.relayMachineSnapshots()
        let machines = try await catalog.machines(relayMachines: relay)
        guard !machines.isEmpty else {
            return .dialog("You don't have any machines paired yet — open Lancer and connect one first.")
        }

        guard let record = try await catalog.machine(id: machine.id, relayMachines: relay) else {
            return .dialog("That machine isn't paired anymore — check Lancer to reconnect it.")
        }

        guard record.kind == .relayMachine else {
            return .dialog("Starting a run by voice needs a relay-paired machine — open Lancer and connect over relay first.")
        }

        guard let relayUUID = SiriIntentSupport.relayMachineUUID(from: record.id),
              let uuid = UUID(uuidString: relayUUID)
        else {
            return .dialog("I couldn't figure out which machine that is.")
        }

        onProgress?(.checkingConnection)

        let relayID = RelayMachineID(uuid)
        // Siri's `openAppWhenRun` brings the app forward fresh, and the relay
        // bridge reconnect that follows a cold launch isn't instant — a bare
        // one-shot check here raced the reconnect and reported "not connected"
        // moments before Home's own state showed it green (found on-device
        // 2026-07-03: real machine, real workspace, real prior message sent,
        // Siri still refused). Give the reconnect a few seconds, matching the
        // cold-launch relay race already fixed elsewhere in the app.
        let bridgeActive = await pollBridgeActive(relayID: relayID)
        let online = SiriIntentSupport.machineConnectivityLabel(record) == "online" || bridgeActive
        guard online else {
            let message = record.displayName.isEmpty
                ? "I can't reach Lancer's connection to your machine right now — open the app and I'll try again."
                : "I can't reach \(record.displayName) right now — open Lancer and I'll try again once it's back."
            return .dialog(message)
        }

        let cwd: String
        if let workspace {
            guard let ws = try await catalog.workspaces(machineID: relayUUID).first(where: { $0.id == workspace.id }) else {
                return .dialog("I couldn't find that workspace on this machine anymore.")
            }
            cwd = ws.path
        } else {
            let workspaces = try await catalog.workspaces(machineID: relayUUID)
            Self.logger.info("prepare: workspaces(machineID=\(relayUUID, privacy: .public)) -> \(workspaces.count, privacy: .public) rows")
            if let mru = workspaces.first {
                cwd = mru.path
            } else if let recentCwd = try await mostRecentConversationCwd(hostName: record.displayName, catalog: catalog) {
                // Home doesn't require an explicit `Workspace` row to show a
                // "workspace" — `LancerHomeView` synthesizes one from any
                // directory that already has chat history for this host
                // (`byWorkspace = Dictionary(grouping: sessions, by: \.cwd)`).
                // This lookup only knows about explicit `Workspace` rows, so
                // it disagreed with what Home visibly showed (found live
                // 2026-07-03: Home showed "Relay host · roshansilva" with 2
                // sessions, no matching `workspaces` table row, and this
                // refused with "no workspace is set up"). Match Home's
                // definition: fall back to the most recent conversation's
                // directory on this host.
                Self.logger.info("prepare: no Workspace row for '\(record.displayName, privacy: .public)', using most-recent-conversation cwd fallback")
                cwd = recentCwd
            } else {
                return .dialog("There's no workspace set up on \(record.displayName) yet — open Lancer and pick a project folder first.")
            }
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
            "Ready to start \(prepared.agentName) on \(prepared.displayName), in \(prepared.workspaceLabel), with: \"\(SiriIntentSupport.promptExcerpt(prepared.trimmedPrompt))\". Want me to go ahead?"
        )
    }
}
