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
          "openRouterAPIKey": "sk-or-v1-test"
        }
        """.data(using: .utf8)!

        let entitlement = try JSONDecoder().decode(CloudEntitlement.self, from: json)
        #expect(entitlement.active)
        #expect(entitlement.customerId == "cus_123")
        #expect(entitlement.openRouterAPIKey == "sk-or-v1-test")
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
}
