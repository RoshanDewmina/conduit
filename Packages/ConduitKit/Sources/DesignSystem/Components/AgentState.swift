import SwiftUI
import ConduitCore

// Mirrors STATE_META from agent-chat-v2.css — drives badge color + label
// across the HUD strip, session rows, and tool card headers.
public enum AgentState: String, Sendable, Hashable, CaseIterable {
    case thinking
    case streaming
    case approval
    case done
    case error
    case offline

    public var label: String {
        switch self {
        case .thinking:  "Thinking"
        case .streaming: "Streaming"
        case .approval:  "Needs approval"
        case .done:      "Connected"
        case .error:     "Error"
        case .offline:   "Offline"
        }
    }

    public var systemImage: String {
        switch self {
        case .thinking:  "ellipsis.circle"
        case .streaming: "bolt.horizontal"
        case .approval:  "exclamationmark.triangle"
        case .done:      "checkmark.circle"
        case .error:     "xmark.circle"
        case .offline:   "wifi.slash"
        }
    }

    /// Semantic color (use within token system)
    public func color(tokens: ConduitTokens) -> Color {
        switch self {
        case .thinking:  tokens.accent
        case .streaming: tokens.info
        case .approval:  tokens.warn
        case .done:      tokens.ok
        case .error:     tokens.danger
        case .offline:   tokens.text4
        }
    }

    /// Derive from Session.Status (maps lifecycle → AgentState)
    public static func from(isExecuting: Bool, status: String) -> AgentState {
        switch status {
        case "connecting":   return .thinking
        case "connected":    return isExecuting ? .streaming : .done
        case "disconnected": return .offline
        case "suspended":    return .offline
        case "failed":       return .error
        default:             return isExecuting ? .streaming : .done
        }
    }
}

/// Rich agent state that includes blocking context.
public struct AgentStateContext: Sendable, Equatable {
    public let state: AgentState
    public let blockedReason: BlockedReason?
    public let lastActivity: Date?
    public let lastBytesReceived: Date?

    public init(
        state: AgentState,
        blockedReason: BlockedReason? = nil,
        lastActivity: Date? = nil,
        lastBytesReceived: Date? = nil
    ) {
        self.state = state
        self.blockedReason = blockedReason
        self.lastActivity = lastActivity
        self.lastBytesReceived = lastBytesReceived
    }
}

extension BlockedReason.Severity {
    /// Map severity onto the risk-ramp tone used across DSChip / status surfaces:
    /// info → neutral, warning → amber/orange, critical → red.
    public func color(tokens: ConduitTokens) -> Color {
        switch self {
        case .info:     return tokens.text3
        case .warning:  return tokens.warn
        case .critical: return tokens.danger
        }
    }

    var systemImage: String {
        switch self {
        case .info:     return "clock"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

/// "Why am I blocked?" line — renders a `BlockedReason` with severity-appropriate
/// styling (risk ramp: info → neutral, warning → amber, critical → red). Designed
/// to sit on the always-dark HUD strip, so it reads colors against `hudText`.
public struct DSBlockedReasonRow: View {
    let reason: BlockedReason
    let onDark: Bool

    @Environment(\.conduitTokens) private var t

    public init(_ reason: BlockedReason, onDark: Bool = false) {
        self.reason = reason
        self.onDark = onDark
    }

    /// Convenience: render only when an `AgentStateContext` carries a blocked reason.
    public init?(context: AgentStateContext, onDark: Bool = false) {
        guard let reason = context.blockedReason else { return nil }
        self.reason = reason
        self.onDark = onDark
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: reason.severity.systemImage)
                .font(.caption2)
                .foregroundStyle(accent)
            Text(reason.displayReason)
                .font(.caption.weight(.medium))
                .foregroundStyle(textColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(onDark ? 0.16 : 0.10))
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
    }

    private var accent: Color { reason.severity.color(tokens: t) }
    private var textColor: Color { onDark ? t.hudText : t.text }
}
