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
}
