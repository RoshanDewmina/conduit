import Testing
@testable import LancerCore

@Suite struct FleetSummaryTests {
    @Test("aggregates vendor count, logged-in, and total spend")
    func summary() {
        let snaps = [
            AgentStatusSnapshot(agents: [
                AgentVendorStatus(agent: "claudeCode", loggedIn: true, model: "claude-sonnet-4.6", sessionCount: 2, usageUSD: 3.18),
                AgentVendorStatus(agent: "codex", loggedIn: true, model: "gpt-5.1-codex", sessionCount: 1, usageUSD: 0.74),
                AgentVendorStatus(agent: "opencode", loggedIn: false, sessionCount: 0),
            ]),
            AgentStatusSnapshot(agents: [
                AgentVendorStatus(agent: "claudeCode", loggedIn: true, model: "claude-opus", sessionCount: 1, usageUSD: 1.10),
            ]),
        ]
        let s = FleetSummary(snapshots: snaps)
        #expect(s.loggedInVendors == 2)
        #expect(s.activeSessions == 4)
        #expect(abs(s.totalSpendUSD - 5.02) < 0.001)
    }
}
