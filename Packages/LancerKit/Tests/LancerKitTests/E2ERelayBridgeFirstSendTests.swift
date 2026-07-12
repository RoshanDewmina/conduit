#if os(iOS)
import Testing
import Foundation
@testable import SessionFeature

/// REL-1 D: pins the pure readiness-gate check `sendDispatch` uses to decide
/// whether a timed-out first attempt gets ONE automatic retry. The race
/// itself (a dispatch lost in the window between socket-connected and
/// session-key derivation/peer ack) is proven live by the sim gate, not here —
/// this only pins the narrow decision function so it can't silently regress
/// into either "never retries" or "retries forever."
@Suite struct E2ERelayBridgeFirstSendTests {

    @Test("no prior re-key event is never a race")
    func nilLastReadyIsNeverARace() {
        #expect(E2ERelayBridge.isFirstSendRace(attemptedAt: Date(), lastReadyAt: nil) == false)
    }

    @Test("a timeout immediately after re-key is the race")
    func immediatelyAfterReadyIsARace() {
        let readyAt = Date()
        let attempted = readyAt.addingTimeInterval(0.5)
        #expect(E2ERelayBridge.isFirstSendRace(attemptedAt: attempted, lastReadyAt: readyAt) == true)
    }

    @Test("a timeout well outside the window is NOT the race")
    func outsideWindowIsNotARace() {
        let readyAt = Date()
        let attempted = readyAt.addingTimeInterval(E2ERelayBridge.firstSendRetryWindow + 1)
        #expect(E2ERelayBridge.isFirstSendRace(attemptedAt: attempted, lastReadyAt: readyAt) == false)
    }

    @Test("a send attempted BEFORE the re-key event (clock skew/ordering edge) is NOT the race")
    func beforeReadyIsNotARace() {
        let readyAt = Date()
        let attempted = readyAt.addingTimeInterval(-1)
        #expect(E2ERelayBridge.isFirstSendRace(attemptedAt: attempted, lastReadyAt: readyAt) == false)
    }

    @Test("exactly at the window boundary is excluded (half-open interval)")
    func atWindowBoundaryIsExcluded() {
        let readyAt = Date()
        let attempted = readyAt.addingTimeInterval(E2ERelayBridge.firstSendRetryWindow)
        #expect(E2ERelayBridge.isFirstSendRace(attemptedAt: attempted, lastReadyAt: readyAt) == false)
    }
}
#endif
