import Foundation
import Testing
@testable import AppFeature

@Suite("LivePollPolicy")
struct LivePollPolicyTests {

    @Test("poll interval is ~1s")
    func pollInterval() {
        #expect(LivePollPolicy.pollIntervalNanoseconds == 1_000_000_000)
        #expect(LivePollPolicy.consecutiveFailureLimit == 5)
    }

    @Test("runningPublish stays working until first non-empty chunk")
    func runningPublish() {
        #expect(LivePollPolicy.runningPublish(assistantText: "") == .working)
        #expect(LivePollPolicy.runningPublish(assistantText: "Hi") == .streaming)
    }

    @Test("refresh success clears failure streak and exits degraded")
    func refreshSuccessRecovers() {
        var tracker = LivePollPolicy.Tracker(
            consecutiveRefreshFailures: 5,
            lastSuccessfulRefreshAt: nil,
            isDegraded: true
        )
        let now = Date(timeIntervalSince1970: 1_000)
        let result = LivePollPolicy.recordRefreshSuccess(&tracker, at: now)
        #expect(result == .recovered)
        #expect(tracker.consecutiveRefreshFailures == 0)
        #expect(tracker.isDegraded == false)
        #expect(tracker.lastSuccessfulRefreshAt == now)
    }

    @Test("refresh success while healthy stays healthy")
    func refreshSuccessHealthy() {
        var tracker = LivePollPolicy.Tracker()
        let now = Date(timeIntervalSince1970: 50)
        let result = LivePollPolicy.recordRefreshSuccess(&tracker, at: now)
        #expect(result == .healthy)
        #expect(tracker.lastSuccessfulRefreshAt == now)
        #expect(tracker.isDegraded == false)
    }

    @Test("failures under limit do not degrade")
    func failuresUnderLimit() {
        var tracker = LivePollPolicy.Tracker()
        let now = Date(timeIntervalSince1970: 10)
        for expected in 1..<LivePollPolicy.consecutiveFailureLimit {
            let result = LivePollPolicy.recordRefreshFailure(&tracker, at: now)
            #expect(result == .failing(count: expected))
            #expect(tracker.isDegraded == false)
        }
        #expect(tracker.consecutiveRefreshFailures == LivePollPolicy.consecutiveFailureLimit - 1)
    }

    @Test("Nth consecutive failure enters degraded and stays there")
    func entersAndStaysDegraded() {
        var tracker = LivePollPolicy.Tracker()
        let now = Date(timeIntervalSince1970: 20)
        for _ in 1..<LivePollPolicy.consecutiveFailureLimit {
            _ = LivePollPolicy.recordRefreshFailure(&tracker, at: now)
        }
        let entered = LivePollPolicy.recordRefreshFailure(&tracker, at: now)
        #expect(entered == .enteredDegraded)
        #expect(tracker.isDegraded == true)
        #expect(tracker.consecutiveRefreshFailures == LivePollPolicy.consecutiveFailureLimit)

        let still = LivePollPolicy.recordRefreshFailure(&tracker, at: now)
        #expect(still == .stillDegraded)
        #expect(tracker.isDegraded == true)
    }

    @Test("degraded message surfaces data age; never invents working")
    func degradedMessage() {
        let now = Date(timeIntervalSince1970: 200)
        #expect(
            LivePollPolicy.degradedMessage(lastSuccessfulRefreshAt: nil, now: now)
                == "Machine unreachable — no successful update yet"
        )
        let last = Date(timeIntervalSince1970: 170)
        #expect(
            LivePollPolicy.degradedMessage(lastSuccessfulRefreshAt: last, now: now)
                == "Machine unreachable — last update 30s ago"
        )
        // Age floors at 0 — never negative.
        #expect(
            LivePollPolicy.degradedMessage(lastSuccessfulRefreshAt: now.addingTimeInterval(5), now: now)
                == "Machine unreachable — last update 0s ago"
        )
    }

    @Test("success after partial failures resets before degrade threshold")
    func successResetsStreak() {
        var tracker = LivePollPolicy.Tracker()
        let t0 = Date(timeIntervalSince1970: 0)
        for _ in 0..<3 {
            _ = LivePollPolicy.recordRefreshFailure(&tracker, at: t0)
        }
        #expect(tracker.consecutiveRefreshFailures == 3)
        _ = LivePollPolicy.recordRefreshSuccess(&tracker, at: t0.addingTimeInterval(1))
        #expect(tracker.consecutiveRefreshFailures == 0)
        #expect(tracker.isDegraded == false)

        // Need a full fresh streak of 5 to degrade again.
        for _ in 0..<4 {
            let result = LivePollPolicy.recordRefreshFailure(&tracker, at: t0)
            guard case .failing = result else {
                Issue.record("expected failing before limit"); return
            }
        }
        #expect(tracker.isDegraded == false)
    }
}
