// Tier 1.5.1 — iOS Live Activity for an active Lancer session.
//
// Surfaces "<agent> running on <host> — N pending" on the lock screen
// and Dynamic Island while the user is connected. Termius leads their
// AI-on-mobile marketing with Live Activities; Lancer matches it.
//
// Lifecycle:
//   • SessionViewModel.connect() success → LancerLiveActivityManager.start(...)
//   • ApprovalRepository.upserts → manager.updatePendingApprovals(_:)
//   • SessionViewModel.disconnect() → manager.end(activityKey:) for that session only
//
// Keying: one Live Activity per active *session* (SessionViewModel.sessionID),
// not per host — two concurrent chat tabs connected to the same host each get
// their own Activity, so neither one's lock-screen progress silently overwrites
// the other's.
//
// Push-driven (Phase 1):
//   • Activity is requested with pushType: .token so iOS can update it
//     while the app is away. pushTokenUpdates delivers the per-activity
//     token; register it with push-backend so the backend can send
//     APNs content-state payloads even when the app is suspended.
//   • pushToStartToken / pushToStartTokenUpdates let the backend START
//     a new activity via APNs when none is running (app fully closed).
//   • frequentPushesEnabled is observed; the backend is told when it
//     changes so it can throttle priority-10 pushes appropriately.
//
// Requires:
//   • NSSupportsLiveActivities = YES in Info.plist (set in project.yml)
//   • NSSupportsLiveActivitiesFrequentUpdates = YES for frequent pushes
//   • A Widget Extension target that imports this file and renders the
//     `ActivityAttributes`/`ContentState` — see LancerLiveActivityWidget
//     (added via `xcodegen generate` once the widget target is declared).

import Foundation
#if os(iOS)
import ActivityKit

// Activity<T> predates Swift 6 concurrency and lacks Sendable annotation in the
// iOS SDK headers. We own all access through @MainActor so this is safe.
@available(iOS 16.2, *)
extension Activity: @retroactive @unchecked Sendable {}
#endif

#if os(iOS)

@available(iOS 16.2, *)
public struct LancerSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String           // "connected" / "reconnecting" / "suspended"
        public var pendingApprovals: Int
        public var agentName: String?       // "Claude Code" when an agent is running
        public var pendingApprovalID: String?
        /// Risk of the pending approval named by `pendingApprovalID`, using the same
        /// 0…3 scale as the daemon (`riskToInt` in daemon/lancerd/hook.go and
        /// `Approval.Risk.rawValue`): 0=low, 1=medium, 2=high, 3=critical. nil when
        /// there's no pending approval. Lets the widget visually distinguish a
        /// high/critical approval from a routine one instead of rendering them
        /// identically.
        public var pendingApprovalRisk: Int?
        public var isStreaming: Bool        // agent is actively executing (drives the blue glyph)
        public var cost: Double?            // accumulated cost in USD
        /// Transient confirmation of a just-resolved decision: "approved" / "rejected" / nil.
        /// Pushed once by push-backend after a decision resolves (incl. the cold path), shown
        /// as a ✓ for ~4s, then cleared. nil in steady state.
        public var lastDecision: String?
        public var lastUpdate: Date

        public init(
            status: String,
            pendingApprovals: Int = 0,
            agentName: String? = nil,
            pendingApprovalID: String? = nil,
            pendingApprovalRisk: Int? = nil,
            isStreaming: Bool = false,
            cost: Double? = nil,
            lastDecision: String? = nil,
            lastUpdate: Date = .now
        ) {
            self.status = status
            self.pendingApprovals = pendingApprovals
            self.agentName = agentName
            self.pendingApprovalID = pendingApprovalID
            self.pendingApprovalRisk = pendingApprovalRisk
            self.isStreaming = isStreaming
            self.cost = cost
            self.lastDecision = lastDecision
            self.lastUpdate = lastUpdate
        }
    }

    public let hostName: String
    public let hostID: String

    public init(hostName: String, hostID: String) {
        self.hostName = hostName
        self.hostID = hostID
    }
}

/// Called by the token-monitoring tasks when a new activity or push-to-start
/// token is available. The registration closure POSTs to push-backend.
public typealias ActivityTokenRegistration = @Sendable (
    _ sessionID: String,
    _ activityToken: String,
    _ isPushToStart: Bool
) async -> Void

