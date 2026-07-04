import Foundation
import PersistenceKit

/// Package-level start-run validation used by `StartAgentRunSupport` and unit tests.
public enum StartAgentRunPreparer {
    public enum Stage: String, Sendable {
        case resolvingMachine
        case checkingConnection
    }

    public struct PreparedRun: Sendable {
        public let relayUUID: String
        public let machineRecordID: String
        public let displayName: String
        public let cwd: String
        public let workspaceLabel: String
        public let agentName: String
        public let vendor: String
        public let trimmedPrompt: String

        public init(
            relayUUID: String,
            machineRecordID: String,
            displayName: String,
            cwd: String,
            workspaceLabel: String,
            agentName: String,
            vendor: String,
            trimmedPrompt: String
        ) {
            self.relayUUID = relayUUID
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

    public static func machineConnectivityLabel(_ machine: IntentMachineRecord) -> String {
        guard let last = machine.lastConnectedAt else { return "offline" }
        if last.timeIntervalSinceNow > -600 { return "online" }
        let minutes = max(1, Int(-last.timeIntervalSinceNow / 60))
        return "last seen \(minutes)m ago"
    }

    public static func relayMachineUUID(from machineRecordID: String) -> String? {
        if machineRecordID.hasPrefix("relay:") {
            return String(machineRecordID.dropFirst("relay:".count))
        }
        return UUID(uuidString: machineRecordID).map(\.uuidString)
    }

    public static func prepare(
        catalog: IntentEntityCatalog,
        relayMachines: [IntentRelayMachineSnapshot],
        machineID: String,
        vendor: String,
        agentDisplayName: String,
        prompt: String,
        workspaceID: String?,
        bridgeActive: @escaping @Sendable (UUID) async -> Bool,
        onProgress: ((Stage) -> Void)? = nil
    ) async throws -> PrepareResult {
        onProgress?(.resolvingMachine)

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return .dialog("Sure — what should the agent work on?")
        }

        let machines = try await catalog.machines(relayMachines: relayMachines)
        guard !machines.isEmpty else {
            return .dialog("You don't have any machines paired yet — open Lancer and connect one first.")
        }

        guard let record = try await catalog.machine(id: machineID, relayMachines: relayMachines) else {
            return .dialog("That machine isn't paired anymore — check Lancer to reconnect it.")
        }

        guard record.kind == .relayMachine else {
            return .dialog("Starting a run by voice needs a relay-paired machine — open Lancer and connect over relay first.")
        }

        guard let relayUUID = relayMachineUUID(from: record.id),
              let uuid = UUID(uuidString: relayUUID)
        else {
            return .dialog("I couldn't figure out which machine that is.")
        }

        onProgress?(.checkingConnection)

        let bridgeActiveNow = await bridgeActive(uuid)
        let online = machineConnectivityLabel(record) == "online" || bridgeActiveNow
        guard online else {
            let message = record.displayName.isEmpty
                ? "I can't reach Lancer's connection to your machine right now — open the app and I'll try again."
                : "I can't reach \(record.displayName) right now — open Lancer and I'll try again once it's back."
            return .dialog(message)
        }

        let cwd: String
        if let workspaceID {
            guard let ws = try await catalog.workspaces(machineID: relayUUID).first(where: { $0.id == workspaceID }) else {
                return .dialog("I couldn't find that workspace on this machine anymore.")
            }
            cwd = ws.path
        } else {
            let workspaces = try await catalog.workspaces(machineID: relayUUID)
            if let mru = workspaces.first {
                cwd = mru.path
            } else if let recentCwd = try await mostRecentConversationCwd(hostName: record.displayName, catalog: catalog) {
                cwd = recentCwd
            } else {
                return .dialog("There's no workspace set up on \(record.displayName) yet — open Lancer and pick a project folder first.")
            }
        }

        let workspaceLabel = URL(fileURLWithPath: cwd).lastPathComponent

        return .ready(
            PreparedRun(
                relayUUID: relayUUID,
                machineRecordID: record.id,
                displayName: record.displayName,
                cwd: cwd,
                workspaceLabel: workspaceLabel,
                agentName: agentDisplayName,
                vendor: vendor,
                trimmedPrompt: trimmedPrompt
            )
        )
    }

    private static func mostRecentConversationCwd(hostName: String, catalog: IntentEntityCatalog) async throws -> String? {
        try await catalog.conversations()
            .first { $0.hostName == hostName }?
            .workspacePath
    }
}
