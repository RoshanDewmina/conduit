import Testing
import Foundation
@testable import LancerCore
@testable import AppFeature

#if os(iOS)
/// Home Screen `AgentStatusWidget` must reflect daemon running agents, not
/// phone session `connected` status. Writer is exercised with an injectable
/// UserDefaults suite (same convention as pending-approvals writer tests).
@Suite("AgentStatusWidget running-agents snapshot writer")
struct RunningAgentsWidgetSnapshotWriterTests {

    @Test("writes count and lines from running rows; clears lines at zero")
    func writerTracksRunningThenIdle() {
        let suite = "running-agents-widget-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let rows = RunningAgentsMapping.rows(from: [
            ObservedSession(
                sessionId: "run",
                provider: "claudeCode",
                title: "Live",
                cwd: "/Users/dev/lancer",
                state: .working,
                source: .transcriptObserved,
                lastActivity: now,
                messageCount: 1
            ),
        ])

        RunningAgentsMapping.writeRunningAgentsWidgetSnapshot(
            rows: rows,
            status: nil,
            hostName: "Studio",
            suiteName: suite
        )

        #expect(defaults.integer(forKey: WidgetSnapshot.runningAgentsCountKey) == 1)
        #expect(
            defaults.stringArray(forKey: WidgetSnapshot.runningAgentsLinesKey)
                == ["Claude Code · lancer · Studio"]
        )
        #expect(defaults.double(forKey: WidgetSnapshot.runningAgentsUpdatedKey) > 0)

        RunningAgentsMapping.writeRunningAgentsWidgetSnapshot(
            rows: [],
            status: AgentStatusSnapshot(agents: []),
            hostName: "Studio",
            suiteName: suite
        )

        #expect(defaults.integer(forKey: WidgetSnapshot.runningAgentsCountKey) == 0)
        #expect(defaults.stringArray(forKey: WidgetSnapshot.runningAgentsLinesKey) == nil)
    }

    @Test("status-only runningCount still populates the widget")
    func statusOnlyFallback() {
        let suite = "running-agents-widget-status-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let status = AgentStatusSnapshot(agents: [
            AgentVendorStatus(agent: "codex", sessionCount: 2, runningCount: 2),
        ])
        RunningAgentsMapping.writeRunningAgentsWidgetSnapshot(
            rows: [],
            status: status,
            hostName: nil,
            suiteName: suite
        )

        #expect(defaults.integer(forKey: WidgetSnapshot.runningAgentsCountKey) == 2)
        #expect(
            defaults.stringArray(forKey: WidgetSnapshot.runningAgentsLinesKey)
                == ["Codex · 2 running"]
        )
    }
}
#endif
