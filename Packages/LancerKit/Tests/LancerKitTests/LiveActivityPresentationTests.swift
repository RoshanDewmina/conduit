import Testing
@testable import SessionFeature

struct LiveActivityPresentationTests {

#if os(iOS)

    typealias CS = LancerSessionAttributes.ContentState

    @available(iOS 16.2, *)
    @Test func needsYouBeatsEverything() {
        let s = CS(status: "connected", pendingApprovals: 2, isStreaming: true,
                   cost: 1.0, lastDecision: "approved")
        let p = LiveActivityPresentation.resolve(s, budget: nil)
        #expect(p.primary == .needsYou(count: 2))
    }

    @available(iOS 16.2, *)
    @Test func decisionLandedBeatsRunning() {
        let s = CS(status: "connected", pendingApprovals: 0, isStreaming: true, lastDecision: "rejected")
        #expect(LiveActivityPresentation.resolve(s, budget: nil).primary == .decisionLanded(approved: false))
    }

    @available(iOS 16.2, *)
    @Test func runningWhenStreamingOnly() {
        let s = CS(status: "connected", isStreaming: true)
        #expect(LiveActivityPresentation.resolve(s, budget: nil).primary == .running)
    }

    @available(iOS 16.2, *)
    @Test func idleWhenNothing() {
        let s = CS(status: "connected")
        #expect(LiveActivityPresentation.resolve(s, budget: nil).primary == .idle)
    }

    @available(iOS 16.2, *)
    @Test func costLevelEscalates() {
        let warn = CS(status: "connected", cost: 8.0)
        #expect(LiveActivityPresentation.resolve(warn, budget: 10.0).costLevel == .warning)
        let over = CS(status: "connected", cost: 10.0)
        #expect(LiveActivityPresentation.resolve(over, budget: 10.0).costLevel == .over)
        let normal = CS(status: "connected", cost: 1.0)
        #expect(LiveActivityPresentation.resolve(normal, budget: nil).costLevel == .normal)
        let none = CS(status: "connected")
        #expect(LiveActivityPresentation.resolve(none, budget: nil).costLevel == .none)
    }

    // MARK: - Risk tier resolution (Gap #2: a high/critical pending approval
    // must be distinguishable from a routine one)

    @available(iOS 16.2, *)
    @Test func riskTierNilWhenNoPendingApprovalRisk() {
        let s = CS(status: "connected", pendingApprovals: 1, pendingApprovalRisk: nil)
        #expect(LiveActivityPresentation.resolve(s, budget: nil).riskTier == nil)
    }

    @available(iOS 16.2, *)
    @Test func riskTierResolvesEachTier() {
        for (raw, expected) in [(0, LiveActivityRiskTier.low), (1, .medium), (2, .high), (3, .critical)] {
            let s = CS(status: "connected", pendingApprovals: 1, pendingApprovalRisk: raw)
            #expect(LiveActivityPresentation.resolve(s, budget: nil).riskTier == expected)
        }
    }

    @available(iOS 16.2, *)
    @Test func riskTierIsElevatedOnlyForHighAndCritical() {
        #expect(LiveActivityRiskTier.low.isElevated == false)
        #expect(LiveActivityRiskTier.medium.isElevated == false)
        #expect(LiveActivityRiskTier.high.isElevated == true)
        #expect(LiveActivityRiskTier.critical.isElevated == true)
    }

    @available(iOS 16.2, *)
    @Test func riskTierOutOfRangeRawValueResolvesNil() {
        // Defends against a future daemon-side scale change landing an
        // unrecognized raw value — must degrade to "no tier" rather than trap.
        let s = CS(status: "connected", pendingApprovals: 1, pendingApprovalRisk: 99)
        #expect(LiveActivityPresentation.resolve(s, budget: nil).riskTier == nil)
    }

    @available(iOS 16.2, *)
    @Test func riskTierIsNilOutsideNeedsYou() {
        // A stale pendingApprovalRisk value must not leak into an unrelated
        // primary state (e.g. after the count drops to 0 but the field lagged).
        let s = CS(status: "connected", pendingApprovals: 0, pendingApprovalRisk: 3, isStreaming: true)
        #expect(LiveActivityPresentation.resolve(s, budget: nil).riskTier == nil)
    }

#endif // os(iOS)
}
