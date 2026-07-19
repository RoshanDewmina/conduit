#if os(iOS)
import Foundation
import ActivityKit
import LancerCore
import WidgetKit

/// Maps Live Activity content → Home Screen `AgentStatusWidget` App Group keys.
///
/// The Agents widget previously only refreshed from `RunningAgentsSection`'s
/// daemon poll while that view was mounted. Live Activities (especially
/// push-to-start for observed/local runs) update independently via ActivityKit /
/// APNs, so the island could show `claudeCode · Running` while the widget
/// stayed at 0 forever. This mapper is the shared truth for "is an agent
/// run visible on the island?" → widget count/lines.
public enum LiveActivityRunningAgentsWidget: Sendable {

    public struct SnapshotInput: Equatable, Sendable {
        public let agentName: String?
        public let hostName: String
        public let status: String
        public let isStreaming: Bool

        public init(
            agentName: String?,
            hostName: String,
            status: String,
            isStreaming: Bool
        ) {
            self.agentName = agentName
            self.hostName = hostName
            self.status = status
            self.isStreaming = isStreaming
        }
    }

    /// Same statuses ShellLiveBridge / push-backend use for an in-flight run.
    public static func isAgentRunning(status: String, isStreaming: Bool) -> Bool {
        if isStreaming { return true }
        switch status.lowercased() {
        case "running", "working", "streaming", "awaitingapproval", "degraded":
            return true
        default:
            return false
        }
    }

    @available(iOS 16.2, *)
    public static func isAgentRunning(_ state: LancerSessionAttributes.ContentState) -> Bool {
        isAgentRunning(status: state.status, isStreaming: state.isStreaming)
    }

    public static func widgetLines(
        from inputs: [SnapshotInput],
        limit: Int = 4
    ) -> [String] {
        var lines: [String] = []
        for input in inputs where isAgentRunning(status: input.status, isStreaming: input.isStreaming) {
            let agent = displayAgentName(input.agentName)
            let host = input.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
            if host.isEmpty {
                lines.append(agent)
            } else {
                lines.append("\(agent) · \(host)")
            }
            if lines.count >= limit { break }
        }
        return lines
    }

    public static func resolvedCount(from inputs: [SnapshotInput]) -> Int {
        inputs.filter { isAgentRunning(status: $0.status, isStreaming: $0.isStreaming) }.count
    }

    /// Writes App Group keys + reloads `AgentStatusWidget`.
    /// - Parameter suiteName: Overridable for tests.
    public static func writeSnapshot(
        inputs: [SnapshotInput],
        suiteName: String = WidgetSnapshot.appGroupID
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let count = resolvedCount(from: inputs)
        let lines = widgetLines(from: inputs)
        defaults.set(count, forKey: WidgetSnapshot.runningAgentsCountKey)
        if lines.isEmpty {
            defaults.removeObject(forKey: WidgetSnapshot.runningAgentsLinesKey)
        } else {
            defaults.set(lines, forKey: WidgetSnapshot.runningAgentsLinesKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: WidgetSnapshot.runningAgentsUpdatedKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "AgentStatusWidget")
    }

    /// System ActivityKit activities — includes push-to-start LAs the in-process
    /// manager dictionary never saw (app was closed when the run started).
    @available(iOS 16.2, *)
    @MainActor
    public static func syncFromSystemActivities(
        suiteName: String = WidgetSnapshot.appGroupID
    ) {
        let inputs = Activity<LancerSessionAttributes>.activities.map { activity in
            SnapshotInput(
                agentName: activity.content.state.agentName,
                hostName: activity.attributes.hostName,
                status: activity.content.state.status,
                isStreaming: activity.content.state.isStreaming
            )
        }
        writeSnapshot(inputs: inputs, suiteName: suiteName)
    }

    private static func displayAgentName(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Agent" }
        switch trimmed {
        case "claudeCode": return "Claude Code"
        case "codex": return "Codex"
        case "kimi": return "Kimi"
        case "opencode": return "OpenCode"
        case "pi": return "Pi"
        default: return trimmed
        }
    }
}
#endif
