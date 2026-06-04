import Testing
import Foundation
@testable import ConduitCore
@testable import AgentKit

@Suite("AgentStatusProtocol")
struct AgentStatusProtocolTests {
    @Test("agent.status RPC result decodes")
    func rpcResultDecode() {
        let json = """
        {"jsonrpc":"2.0","id":2,"result":{"agents":[{"agent":"claudeCode","loggedIn":true,"sessionCount":3,"usageUSD":2.47},{"agent":"codex","sessionCount":1}],"collectedAt":"2026-06-04T12:00:00Z"}}
        """.data(using: .utf8)!
        guard case .agentStatus(let snapshot) = DaemonRPCResponse.decode(from: json) else {
            Issue.record("Expected agentStatus"); return
        }
        #expect(snapshot.agents[0].usageUSD == 2.47)
        #expect(snapshot.agents[1].usageUSD == nil)
        #expect(snapshot.totalUsageUSD == 2.47)
    }

    @Test("quota merge honest")
    func quotaMergeHonest() {
        let snapshot = AgentStatusSnapshot(agents: [
            AgentVendorStatus(agent: "claudeCode", usageUSD: 1.5),
            AgentVendorStatus(agent: "codex", sessionCount: 2),
        ])
        #expect(snapshot.mergeIntoQuota(HostedQuotaSnapshot()).usageTodayUSD == 1.5)
    }
}
