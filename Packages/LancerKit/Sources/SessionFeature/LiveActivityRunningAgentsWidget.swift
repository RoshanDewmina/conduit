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
///
/// ActivityKit can briefly (or durably) expose two Activities for one logical
/// run — in-process ShellLiveBridge start plus a push-to-start island for the
/// same host/agent. Count/lines are deduped by `(agent, host)` so the Home
/// Screen widget never shows "2 agents" with identical `Claude Code · host`
/// lines for a single island.
public enum LiveActivityRunningAgentsWidget: Sendable {

    public struct SnapshotInput: Equatable, Sendable {
        public let agentName: String?
        public let hostName: String
        /// Stable host identity when available (`LancerSessionAttributes.hostID`).
        /// Used for dedupe when display names differ (e.g. short vs FQDN).
        public let hostID: String?
        public let status: String
        public let isStreaming: Bool

        public init(
            agentName: String?,
            hostName: String,
            hostID: String? = nil,
            status: String,
            isStreaming: Bool
        ) {
            self.agentName = agentName
            self.hostName = hostName
            self.hostID = hostID
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

    /// Collapse duplicate ActivityKit rows that represent the same logical run.
    public static func deduplicatedInputs(_ inputs: [SnapshotInput]) -> [SnapshotInput] {
        var order: [String] = []
        var best: [String: SnapshotInput] = [:]
        for input in inputs {
            let key = dedupeKey(for: input)
            if best[key] == nil {
                order.append(key)
                best[key] = input
                continue
            }
            if prefers(input, over: best[key]!) {
                best[key] = input
            }
        }
        return order.compactMap { best[$0] }
    }

    public static func widgetLines(
        from inputs: [SnapshotInput],
        limit: Int = 4
    ) -> [String] {
        var lines: [String] = []
        var seenLines = Set<String>()
        for input in deduplicatedInputs(inputs)
        where isAgentRunning(status: input.status, isStreaming: input.isStreaming) {
            let line = displayLine(for: input)
            guard seenLines.insert(line).inserted else { continue }
            lines.append(line)
            if lines.count >= limit { break }
        }
        return lines
    }

    public static func resolvedCount(from inputs: [SnapshotInput]) -> Int {
        deduplicatedInputs(inputs).filter {
            isAgentRunning(status: $0.status, isStreaming: $0.isStreaming)
        }.count
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
                hostID: activity.attributes.hostID,
                status: activity.content.state.status,
                isStreaming: activity.content.state.isStreaming
            )
        }
        writeSnapshot(inputs: inputs, suiteName: suiteName)
    }

    // MARK: - Private

    private static func displayLine(for input: SnapshotInput) -> String {
        let agent = displayAgentName(input.agentName)
        let host = input.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            return agent
        }
        return "\(agent) · \(host)"
    }

    private static func dedupeKey(for input: SnapshotInput) -> String {
        let agent = normalizedAgentKey(input.agentName)
        let hostID = (input.hostID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !hostID.isEmpty {
            return "\(agent)|id:\(hostID)"
        }
        return "\(agent)|host:\(normalizedHostKey(input.hostName))"
    }

    private static func normalizedAgentKey(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "", "agent": return "agent"
        case "claudecode", "claude code", "claude": return "claudecode"
        case "opencode", "open code": return "opencode"
        default: return trimmed
        }
    }

    private static func normalizedHostKey(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasSuffix(".local") {
            host.removeLast(".local".count)
        }
        return host
    }

    /// Prefer the input that more clearly represents an in-flight run.
    private static func prefers(_ lhs: SnapshotInput, over rhs: SnapshotInput) -> Bool {
        let lhsRunning = isAgentRunning(status: lhs.status, isStreaming: lhs.isStreaming)
        let rhsRunning = isAgentRunning(status: rhs.status, isStreaming: rhs.isStreaming)
        if lhsRunning != rhsRunning { return lhsRunning }
        if lhs.isStreaming != rhs.isStreaming { return lhs.isStreaming }
        // Prefer richer agent labels when one side is empty.
        let lhsAgent = (lhs.agentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsAgent = (rhs.agentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if lhsAgent.isEmpty != rhsAgent.isEmpty { return !lhsAgent.isEmpty }
        return false
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
