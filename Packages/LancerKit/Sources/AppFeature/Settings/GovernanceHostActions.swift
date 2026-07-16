#if os(iOS)
import Foundation
import LancerCore
import SessionFeature
import SSHTransport

/// Resolves the live host transport for governance Settings actions.
/// Emergency stop + audit tail: SSH `DaemonChannel` first, then a relay mirror
/// (`agentEmergencyStop` / `agentAuditTail`) — same fallback shape.
/// Permission mode (coarse deny/ask/allow default): SSH `agent.policy.get`/`.set`
/// first, then relay `agentPermissionModeGet`/`agentPermissionModeSet`.
/// Full per-rule policy YAML editing stays SSH-only: no relay round-trip of the
/// entire rules document (see docs/product/2026-07-16-policy-audit-relay-port-map.md —
/// none of the studied competitors expose full remote rules editing either).
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

    /// Reads the coarse policy default (deny/ask/allow). SSH-first via the
    /// existing `agent.policy.get` RPC's `default` field; relay fallback via
    /// `agentPermissionModeGet` for a relay-only pairing.
    static func fetchPermissionMode(cwd: String = "~", relayFleetStore: RelayFleetStore) async throws -> PermissionMode {
        if let channel = ApprovalRelay.shared.channel {
            let result = try await channel.fetchPolicy(cwd: cwd)
            guard let raw = result.default, let mode = PermissionMode(rawValue: raw) else {
                throw Failure.noTransport
            }
            return mode
        }
        if let bridge = relayFleetStore.firstConnectedMachine?.bridge {
            let result = try await bridge.sendPermissionModeGet()
            guard let mode = PermissionMode(rawValue: result.mode) else {
                throw Failure.noTransport
            }
            return mode
        }
        throw Failure.noTransport
    }

    /// Writes ONLY the coarse policy default (deny/ask/allow) — never full rules
    /// YAML. SSH-first via `agent.policy.set` (re-reading current YAML and
    /// patching just `default:` so existing rules survive); relay fallback via
    /// `agentPermissionModeSet` for a relay-only pairing.
    static func setPermissionMode(_ mode: PermissionMode, cwd: String = "~", relayFleetStore: RelayFleetStore) async throws {
        if let channel = ApprovalRelay.shared.channel {
            let current = try await channel.fetchPolicy(cwd: cwd)
            guard let yaml = current.yaml else {
                throw Failure.noTransport
            }
            let patched = Self.replacingDefaultLine(in: yaml, with: mode.rawValue)
            try await channel.savePolicyYAML(cwd: cwd, yaml: patched)
            return
        }
        if let bridge = relayFleetStore.firstConnectedMachine?.bridge {
            let result = try await bridge.sendPermissionModeSet(mode)
            guard result.ok else {
                throw Failure.noTransport
            }
            return
        }
        throw Failure.noTransport
    }

    /// Rewrites (or inserts) the top-level `default:` line in a policy YAML
    /// document, leaving every other line — including all rules — untouched.
    /// Used only by the SSH path of `setPermissionMode`, which must patch a
    /// single field without round-tripping a structured rules editor through
    /// this coarse-mode control.
    private static func replacingDefaultLine(in yaml: String, with mode: String) -> String {
        var lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var replaced = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("default:") {
                lines[i] = "default: \(mode)"
                replaced = true
                break
            }
        }
        if !replaced {
            lines.insert("default: \(mode)", at: 0)
        }
        return lines.joined(separator: "\n")
    }
}
#endif
