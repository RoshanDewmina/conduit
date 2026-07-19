import Foundation

/// Pure poll / degrade policy for `ShellLiveBridge.pollUntilTerminal`.
/// OS-agnostic so unit tests can drive it without the iOS-only bridge.
public enum LivePollPolicy: Sendable {
    /// ~1s tick while a run is in flight — refresh every tick so partial
    /// `assistantText` reaches the UI promptly.
    public static let pollIntervalNanoseconds: UInt64 = 1_000_000_000

    /// Idle tick for the observed-session live follow (desktop activity
    /// appearing in an open thread). Slightly slower than the in-flight poll —
    /// each tick is a relay round trip even when nothing changed.
    public static let observedFollowIntervalNanoseconds: UInt64 = 1_500_000_000

    /// Consecutive `refreshConversation` failures before entering degraded.
    public static let consecutiveFailureLimit = 5

    /// Consecutive empty observed-follow polls (~`observedFollowIntervalNanoseconds`
    /// apart) before `ShellLiveBridge.isObservedSessionWorking` drops back to
    /// false. Debounces the natural pause between tool calls (thinking,
    /// waiting on a slow command) so the working indicator doesn't flicker
    /// off between bursts of activity.
    public static let observedFollowIdleGracePolls = 4

    public struct Tracker: Equatable, Sendable {
        public var consecutiveRefreshFailures: Int
        public var lastSuccessfulRefreshAt: Date?
        public var isDegraded: Bool

        public init(
            consecutiveRefreshFailures: Int = 0,
            lastSuccessfulRefreshAt: Date? = nil,
            isDegraded: Bool = false
        ) {
            self.consecutiveRefreshFailures = consecutiveRefreshFailures
            self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
            self.isDegraded = isDegraded
        }
    }

    public enum RefreshResult: Equatable, Sendable {
        case healthy
        /// Failures are accumulating but still under the degrade threshold.
        case failing(count: Int)
        case enteredDegraded
        case stillDegraded
        case recovered
    }

    public enum RunningPublish: Equatable, Sendable {
        /// No assistant text yet — keep the working indicator.
        case working
        /// Partial text available — stream it.
        case streaming
    }

    /// Record a successful host refresh. Clears the failure streak and
    /// exits degraded if we were there.
    @discardableResult
    public static func recordRefreshSuccess(_ tracker: inout Tracker, at now: Date) -> RefreshResult {
        let wasDegraded = tracker.isDegraded
        tracker.consecutiveRefreshFailures = 0
        tracker.lastSuccessfulRefreshAt = now
        tracker.isDegraded = false
        return wasDegraded ? .recovered : .healthy
    }

    /// Record a failed host refresh. Enters / stays degraded once
    /// `consecutiveFailureLimit` failures accumulate.
    @discardableResult
    public static func recordRefreshFailure(_ tracker: inout Tracker, at _: Date) -> RefreshResult {
        tracker.consecutiveRefreshFailures += 1
        if tracker.consecutiveRefreshFailures >= consecutiveFailureLimit {
            if tracker.isDegraded {
                return .stillDegraded
            }
            tracker.isDegraded = true
            return .enteredDegraded
        }
        return .failing(count: tracker.consecutiveRefreshFailures)
    }

    /// Honest degraded copy — never claims the run is still progressing
    /// when we have no fresh host data. Surfaces data age when known.
    public static func degradedMessage(lastSuccessfulRefreshAt: Date?, now: Date) -> String {
        guard let lastSuccessfulRefreshAt else {
            return "Machine unreachable — no successful update yet"
        }
        let seconds = max(0, Int(now.timeIntervalSince(lastSuccessfulRefreshAt).rounded(.down)))
        return "Machine unreachable — last update \(seconds)s ago"
    }

    /// What the UI should publish for a still-`.running` turn after a
    /// healthy refresh (or a local re-read while not degraded).
    public static func runningPublish(assistantText: String) -> RunningPublish {
        assistantText.isEmpty ? .working : .streaming
    }
}