/// Thin wrapper around ActivityKit for Lancer's session activities. One
/// activity per active *session* (keyed by `SessionViewModel.sessionID`, not
/// `hostID`), so two concurrent sessions against the same host each get their
/// own Activity instead of the second silently overwriting the first's
/// content. Calling `start(...)` again for an existing `activityKey` updates
/// its content rather than creating a duplicate.
///
/// Push path: activities are requested with pushType: .token so iOS delivers
/// APNs content-state updates even when the app is suspended. The caller
/// supplies a `tokenRegistration` closure (wired in LancerApp/AppRoot) that
/// forwards new tokens to push-backend.
@available(iOS 16.2, *)
@MainActor
public final class LancerLiveActivityManager {
    public static let shared = LancerLiveActivityManager()

    private var activities: [String: Activity<LancerSessionAttributes>] = [:]
    // Last content pushed per activityKey, so partial updates (e.g. approval
    // count only) can preserve the other fields instead of resetting them.
    private var lastContent: [String: LancerSessionAttributes.ContentState] = [:]
    // Token-monitoring tasks keyed by activityKey so they're cancelled on end().
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    // Push-to-start token monitor (one per app lifetime).
    private var pushToStartTask: Task<Void, Never>?

    /// Closure called when an activity or push-to-start push token is ready.
    /// Set by LancerApp at launch (alongside the APNs device-token path).
    public var tokenRegistration: ActivityTokenRegistration?

    private init() {}

    /// True when the OS allows Live Activities (user toggle in Settings →
    /// Notifications → Lancer). Calls are safe when false — they no-op.
    public var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// True when the OS allows frequent ActivityKit push updates (controlled
    /// by Settings → Notifications → Lancer). Send to push-backend so it can
    /// set apns-priority 5 vs 10 accordingly.
    public var frequentPushesEnabled: Bool {
        ActivityAuthorizationInfo().frequentPushesEnabled
    }

    /// Start a Live Activity for a session, or update its content if one is
    /// already running for that session.
    ///
    /// - Parameters:
    ///   - activityKey: Per-session dictionary key (stringified
    ///     `SessionViewModel.sessionID`). Distinct concurrent sessions against
    ///     the same host must pass distinct keys so each gets its own Activity.
    ///   - deviceSessionID: The device/app-level id (`DeviceIdentity.sessionID()`)
    ///     used only to register push tokens with push-backend — unrelated to
    ///     `activityKey`.
    public func start(
        hostID: String,
        hostName: String,
        activityKey: String,
        deviceSessionID: String,
        status: String = "connected",
        agentName: String? = nil,
        pendingApprovals: Int = 0,
        pendingApprovalID: String? = nil,
        pendingApprovalRisk: Int? = nil
    ) async {
        guard isEnabled else { return }

        let content = LancerSessionAttributes.ContentState(
            status: status,
            pendingApprovals: pendingApprovals,
            agentName: agentName,
            pendingApprovalID: pendingApprovalID,
            pendingApprovalRisk: pendingApprovalRisk,
            cost: lastContent[activityKey]?.cost
        )

        if let existing = activities[activityKey] {
            await existing.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
            lastContent[activityKey] = content
            return
        }

        let attrs = LancerSessionAttributes(hostName: hostName, hostID: hostID)
        do {
            let activity = try Activity.request(
                attributes: attrs,
                content: .init(state: content, staleDate: Date().addingTimeInterval(1800)),
                pushType: .token
            )
            activities[activityKey] = activity
            lastContent[activityKey] = content
            startTokenMonitor(for: activity, activityKey: activityKey, deviceSessionID: deviceSessionID)
        } catch {
            // ActivityKit refuses (off in Settings, system busy, etc.) —
            // silent failure is correct; the in-app inbox still works.
        }
    }

    /// Begin observing push-to-start tokens so push-backend can remotely
    /// START a Live Activity when none is running (app fully closed).
    /// Call once at app launch from LancerApp alongside APNs token setup.
    public func startPushToStartMonitor(sessionID: String) {
        guard pushToStartTask == nil else { return }
        guard #available(iOS 17.2, *) else { return }
        pushToStartTask = Task { [weak self] in
            for await tokenData in Activity<LancerSessionAttributes>.pushToStartTokenUpdates {
                let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
                await self?.tokenRegistration?(sessionID, hexToken, true)
            }
        }
    }

