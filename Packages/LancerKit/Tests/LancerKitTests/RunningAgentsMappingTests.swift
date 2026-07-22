import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("RunningAgentsMapping")
struct RunningAgentsMappingTests {

    @Test("providerLabel maps known vendors")
    func providerLabel() {
        #expect(RunningAgentsMapping.providerLabel("claudeCode") == "Claude Code")
        #expect(RunningAgentsMapping.providerLabel("codex") == "Codex")
        #expect(RunningAgentsMapping.providerLabel("kimi") == "Kimi")
        #expect(RunningAgentsMapping.providerLabel("opencode") == "OpenCode")
        #expect(RunningAgentsMapping.providerLabel("other") == "other")
    }

    @Test("rows drop historical and sort running first")
    func rowsFilterAndSort() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessions = [
            ObservedSession(
                sessionId: "hist",
                provider: "claudeCode",
                title: "Old",
                cwd: "/tmp/a",
                state: .historical,
                source: .transcriptObserved,
                lastActivity: now,
                messageCount: 1
            ),
            ObservedSession(
                sessionId: "idle",
                provider: "codex",
                title: "Idle one",
                cwd: "/tmp/b",
                state: .idle,
                source: .providerManaged,
                lastActivity: now.addingTimeInterval(-60),
                messageCount: 2
            ),
            ObservedSession(
                sessionId: "run",
                provider: "claudeCode",
                title: "Live",
                cwd: "/tmp/c",
                state: .working,
                source: .transcriptObserved,
                lastActivity: now.addingTimeInterval(-120),
                messageCount: 3
            ),
        ]
        let rows = RunningAgentsMapping.rows(from: sessions)
        #expect(rows.map(\.id) == ["run", "idle"])
        #expect(rows[0].isRunning)
        #expect(rows[0].stateLabel == "Running")
        #expect(!rows[1].isRunning)
        #expect(rows[1].stateLabel == "Idle")
    }

    @Test("displayTitle falls back to cwd basename")
    func displayTitleFallback() {
        let session = ObservedSession(
            sessionId: "s1",
            provider: "claudeCode",
            title: "  ",
            cwd: "/Users/dev/command-center",
            state: .idle,
            source: .transcriptObserved,
            lastActivity: .now,
            messageCount: 0
        )
        #expect(RunningAgentsMapping.displayTitle(session) == "command-center")
        #expect(RunningAgentsMapping.cwdSubtitle("/Users/dev/lancer-ios") == "lancer-ios")
    }

    @Test("totalRunningCount sums vendor runningCount")
    func totalRunningCount() {
        let snap = AgentStatusSnapshot(agents: [
            AgentVendorStatus(agent: "claudeCode", sessionCount: 2, runningCount: 1),
            AgentVendorStatus(agent: "codex", sessionCount: 1, runningCount: 2),
            AgentVendorStatus(agent: "kimi", sessionCount: 0, runningCount: nil),
        ])
        #expect(RunningAgentsMapping.totalRunningCount(from: snap) == 3)
        #expect(RunningAgentsMapping.totalRunningCount(from: nil) == 0)
    }
}

@Suite("RunningAgentsFreshness")
struct RunningAgentsFreshnessTests {

    @Test("poll interval is ~5s")
    func pollInterval() {
        #expect(RunningAgentsFreshness.pollIntervalNanoseconds == 5_000_000_000)
        #expect(RunningAgentsFreshness.consecutiveFailureLimit == 2)
    }

