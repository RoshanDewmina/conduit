import Foundation
import Testing
@testable import AgentKit

@Suite("Cloud entitlement gating")
struct CloudEntitlementTests {
    @Test("active entitlement decodes from backend JSON")
    func decodesActiveEntitlement() throws {
        let json = """
        {
          "customerId": "cus_123",
          "subscriptionId": "sub_456",
          "status": "active",
          "active": true,
          "openRouterAPIKey": "sk-or-v1-test",
          "clientToken": "ctok_abc123"
        }
        """.data(using: .utf8)!

        let entitlement = try JSONDecoder().decode(CloudEntitlement.self, from: json)
        #expect(entitlement.active)
        #expect(entitlement.customerId == "cus_123")
        #expect(entitlement.openRouterAPIKey == "sk-or-v1-test")
        #expect(entitlement.clientToken == "ctok_abc123")
    }

    @Test("policy separates inactive entitlement from debug bypass")
    func policyGating() {
        let inactive = CloudEntitlement(status: "inactive", active: false)
        #expect(!CloudEntitlementPolicy.hasCloudEntitlement(inactive, backendURLConfigured: true))
        #expect(CloudEntitlementPolicy.hasCloudEntitlement(inactive, backendURLConfigured: true, debugBypass: true))

        let active = CloudEntitlement(status: "active", active: true)
        #expect(CloudEntitlementPolicy.hasCloudEntitlement(active, backendURLConfigured: true))
    }

    @Test("AgentStoreError entitlementRequired is equatable")
    func storeErrors() {
        #expect(AgentStoreError.entitlementRequired == AgentStoreError.entitlementRequired)
    }

    @Test("teamOrg is nil without orgId")
    func noTeamWithoutOrg() {
        let ent = CloudEntitlement(active: true)
        #expect(ent.teamOrg == nil)
    }
}
