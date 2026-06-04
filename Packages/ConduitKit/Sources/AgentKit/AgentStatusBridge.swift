import ConduitCore

extension AgentStatusSnapshot {
    public func mergeIntoQuota(_ quota: HostedQuotaSnapshot) -> HostedQuotaSnapshot {
        var q = quota
        if let total = totalUsageUSD, quota.creditsRemainingUSD == nil {
            q.usageTodayUSD = total
        }
        let running = agents.compactMap(\.runningCount).reduce(0, +)
        if running > 0, quota.concurrentRuns == 0 {
            q.concurrentRuns = running
        }
        return q
    }
}