    @Test("No agents running only from fresh success with zero rows")
    func noAgentsOnlyWhenFresh() {
        var tracker = RunningAgentsFreshness.Tracker()
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(RunningAgentsFreshness.statusMessage(rowCount: 0, tracker: tracker, now: now) == nil)
        #expect(!RunningAgentsFreshness.mayClaimNoAgentsRunning(tracker: tracker))

        _ = RunningAgentsFreshness.recordSuccess(&tracker, at: now)
        #expect(RunningAgentsFreshness.mayClaimNoAgentsRunning(tracker: tracker))
        #expect(
            RunningAgentsFreshness.statusMessage(rowCount: 0, tracker: tracker, now: now)
                == "No agents running"
        )
        #expect(RunningAgentsFreshness.statusMessage(rowCount: 1, tracker: tracker, now: now) == nil)
    }

    @Test("one pre-first-success failure stays neutral (nil statusMessage)")
    func onePreFirstSuccessFailureIsNeutral() {
        var tracker = RunningAgentsFreshness.Tracker()
        let result = RunningAgentsFreshness.recordFailure(&tracker)
        #expect(result == .failing(count: 1))
        #expect(!tracker.isDegraded)
        #expect(!tracker.hasEverSucceeded)
        #expect(
            RunningAgentsFreshness.statusMessage(rowCount: 0, tracker: tracker, now: .now) == nil
        )
    }

    @Test("two consecutive failures yield degraded unreachable copy")
    func twoConsecutiveFailuresDegrade() {
        var tracker = RunningAgentsFreshness.Tracker()
        _ = RunningAgentsFreshness.recordFailure(&tracker)
        let entered = RunningAgentsFreshness.recordFailure(&tracker)
        #expect(entered == .enteredDegraded)
        #expect(tracker.isDegraded)
        let msg = RunningAgentsFreshness.statusMessage(rowCount: 0, tracker: tracker, now: .now)
        #expect(msg == "Machine unreachable — no successful update yet")
        #expect(msg != "No agents running")
    }

    @Test("connected host + refresh timeout ≠ Machine unreachable (P1.9 honesty)")
    func connectedHostRefreshTimeoutIsNotUnreachable() {
        var tracker = RunningAgentsFreshness.Tracker()
        _ = RunningAgentsFreshness.recordFailure(&tracker)
        _ = RunningAgentsFreshness.recordFailure(&tracker)
        #expect(tracker.isDegraded)

        let msg = RunningAgentsFreshness.statusMessage(
            rowCount: 0,
            tracker: tracker,
            now: .now,
            hostConnected: true
        )
        #expect(msg == "Couldn't refresh agents")
        #expect(msg?.contains("Machine unreachable") != true)
        #expect(msg != "No agents running")
    }

    @Test("connected host + stale refresh surfaces age without unreachable claim")
    func connectedHostDegradedSurfacesDataAge() {
        var tracker = RunningAgentsFreshness.Tracker()
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = RunningAgentsFreshness.recordSuccess(&tracker, at: t0)
        _ = RunningAgentsFreshness.recordFailure(&tracker)
        _ = RunningAgentsFreshness.recordFailure(&tracker)

        #expect(tracker.isDegraded)
        #expect(!RunningAgentsFreshness.mayClaimNoAgentsRunning(tracker: tracker))

        let msg = RunningAgentsFreshness.statusMessage(
            rowCount: 0,
            tracker: tracker,
            now: t0.addingTimeInterval(12),
            hostConnected: true
        )
        #expect(msg == "Couldn't refresh agents — last update 12s ago")
        #expect(msg?.contains("Machine unreachable") != true)
    }

    @Test("disconnected host keeps honest unreachable copy")
    func disconnectedHostKeepsUnreachableCopy() {
        var tracker = RunningAgentsFreshness.Tracker()
        _ = RunningAgentsFreshness.recordFailure(&tracker)
        _ = RunningAgentsFreshness.recordFailure(&tracker)

        let msg = RunningAgentsFreshness.statusMessage(
            rowCount: 0,
            tracker: tracker,
            now: .now,
            hostConnected: false
        )
        #expect(msg == "Machine unreachable — no successful update yet")
    }

    @Test("stale/unreachable surfaces data age — never all-clear")
    func degradedSurfacesDataAge() {
        var tracker = RunningAgentsFreshness.Tracker()
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = RunningAgentsFreshness.recordSuccess(&tracker, at: t0)
        _ = RunningAgentsFreshness.recordFailure(&tracker)
        _ = RunningAgentsFreshness.recordFailure(&tracker)

        #expect(tracker.isDegraded)
        #expect(!RunningAgentsFreshness.mayClaimNoAgentsRunning(tracker: tracker))

        let msg = RunningAgentsFreshness.statusMessage(
            rowCount: 0,
            tracker: tracker,
            now: t0.addingTimeInterval(12)
        )
        #expect(msg == "Machine unreachable — last update 12s ago")
    }

    @Test("recovery clears degraded and allows all-clear again")
    func recovery() {
        var tracker = RunningAgentsFreshness.Tracker()
        let t0 = Date(timeIntervalSince1970: 2_000)
        _ = RunningAgentsFreshness.recordSuccess(&tracker, at: t0)
        _ = RunningAgentsFreshness.recordFailure(&tracker)
        _ = RunningAgentsFreshness.recordFailure(&tracker)
        #expect(tracker.isDegraded)

        let recovered = RunningAgentsFreshness.recordSuccess(&tracker, at: t0.addingTimeInterval(5))
        #expect(recovered == .recovered)
        #expect(!tracker.isDegraded)
        #expect(
            RunningAgentsFreshness.statusMessage(rowCount: 0, tracker: tracker, now: t0.addingTimeInterval(5))
                == "No agents running"
        )
    }
}
