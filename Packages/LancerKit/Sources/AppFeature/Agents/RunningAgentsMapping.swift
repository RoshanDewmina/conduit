import Foundation
import LancerCore

/// Pure mapping + freshness rules for the Workspaces "Agents" section.
/// OS-agnostic so host `swift test` can drive it without the iOS-only UI.
public enum RunningAgentsMapping: Sendable {

    public struct Row: Identifiable, Equatable, Hashable, Sendable {
        public let id: String
        public let sessionId: String
        public let provider: String
        public let providerLabel: String
        public let title: String
        public let cwd: String
        public let state: ObservedSessionState
        public let stateLabel: String
        public let isRunning: Bool
        public let lastActivity: Date
        public let systemImage: String

        public init(
            id: String,
            sessionId: String,
            provider: String,
            providerLabel: String,
            title: String,
            cwd: String,
            state: ObservedSessionState,
            stateLabel: String,
            isRunning: Bool,
            lastActivity: Date,
            systemImage: String
        ) {
            self.id = id
            self.sessionId = sessionId
            self.provider = provider
            self.providerLabel = providerLabel
            self.title = title
            self.cwd = cwd
            self.state = state
            self.stateLabel = stateLabel
            self.isRunning = isRunning
            self.lastActivity = lastActivity
            self.systemImage = systemImage
        }

        public init(session: ObservedSession) {
            let isRunning = RunningAgentsMapping.isRunning(session.state)
            self.init(
                id: session.sessionId,
                sessionId: session.sessionId,
                provider: session.provider,
                providerLabel: RunningAgentsMapping.providerLabel(session.provider),
                title: RunningAgentsMapping.displayTitle(session),
                cwd: session.cwd,
                state: session.state,
                stateLabel: RunningAgentsMapping.stateLabel(session.state),
                isRunning: isRunning,
                lastActivity: session.lastActivity,
                systemImage: RunningAgentsMapping.systemImage(for: session.provider)
            )
        }
    }

    /// Live / observed sessions the Agents section should list.
    /// Drops purely historical rows so the section stays a "what's on the machine" surface.
    public static func isListable(_ session: ObservedSession) -> Bool {
        switch session.state {
        case .historical:
            return false
        case .working, .waitingForInput, .idle, .completed, .recentlyActive, .unknown:
            return true
        }
    }

    public static func isRunning(_ state: ObservedSessionState) -> Bool {
        switch state {
        case .working, .waitingForInput:
            return true
        case .idle, .completed, .recentlyActive, .historical, .unknown:
            return false
        }
    }

    public static func rows(from sessions: [ObservedSession]) -> [Row] {
        sessions
            .filter(isListable)
            .map(Row.init(session:))
            .sorted { lhs, rhs in
                if lhs.isRunning != rhs.isRunning { return lhs.isRunning && !rhs.isRunning }
                return lhs.lastActivity > rhs.lastActivity
            }
    }

    public static func providerLabel(_ provider: String) -> String {
        switch provider {
        case "claudeCode": return "Claude Code"
        case "codex": return "Codex"
        case "kimi": return "Kimi"
        case "opencode": return "OpenCode"
        case "cursor": return "Cursor"
        case "pi": return "Pi"
        default: return provider
        }
    }

    public static func stateLabel(_ state: ObservedSessionState) -> String {
        switch state {
        case .working: return "Running"
        case .waitingForInput: return "Waiting"
        case .idle: return "Idle"
        case .completed: return "Completed"
        case .recentlyActive: return "Recent"
        case .historical: return "Historical"
        case .unknown: return "Unknown"
        }
    }

    public static func systemImage(for provider: String) -> String {
        switch provider {
        case "claudeCode": return "sparkles"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "opencode": return "terminal"
        case "kimi": return "moon.stars"
        case "cursor": return "hammer"
        case "pi": return "circle.hexagongrid"
        default: return "cpu"
        }
    }

