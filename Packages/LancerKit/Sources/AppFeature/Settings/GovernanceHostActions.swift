#if os(iOS)
import Foundation
import LancerCore
import SessionFeature
import SSHTransport

/// Resolves the live host transport for governance Settings actions.
/// Emergency stop: SSH `DaemonChannel` first, then relay `agentEmergencyStop`.
/// Policy + audit: SSH only (no relay mirror on the daemon today).
@MainActor
enum GovernanceHostActions {
    enum Failure: Error, LocalizedError {
        case noTransport
        case sshRequired(String)

        var errorDescription: String? {
            switch self {
            case .noTransport:
                return "No connected host. Pair a trusted machine or open an SSH session first."
            case .sshRequired(let surface):
                return "\(surface) requires an SSH host session. Relay-only pairings cannot reach this RPC yet."
            }
        }
    }

    static func emergencyStop(relayFleetStore: RelayFleetStore) async throws -> EmergencyStopResult {
        if let channel = ApprovalRelay.shared.channel {
            return try await channel.emergencyStop()
        }
        if let bridge = relayFleetStore.firstConnectedMachine?.bridge {
            return try await bridge.sendEmergencyStop()
        }
        throw Failure.noTransport
    }

    static func fetchPolicy(cwd: String = "~") async throws -> PolicyGetResult {
        guard let channel = ApprovalRelay.shared.channel else {
            throw Failure.sshRequired("Policy")
        }
        return try await channel.fetchPolicy(cwd: cwd)
    }

    static func savePolicyYAML(cwd: String = "~", yaml: String) async throws {
        guard let channel = ApprovalRelay.shared.channel else {
            throw Failure.sshRequired("Policy save")
        }
        try await channel.savePolicyYAML(cwd: cwd, yaml: yaml)
    }

    static func tailAudit(limit: Int = 100) async throws -> [AuditLogEntry] {
        guard let channel = ApprovalRelay.shared.channel else {
            throw Failure.sshRequired("Audit feed")
        }
        return try await channel.tailAudit(limit: limit).entries
    }
}
#endif
