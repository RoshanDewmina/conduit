import Foundation
import LancerCore
import PersistenceKit
import SSHTransport

/// Package-level start-run validation used by `StartAgentRunSupport` (Lancer
/// app target) and unit tests. Pure logic over already-fetched data — no
/// `AppIntents`/Keychain/UIKit imports — so it can be exercised directly by
/// `StartAgentRunIntentTests` without standing up the intents runtime.
///
/// Siri Phase 2 (resurrected in I1): only dispatches to relay-paired
/// machines. A relay bridge is a fire-and-forget WebSocket the daemon keeps
/// warm and reconnects on its own — reachable from a Siri-triggered cold
/// launch. An SSH host needs an already-open in-app "fleet slot"
/// (`AppRoot.resolveAgentTransport`'s SSH branch), which App Intents has no
/// way to establish; routing a voice-started run there would either hang or
/// surface a confusing "Host is no longer connected" for a host nobody
/// disconnected. `prepare` below rejects `.sshHost` machines with an explicit
/// dialog instead.
public enum StartAgentRunPreparer {
    public enum Stage: String, Sendable {
        case resolvingMachine
        case checkingConnection
    }

    public struct PreparedRun: Sendable {
        public let relayMachineID: RelayMachineID
        public let machineRecordID: String
        public let displayName: String
        public let cwd: String
        public let workspaceLabel: String
        public let agentName: String
        public let vendor: String
        public let trimmedPrompt: String

        public init(
            relayMachineID: RelayMachineID,
            machineRecordID: String,
            displayName: String,
            cwd: String,
            workspaceLabel: String,
            agentName: String,
            vendor: String,
            trimmedPrompt: String
        ) {
            self.relayMachineID = relayMachineID
            self.machineRecordID = machineRecordID
            self.displayName = displayName
            self.cwd = cwd
            self.workspaceLabel = workspaceLabel
            self.agentName = agentName
            self.vendor = vendor
            self.trimmedPrompt = trimmedPrompt
        }
    }

    public enum PrepareResult: Sendable {
        case ready(PreparedRun)
        case dialog(String)
    }

    /// `machineID` is the raw relay-machine UUID string (the `MachineEntity`
    /// id with its `"relay:"` prefix already stripped by the caller) — or, for
    /// an `.sshHost` entity the caller detected up front, `nil`/anything not
    /// matching a known relay machine, which resolves to the "needs a
    /// relay-paired machine" dialog below.
    public static func prepare(
        relayMachineID: String?,
        relayMachines: [RelayMachineRecord],
        agentDisplayName: String,
        vendor: String,
        prompt: String,
        workspaceID: String?,
        workspaceRepository: WorkspaceRepository,
        conversationRepository: ChatConversationRepository,
        bridgeActive: @escaping @Sendable (RelayMachineID) async -> Bool,
        onProgress: ((Stage) -> Void)? = nil
    ) async throws -> PrepareResult {
        onProgress?(.resolvingMachine)

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return .dialog("Sure — what should the agent work on?")
        }

        guard !relayMachines.isEmpty else {
            return .dialog("You don't have any machines paired yet — open Lancer and connect one first.")
        }

        guard let relayMachineID,
              let uuid = UUID(uuidString: relayMachineID),
              let record = relayMachines.first(where: { $0.id == RelayMachineID(uuid) })
        else {
            return .dialog("Starting a run by voice needs a relay-paired machine — open Lancer and connect over relay first.")
        }

        onProgress?(.checkingConnection)

        let bridgeActiveNow = await bridgeActive(record.id)
        let online = machineConnectivityLabel(record) == "online" || bridgeActiveNow
        guard online else {
            return .dialog("I can't reach \(record.displayName) right now — open Lancer and I'll try again once it's back.")
        }

        let cwd: String
        if let workspaceID {
            guard let ws = try await workspaceRepository.workspace(id: workspaceID), ws.machineID == record.id else {
                return .dialog("I couldn't find that workspace on this machine anymore.")
            }
            cwd = ws.path
        } else {
            let workspaces = try await workspaceRepository.list(machineID: record.id)
            if let mru = workspaces.first {
                cwd = mru.path
            } else if let recentCwd = try await mostRecentConversationCwd(hostName: record.displayName, repository: conversationRepository) {
                cwd = recentCwd
            } else {
                return .dialog("There's no workspace set up on \(record.displayName) yet — open Lancer and pick a project folder first.")
            }
        }

        let workspaceLabel = URL(fileURLWithPath: cwd).lastPathComponent

        return .ready(
            PreparedRun(
                relayMachineID: record.id,
                machineRecordID: "relay:\(record.id.uuidString)",
                displayName: record.displayName,
                cwd: cwd,
                workspaceLabel: workspaceLabel,
                agentName: agentDisplayName,
                vendor: vendor,
                trimmedPrompt: trimmedPrompt
            )
        )
    }

    public static func machineConnectivityLabel(_ machine: RelayMachineRecord) -> String {
        guard let last = machine.lastConnectedAt else { return "offline" }
        if last.timeIntervalSinceNow > -600 { return "online" }
        return "stale"
    }

    private static func mostRecentConversationCwd(
        hostName: String,
        repository: ChatConversationRepository
    ) async throws -> String? {
        try await repository.recent(limit: 25)
            .first { $0.hostName == hostName }?
            .cwd
    }
}