    public static func displayTitle(_ session: ObservedSession) -> String {
        let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let base = (session.cwd as NSString).lastPathComponent
        return base.isEmpty ? session.sessionId : base
    }

    public static func cwdSubtitle(_ cwd: String) -> String {
        let base = (cwd as NSString).lastPathComponent
        return base.isEmpty ? cwd : base
    }

    /// Sum of per-vendor `runningCount` from `agent.status` (nil counts as 0).
    public static func totalRunningCount(from snapshot: AgentStatusSnapshot?) -> Int {
        guard let snapshot else { return 0 }
        return snapshot.agents.reduce(0) { $0 + ($1.runningCount ?? 0) }
    }
}

/// Poll / degrade policy for the Agents section (~5s while visible).
public enum RunningAgentsFreshness: Sendable {
    public static let pollIntervalNanoseconds: UInt64 = 5_000_000_000
    /// Two missed 5s ticks (~10s) before we refuse to claim "No agents running".
    public static let consecutiveFailureLimit = 2

    public struct Tracker: Equatable, Sendable {
        public var consecutiveFailures: Int
        public var lastSuccessfulFetchAt: Date?
        public var isDegraded: Bool
        public var hasEverSucceeded: Bool

        public init(
            consecutiveFailures: Int = 0,
            lastSuccessfulFetchAt: Date? = nil,
            isDegraded: Bool = false,
            hasEverSucceeded: Bool = false
        ) {
            self.consecutiveFailures = consecutiveFailures
            self.lastSuccessfulFetchAt = lastSuccessfulFetchAt
            self.isDegraded = isDegraded
            self.hasEverSucceeded = hasEverSucceeded
        }
    }

    public enum RefreshResult: Equatable, Sendable {
        case healthy
        case failing(count: Int)
        case enteredDegraded
        case stillDegraded
        case recovered
    }

    @discardableResult
    public static func recordSuccess(_ tracker: inout Tracker, at now: Date) -> RefreshResult {
        let wasDegraded = tracker.isDegraded
        tracker.consecutiveFailures = 0
        tracker.lastSuccessfulFetchAt = now
        tracker.isDegraded = false
        tracker.hasEverSucceeded = true
        return wasDegraded ? .recovered : .healthy
    }

    @discardableResult
    public static func recordFailure(_ tracker: inout Tracker) -> RefreshResult {
        tracker.consecutiveFailures += 1
        if tracker.consecutiveFailures >= consecutiveFailureLimit {
            if tracker.isDegraded {
                return .stillDegraded
            }
            tracker.isDegraded = true
            return .enteredDegraded
        }
        return .failing(count: tracker.consecutiveFailures)
    }

    /// Honest empty / degraded copy.
    /// "No agents running" only when we have a fresh successful fetch and zero rows.
    /// Pre-first-success stays neutral (`nil`) until `consecutiveFailureLimit` degrades.
    public static func statusMessage(
        rowCount: Int,
        tracker: Tracker,
        now: Date
    ) -> String? {
        if tracker.isDegraded {
            return degradedMessage(lastSuccessfulFetchAt: tracker.lastSuccessfulFetchAt, now: now)
        }
        guard tracker.hasEverSucceeded else { return nil }
        if rowCount == 0 {
            return "No agents running"
        }
        return nil
    }

    public static func degradedMessage(lastSuccessfulFetchAt: Date?, now: Date) -> String {
        guard let lastSuccessfulFetchAt else {
            return "Machine unreachable — no successful update yet"
        }
        let seconds = max(0, Int(now.timeIntervalSince(lastSuccessfulFetchAt).rounded(.down)))
        return "Machine unreachable — last update \(seconds)s ago"
    }

    /// True when it is honest to show the all-clear empty string.
    public static func mayClaimNoAgentsRunning(tracker: Tracker) -> Bool {
        tracker.hasEverSucceeded && !tracker.isDegraded
    }
}
