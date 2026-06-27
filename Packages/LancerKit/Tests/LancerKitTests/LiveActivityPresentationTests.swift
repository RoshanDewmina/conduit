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

#endif // os(iOS)
}
