import Testing
import Foundation
import LancerCore
@testable import SecurityKit

@Suite("ApprovalDecisionAuth")
struct ApprovalDecisionAuthTests {

    @Test("tier split mirrors PermitsNoClientGrace: high/critical gate, low/medium pass")
    func tierSplit() {
        #expect(!ApprovalDecisionAuth.requiresUnlock(risk: .low))
        #expect(!ApprovalDecisionAuth.requiresUnlock(risk: .medium))
        #expect(ApprovalDecisionAuth.requiresUnlock(risk: .high))
        #expect(ApprovalDecisionAuth.requiresUnlock(risk: .critical))
    }

    @Test("unknown risk fails closed")
    func unknownRiskFailsClosed() {
        #expect(ApprovalDecisionAuth.requiresUnlock(risk: nil))
    }

    @Test("low/medium decision commits without invoking the unlock at all")
    func lowRiskNeverPrompts() async {
        let ok = await ApprovalDecisionAuth.authorize(risk: .medium) { _ in
            Issue.record("unlock must not run for a medium-risk decision")
        }
        #expect(ok)
    }

    @Test("high-risk decision without a successful unlock is rejected")
    func highRiskFailedUnlockBlocks() async {
        let ok = await ApprovalDecisionAuth.authorize(risk: .high) { _ in
            throw LancerError.cancelled
        }
        #expect(!ok)
    }

    @Test("high-risk decision with a fresh unlock commits")
    func highRiskUnlockedCommits() async {
        var prompted = false
        let ok = await ApprovalDecisionAuth.authorize(risk: .critical) { _ in
            prompted = true
        }
        #expect(ok)
        #expect(prompted)
    }
}
