import Foundation

/// Per-session autonomy preset: controls which approval requests are surfaced
/// to the user and which are handled automatically by the client.
public enum AutonomyPreset: String, CaseIterable, Sendable, Codable {
    /// Low-risk reads (exit-checks, git status, file reads) are approved
    /// automatically. All writes and destructive ops still ask the user.
    case autoReads

    /// Every agent action surfaces an approval request, regardless of risk.
    case alwaysAsk

    /// Only `critical`-risk actions require manual approval.
    /// The agent's own risk assessment gates the rest.
    case agentDecides

    public var label: String {
        switch self {
        case .autoReads:    return "Auto-approve reads"
        case .alwaysAsk:    return "Always ask"
        case .agentDecides: return "Critical only"
        }
    }

    public var shortLabel: String {
        switch self {
        case .autoReads:    return "Auto-reads"
        case .alwaysAsk:    return "Always ask"
        case .agentDecides: return "Critical only"
        }
    }

    public var description: String {
        switch self {
        case .autoReads:
            return "Read-only operations are approved automatically. Writes and destructive actions always ask."
        case .alwaysAsk:
            return "Every agent action requires your approval before it runs."
        case .agentDecides:
            return "Only critical-risk actions ask. Low, medium, and high-risk actions can run automatically."
        }
    }

    /// Returns `true` if an approval with `risk` should be auto-approved
    /// under this preset without surfacing the inbox card.
    public func isAutoApproved(kind: Approval.Kind, risk: Approval.Risk) -> Bool {
        switch self {
        case .alwaysAsk:
            return false
        case .autoReads:
            return risk == .low && (kind == .command || kind == .callMCP)
        case .agentDecides:
            return risk < .critical
        }
    }
}
