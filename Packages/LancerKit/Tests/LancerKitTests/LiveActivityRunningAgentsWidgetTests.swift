import Testing
import Foundation
@testable import LancerCore
@testable import SessionFeature

#if os(iOS)
@Suite("Live Activity → AgentStatusWidget snapshot")
struct LiveActivityRunningAgentsWidgetTests {

    @Test("running status maps to count/lines; idle clears")
    func writerTracksRunningThenIdle() {
        let suite = "la-running-agents-widget-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        LiveActivityRunningAgentsWidget.writeSnapshot(
            inputs: [
                .init(
                    agentName: "claudeCode",
                    hostName: "Roshans-MacBook-Air.local",
                    status: "running",
                    isStreaming: false
                ),
            ],
            suiteName: suite
        )

        #expect(defaults.integer(forKey: WidgetSnapshot.runningAgentsCountKey) == 1)
        #expect(
            defaults.stringArray(forKey: WidgetSnapshot.runningAgentsLinesKey)
                == ["Claude Code · Roshans-MacBook-Air.local"]
        )

        LiveActivityRunningAgentsWidget.writeSnapshot(inputs: [], suiteName: suite)
        #expect(defaults.integer(forKey: WidgetSnapshot.runningAgentsCountKey) == 0)
        #expect(defaults.stringArray(forKey: WidgetSnapshot.runningAgentsLinesKey) == nil)
    }

    @Test("isStreaming counts as running even when status is connected")
    func streamingCountsAsRunning() {
        #expect(
            LiveActivityRunningAgentsWidget.isAgentRunning(
                status: "connected",
                isStreaming: true
            )
        )
        #expect(
            !LiveActivityRunningAgentsWidget.isAgentRunning(
                status: "connected",
                isStreaming: false
            )
        )
        #expect(
            LiveActivityRunningAgentsWidget.isAgentRunning(
                status: "running",
                isStreaming: false
            )
        )
    }

    @Test("multiple running activities produce multiple lines")
    func multipleLines() {
        let lines = LiveActivityRunningAgentsWidget.widgetLines(from: [
            .init(agentName: "claudeCode", hostName: "HostA", status: "running", isStreaming: false),
            .init(agentName: "codex", hostName: "HostB", status: "connected", isStreaming: true),
            .init(agentName: "kimi", hostName: "HostC", status: "connected", isStreaming: false),
        ])
        #expect(lines == [
            "Claude Code · HostA",
            "Codex · HostB",
        ])
        #expect(
            LiveActivityRunningAgentsWidget.resolvedCount(from: [
                .init(agentName: "claudeCode", hostName: "HostA", status: "running", isStreaming: false),
                .init(agentName: "codex", hostName: "HostB", status: "connected", isStreaming: true),
                .init(agentName: "kimi", hostName: "HostC", status: "connected", isStreaming: false),
            ]) == 2
        )
    }
}
#endif
