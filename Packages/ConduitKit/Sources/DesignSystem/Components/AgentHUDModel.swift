import SwiftUI

// MARK: - AgentInfo
// Store-free value type carrying everything the Agent Island needs to render
// one agent — compact pill (state + host + badge) and the expanded panel
// (header, tool line, progress stats, inline approval, roster row).

public struct AgentInfo: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let agentKey: AgentKey
    public let host: String
    public let cwd: String
    public let state: AgentState
    public let tool: String?
    public let pendingApprovals: Int
    /// Step / elapsed / tokens shown in the expanded panel. Optional — when the
    /// app has no telemetry yet this is filled with `AgentDemoData` (see store).
    public let progress: AgentProgress?
    /// A pending command awaiting approval, shown as the inline amber card.
    public let approval: AgentApproval?

    public init(
        id: UUID = UUID(),
        name: String,
        agentKey: AgentKey,
        host: String,
        cwd: String,
        state: AgentState,
        tool: String? = nil,
        pendingApprovals: Int = 0,
        progress: AgentProgress? = nil,
        approval: AgentApproval? = nil
    ) {
        self.id = id
        self.name = name
        self.agentKey = agentKey
        self.host = host
        self.cwd = cwd
        self.state = state
        self.tool = tool
        self.pendingApprovals = pendingApprovals
        self.progress = progress
        self.approval = approval
    }

#if DEBUG
    // A believable multi-agent roster used as the Island's mock backdrop while
    // real per-agent telemetry (steps/tokens/multi-session) doesn't exist yet.
    public static let demoSeed: [AgentInfo] = [
        AgentInfo(
            name: "Claude Code",
            agentKey: .claudeCode,
            host: "Prod EU",
            cwd: "/srv/api",
            state: .streaming,
            tool: "tail -f /var/log/app.log",
            progress: AgentProgress(step: 7, total: 12, elapsed: "4m 12s", tokens: "18.2k")
        ),
        AgentInfo(
            name: "Codex",
            agentKey: .codex,
            host: "Dev Box",
            cwd: "~/repo/conduit",
            state: .thinking,
            tool: "Read SessionView.swift · 741 lines",
            progress: AgentProgress(step: 2, total: 9, elapsed: "48s", tokens: "5.1k")
        ),
        AgentInfo(
            name: "OpenCode",
            agentKey: .opencode,
            host: "GPU Box",
            cwd: "~/training",
            state: .approval,
            tool: "rm -rf ~/training/checkpoints/*",
            pendingApprovals: 1,
            approval: AgentApproval(cmd: "rm -rf ~/training/checkpoints/*", risk: .critical)
        ),
        AgentInfo(
            name: "Cursor",
            agentKey: .cursor,
            host: "Mac",
            cwd: "~/code",
            state: .done,
            tool: "git push origin main",
            progress: AgentProgress(step: 9, total: 9, elapsed: "2m 03s", tokens: "11.7k")
        ),
    ]
#endif
}

// MARK: - AgentDemoData
// The single place mock Island data lives. The primary agent is real (live
// session); these fill the fields the app has no telemetry for yet (per-step /
// token metrics, a true multi-session roster). Replace with real data later.

public enum AgentDemoData {
    public static var roster: [AgentInfo] {
        #if DEBUG
        return AgentInfo.demoSeed
        #else
        return []
        #endif
    }

    public static let progress = AgentProgress(step: 7, total: 12, elapsed: "4m 12s", tokens: "18.2k")

    public static func toolLine(for state: AgentState) -> String? {
        switch state {
        case .streaming: return "tail -f /var/log/app.log"
        case .thinking:  return "Read SessionView.swift · 741 lines"
        case .done:      return "git push origin main"
        default:         return nil
        }
    }
}

// MARK: - AgentProgress

public struct AgentProgress: Equatable, Sendable {
    public let step: Int
    public let total: Int
    public let elapsed: String
    public let tokens: String
    public init(step: Int, total: Int, elapsed: String, tokens: String) {
        self.step = step; self.total = total; self.elapsed = elapsed; self.tokens = tokens
    }
}

// MARK: - AgentApproval

public struct AgentApproval: Equatable, Sendable {
    public enum Risk: String, Sendable { case low, medium, high, critical }
    public let cmd: String
    public let risk: Risk
    public init(cmd: String, risk: Risk) { self.cmd = cmd; self.risk = risk }
}

public extension AgentApproval.Risk {
    /// Short uppercase tag shown on the inline approval card.
    var label: String {
        switch self {
        case .low: "LOW"; case .medium: "MED"; case .high: "HIGH"; case .critical: "CRIT"
        }
    }
}

// MARK: - AgentState labels

public extension AgentState {
    /// HUD-specific labels (Responding / Complete / Needs approval / Offline).
    var hudLabel: String {
        switch self {
        case .thinking:  "Thinking"
        case .streaming: "Responding"
        case .approval:  "Needs approval"
        case .done:      "Complete"
        case .error:     "Failed"
        case .offline:   "Offline"
        }
    }

    /// Short labels matching the Agent Island design (`ISLAND_STATES.short`):
    /// Thinking / Streaming / Needs you / Done / Failed / Idle.
    var islandLabel: String {
        switch self {
        case .thinking:  "Thinking"
        case .streaming: "Streaming"
        case .approval:  "Needs you"
        case .done:      "Done"
        case .error:     "Failed"
        case .offline:   "Idle"
        }
    }
}
