import Foundation

public enum WidgetSnapshot {
    public static let appGroupID = "group.dev.lancer.mobile"
    public static let pendingApprovalsKey = "widgetPendingApprovals"
    public static let sessionStatusKey = "widgetSessionStatus"
    public static let hostNameKey = "widgetHostName"
    public static let lastUpdatedKey = "widgetLastUpdated"
    /// Name of the agent driving the most recently updated session
    /// (`SessionViewModel.liveAgentName`), e.g. "Claude Code". Read by
    /// `AgentStatusWidget`. nil when no agent name is known.
    public static let agentNameKey = "widgetAgentName"
    /// One-liner for the newest pending approval (action + risk), e.g.
    /// "rm -rf build/ · High risk". Read by `PendingApprovalsWidget`. Removed
    /// from the App Group (not just emptied) once the pending count hits zero.
    public static let pendingApprovalSummaryKey = "widgetPendingApprovalSummary"
    /// Unix epoch when `writeApprovalWidgetSnapshot` last rewrote the pending
    /// count/summary. Distinct from `lastUpdatedKey` (session-status writes)
    /// so a status refresh cannot keep a stale approvals count looking "fresh"
    /// to the widget TTL guard.
    public static let pendingApprovalsUpdatedKey = "widgetPendingApprovalsUpdated"

    /// Phone-local pending rows older than this are treated as dead corpses.
    /// Daemon-side resolutions (timeout-deny, restart prune, decision on
    /// another surface) never retire the phone row — only an explicit
    /// in-app/lock-screen decision does — so without a TTL the Home Screen
    /// widget count accumulates forever. Generous vs the daemon's short
    /// no-client grace / historical ~120s hold.
    public static let pendingApprovalTTL: TimeInterval = 10 * 60
}
