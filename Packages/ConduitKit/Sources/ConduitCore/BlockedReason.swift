import Foundation

/// Why an agent session or run is currently blocked.
public enum BlockedReason: Sendable, Equatable, Hashable, Codable {
    /// Waiting for user approval on a specific action
    case awaitingApproval(approvalID: String, command: String, agent: String)
    /// Policy engine is evaluating
    case awaitingPolicyEvaluation
    /// Network connection is stale
    case networkStale(lastBytesReceived: Date)
    /// Daemon is unreachable
    case daemonUnreachable(lastContact: Date)
    /// Watchdog detected no activity for N seconds
    case watchdogTimeout(secondsSinceLastActivity: Int)
    /// Run is paused by user
    case pausedByUser
    /// Budget cap exceeded
    case budgetExceeded(spentUSD: Double, capUSD: Double)

    /// Human-readable description for the "Why am I blocked?" line
    public var displayReason: String {
        switch self {
        case .awaitingApproval(_, let command, _):
            return "Waiting for approval: \(command.prefix(60))"
        case .awaitingPolicyEvaluation:
            return "Evaluating policy..."
        case .networkStale:
            return "Network connection is stale"
        case .daemonUnreachable:
            return "Host daemon is unreachable"
        case .watchdogTimeout(let seconds):
            return "No activity for \(seconds)s — checking..."
        case .pausedByUser:
            return "Paused by you"
        case .budgetExceeded(let spent, let cap):
            return "Budget exceeded: $\(String(format: "%.2f", spent)) / $\(String(format: "%.2f", cap))"
        }
    }

    /// Severity for UI rendering
    public var severity: Severity {
        switch self {
        case .awaitingApproval: return .warning
        case .awaitingPolicyEvaluation: return .info
        case .networkStale, .daemonUnreachable: return .critical
        case .watchdogTimeout: return .warning
        case .pausedByUser: return .info
        case .budgetExceeded: return .critical
        }
    }

    public enum Severity: Sendable { case info, warning, critical }
}
