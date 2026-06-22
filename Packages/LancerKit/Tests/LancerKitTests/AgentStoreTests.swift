import Foundation
import Testing
@testable import AgentKit

@Suite("AgentStore entitlement gating")
struct AgentStoreTests {
    @Test("hasHostedAgentsAccess requires active cloud entitlement in release mode")
    func releaseGating() {
        let inactive = CloudEntitlement(status: "inactive", active: false)
        #expect(!CloudEntitlementPolicy.hasCloudEntitlement(inactive, backendURLConfigured: true, debugBypass: false))
    }
}
