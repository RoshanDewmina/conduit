#if os(iOS)
import Foundation

/// A dispatchable agent target surfaced in composer/run pickers and fleet routing.
public struct DispatchAgent: Identifiable {
    public let id: String
    public let name: String
    public let cwd: String
    public let isOffline: Bool
    public let hostID: String?
    public let hostName: String?

    /// The agent kind after the "|" separator in id, e.g. "opencode", "claudeCode", "codex".
    public var vendor: String {
        id.split(separator: "|", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
    }

    public init(
        id: String,
        name: String,
        cwd: String,
        isOffline: Bool,
        hostID: String? = nil,
        hostName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.isOffline = isOffline
        self.hostID = hostID
        self.hostName = hostName
    }

    /// Picks the best dispatch agent for a composer run-target selection.
    /// Prefers an online agent on `preferredMachineID`, then any agent on that
    /// machine, then the first online agent, then any agent.
    public static func preferredAgentID(
        from agents: [DispatchAgent],
        preferredMachineID: String?
    ) -> String {
        if let machineID = preferredMachineID {
            if let match = agents.first(where: { !$0.isOffline && $0.hostID == machineID }) {
                return match.id
            }
            if let match = agents.first(where: { $0.hostID == machineID }) {
                return match.id
            }
        }
        if let online = agents.first(where: { !$0.isOffline }) {
            return online.id
        }
        return agents.first?.id ?? "claude"
    }
}
#endif
