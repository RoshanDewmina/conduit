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