    /// Update an existing activity's content. No-ops if no activity is
    /// running for the given session.
    public func update(
        activityKey: String,
        status: String,
        agentName: String? = nil,
        pendingApprovals: Int = 0,
        pendingApprovalID: String? = nil,
        pendingApprovalRisk: Int? = nil
    ) async {
        guard let activity = activities[activityKey] else { return }
        let content = LancerSessionAttributes.ContentState(
            status: status,
            pendingApprovals: pendingApprovals,
            agentName: agentName,
            pendingApprovalID: pendingApprovalID,
            pendingApprovalRisk: pendingApprovalRisk,
            cost: lastContent[activityKey]?.cost
        )
        await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
        lastContent[activityKey] = content
    }

    /// Update the pending-approval count on every running activity, preserving
    /// each one's other fields. This is the glanceable signal the Dynamic Island
    /// exists for, so it must stay live while the app is backgrounded. No-ops
    /// when no activities are running.
    ///
    /// KNOWN FOLLOW-UP: `count` is the fleet-wide pending-approval count, so
    /// every session's activity (even ones with zero approvals of their own)
    /// shows the same number. Attributing approvals to a specific session/host
    /// is a separate, bigger change — not solved here.
    ///
    /// - Parameter highestRisk: the most severe risk (0…3, same scale as
    ///   `ContentState.pendingApprovalRisk`) among the current fleet-wide
    ///   pending approvals, or nil when `count` is 0. Same fleet-wide caveat
    ///   as `count` above — not attributed to a specific session/host.
    public func updatePendingApprovals(_ count: Int, highestRisk: Int? = nil) async {
        for (activityKey, activity) in activities {
            guard let base = lastContent[activityKey] else { continue }
            // Construct a fresh value (not a mutated copy of stored actor state)
            // so it forms its own isolation region and is safe to send.
            //
            // MAJOR-14: preserve `pendingApprovalID` — the Live Activity / Dynamic
            // Island Approve/Reject buttons only render when it is non-empty, so
            // dropping it here stripped the buttons exactly when an approval was
            // pending. Carry it through whenever there's still a pending approval
            // (clear it only when the count drops to zero).
            let content = LancerSessionAttributes.ContentState(
                status: base.status,
                pendingApprovals: count,
                agentName: base.agentName,
                pendingApprovalID: count > 0 ? base.pendingApprovalID : nil,
                pendingApprovalRisk: count > 0 ? highestRisk : nil,
                isStreaming: base.isStreaming,
                cost: base.cost
            )
            await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
            lastContent[activityKey] = content
        }
    }

    /// Reflect whether the agent is actively executing on a session, preserving
    /// the activity's other fields. Drives the island glyph's blue "streaming"
    /// tint. No-ops when no activity is running for the session.
    public func updateStreaming(activityKey: String, isStreaming: Bool) async {
        guard let activity = activities[activityKey], let base = lastContent[activityKey] else { return }
        guard base.isStreaming != isStreaming else { return }
        let content = LancerSessionAttributes.ContentState(
            status: base.status,
            pendingApprovals: base.pendingApprovals,
            agentName: base.agentName,
            isStreaming: isStreaming,
            cost: base.cost
        )
        await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
        lastContent[activityKey] = content
    }

    /// Update the accumulated cost for a session's activity. No-ops when no
    /// activity is running for the session.
    public func updateCost(activityKey: String, cost: Double?) async {
        guard let activity = activities[activityKey], let base = lastContent[activityKey] else { return }
        let content = LancerSessionAttributes.ContentState(
            status: base.status,
            pendingApprovals: base.pendingApprovals,
            agentName: base.agentName,
            pendingApprovalID: base.pendingApprovalID,
            isStreaming: base.isStreaming,
            cost: cost
        )
        await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
        lastContent[activityKey] = content
    }

    /// End the activity for a single session (e.g. user disconnected).
    public func end(activityKey: String) async {
        guard let activity = activities[activityKey] else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        activities.removeValue(forKey: activityKey)
        lastContent.removeValue(forKey: activityKey)
        tokenTasks[activityKey]?.cancel()
        tokenTasks.removeValue(forKey: activityKey)
    }

    // MARK: - Push token monitoring

    private func startTokenMonitor(
        for activity: Activity<LancerSessionAttributes>,
        activityKey: String,
        deviceSessionID: String
    ) {
        tokenTasks[activityKey]?.cancel()
        tokenTasks[activityKey] = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
                await self?.tokenRegistration?(deviceSessionID, hexToken, false)
            }
        }
    }
}

#endif // os(iOS)
