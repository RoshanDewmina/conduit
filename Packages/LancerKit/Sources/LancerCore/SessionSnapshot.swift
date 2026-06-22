// Adapted from cmux (MIT) — Sources/SessionPersistence.swift (the schema
// + caps; not the storage layer, which is GRDB-backed here).
//
// A `SessionSnapshot` records what was last running on a host so that the
// next connection can auto-resume it. Persistence is keyed by `hostID`
// — one snapshot per host, overwritten on each successful connect.

import Foundation

/// Last-known agent/session state for a single host.
/// Used by `SessionViewModel.connect()` to decide whether to issue an
/// `AgentResumeBuilder` command after attaching/creating the tmux session.
public struct SessionSnapshot: Codable, Hashable, Sendable {
    /// Host this snapshot belongs to.
    public let hostID: HostID

    /// When the user was last actively in a session on this host.
    /// Drives "auto-attach to most-recent" sort order.
    public var lastUsedTime: Date

    /// The agent that was running, matching an `AgentRegistration.id`.
    /// `nil` when the last session wasn't running a known agent.
    public var agentID: String?

    /// Captured session identifier passed to `AgentResumeBuilder`.
    public var agentSessionID: String?

    /// Working directory recorded at the time of capture; used to `cd` before
    /// the resume command when the agent's `cwd` policy is `.preserve`.
    public var agentWorkingDirectory: String?

    /// Tmux session name (may differ from `Host.tmuxSessionName` if the user
    /// attached to an ad-hoc session).
    public var tmuxSessionName: String?

    public init(
        hostID: HostID,
        lastUsedTime: Date = .now,
        agentID: String? = nil,
        agentSessionID: String? = nil,
        agentWorkingDirectory: String? = nil,
        tmuxSessionName: String? = nil
    ) {
        self.hostID = hostID
        self.lastUsedTime = lastUsedTime
        self.agentID = agentID
        self.agentSessionID = agentSessionID
        self.agentWorkingDirectory = agentWorkingDirectory
        self.tmuxSessionName = tmuxSessionName
    }

    /// True when this snapshot carries enough state to attempt an agent
    /// resume command on next connect.
    public var isResumable: Bool {
        guard let agentID, !agentID.isEmpty,
              let sid = agentSessionID, !sid.isEmpty else { return false }
        return true
    }
}

// MARK: - Persistence caps (from cmux SessionPersistence.swift:15-49)

/// Limits Lancer enforces when persisting session/scrollback state. cmux's
/// values were measured at scale on macOS; we adopt the same shape so the
/// app stays bounded even with many hosts.
public enum SessionPersistenceLimits {
    public static let maxScrollbackLines: Int = 4_000
    public static let maxScrollbackBytesPerBlock: Int = 400_000
    public static let maxSnapshotsRetained: Int = 1_000
}
