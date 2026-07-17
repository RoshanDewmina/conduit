#if os(iOS)
import Foundation
import LancerCore
import SessionFeature
import SSHTransport

/// Resolves the live host transport for governance Settings actions.
/// Emergency stop + audit tail: SSH `DaemonChannel` first, then a relay mirror
/// (`agentEmergencyStop` / `agentAuditTail`) — same fallback shape.
/// Permission mode (coarse deny/ask/allow): SSH `agent.permissionMode.get`/`.set`
/// first, then relay `agentPermissionModeGet`/`agentPermissionModeSet`. Real
/// repo `cwd` scopes to a per-chat override; ""/"~" keeps the document-level
/// default (Settings). Full per-rule policy YAML editing stays SSH-only.
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

    static func tailAudit(limit: Int = 100, relayFleetStore: RelayFleetStore) async throws -> [AuditLogEntry] {
        if let channel = ApprovalRelay.shared.channel {
            return try await channel.tailAudit(limit: limit).entries
        }
        if let bridge = relayFleetStore.firstConnectedMachine?.bridge {
            return try await bridge.sendAuditTail(limit: limit)
        }
        throw Failure.noTransport
    }

    /// Reads the coarse policy default (deny/ask/allow). SSH-first via
    /// `agent.permissionMode.get` (per-cwd override when `cwd` is a real repo
    /// path; document default for ""/"~"); relay fallback via
    /// `agentPermissionModeGet` for a relay-only pairing.
    static func fetchPermissionMode(cwd: String = "~", relayFleetStore: RelayFleetStore) async throws -> PermissionMode {
        if let channel = ApprovalRelay.shared.channel {
            let result = try await channel.fetchPermissionMode(cwd: cwd)
            guard let mode = PermissionMode(rawValue: result.mode) else {
                throw Failure.noTransport
            }
            return mode
        }
        if let bridge = relayFleetStore.firstConnectedMachine?.bridge {
            let result = try await bridge.sendPermissionModeGet(cwd: cwd)
            guard let mode = PermissionMode(rawValue: result.mode) else {
                throw Failure.noTransport
            }
            return mode
        }
        throw Failure.noTransport
    }

    /// Writes ONLY the coarse policy default (deny/ask/allow) — never full rules
    /// YAML. SSH-first via `agent.permissionMode.set` (per-cwd override when
    /// `cwd` is a real repo path; document Default for ""/"~"); relay fallback
    /// via `agentPermissionModeSet` for a relay-only pairing.
    static func setPermissionMode(_ mode: PermissionMode, cwd: String = "~", relayFleetStore: RelayFleetStore) async throws {
        if let channel = ApprovalRelay.shared.channel {
            let result = try await channel.setPermissionMode(mode, cwd: cwd)
            guard result.ok else {
                throw Failure.noTransport
            }
            return
        }
        if let bridge = relayFleetStore.firstConnectedMachine?.bridge {
            let result = try await bridge.sendPermissionModeSet(mode, cwd: cwd)
            guard result.ok else {
                throw Failure.noTransport
            }
            return
        }
        throw Failure.noTransport
    }
}
#endif
