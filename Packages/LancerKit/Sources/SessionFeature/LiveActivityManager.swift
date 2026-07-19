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
import os
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

/// Called by `end(activityKey:)` once the local Activity has actually ended,
/// so push-backend can clear its now-dead per-activity token (root cause b,
/// 2026-07-19: a token left on file after the activity it belonged to ended
/// permanently suppressed the next app-closed push-to-start). Carries only the
/// device/app-level session id — never an activity token, since there is
/// nothing left to register, only to clear.
public typealias ActivityTokenClear = @Sendable (_ sessionID: String) async -> Void

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
    fileprivate static let diagLogger = Logger(subsystem: "dev.lancer.mobile", category: "LiveActivity")

    private var activities: [String: Activity<LancerSessionAttributes>] = [:]
    // Last content pushed per activityKey, so partial updates (e.g. approval
    // count only) can preserve the other fields instead of resetting them.
    private var lastContent: [String: LancerSessionAttributes.ContentState] = [:]
    // Token-monitoring tasks keyed by activityKey so they're cancelled on end().
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    // Push-to-start token monitor (one per app lifetime).
    private var pushToStartTask: Task<Void, Never>?
    // Watches ActivityKit's activity set so push-to-start LAs (started while
    // the app was closed) still feed the Home Screen Agents widget once iOS
    // surfaces them — a one-shot sync at launch often races an empty list.
    private var activityUpdatesTask: Task<Void, Never>?
    // Fleet-wide pending-approval state, remembered even when no activity is
    // currently running (2026-07-18 review finding): an approval can arrive
    // before the run that will own its Live Activity starts, so a freshly
    // started activity needs to seed from this instead of always opening at
    // pendingApprovals: 0 and under-reporting until the next count change.
    private var fleetPendingCount = 0
    private var fleetPendingRisk: Int?
    private var fleetPendingID: String?

    /// Closure called when an activity or push-to-start push token is ready.
    /// Set by LancerApp at launch (alongside the APNs device-token path).
    public var tokenRegistration: ActivityTokenRegistration?

    /// Closure called from `end(activityKey:)` to clear the now-dead
    /// per-activity token on push-backend. Set by LancerApp alongside
    /// `tokenRegistration`.
    public var tokenClear: ActivityTokenClear?

    /// deviceSessionID captured at `start(...)` per activityKey, so `end(...)`
    /// (which only receives activityKey) can still tell `tokenClear` which
    /// session's token to drop.
    private var deviceSessionIDs: [String: String] = [:]

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
        Self.diagLogger.info("start() called, isEnabled=\(self.isEnabled, privacy: .public)")
        guard isEnabled else {
            Self.diagLogger.error("start() aborted — Live Activities disabled (Settings → Notifications → Lancer, or system-wide)")
            return
        }

        // Callers on the production relay path (`ShellLiveBridge.startLiveActivity`)
        // never know the fleet-wide pending count themselves — that's
        // `RelayApprovalIngest`'s job via `updatePendingApprovals` — so they pass
        // the parameter defaults. Seed a brand-new activity from the fleet-wide
        // cache in that case instead of always opening at 0/nil, which under-
        // reported an approval that arrived before this activity existed
        // (2026-07-18 review finding). A caller passing explicit values (the
        // legacy per-session path) is left alone.
        let usesFleetDefaults = pendingApprovals == 0 && pendingApprovalID == nil && pendingApprovalRisk == nil
        let resolvedApprovals = usesFleetDefaults ? fleetPendingCount : pendingApprovals
        let resolvedApprovalID = usesFleetDefaults ? fleetPendingID : pendingApprovalID
        let resolvedApprovalRisk = usesFleetDefaults ? fleetPendingRisk : pendingApprovalRisk

        let content = LancerSessionAttributes.ContentState(
            status: status,
            pendingApprovals: resolvedApprovals,
            agentName: agentName,
            pendingApprovalID: resolvedApprovalID,
            pendingApprovalRisk: resolvedApprovalRisk,
            cost: lastContent[activityKey]?.cost
        )

        deviceSessionIDs[activityKey] = deviceSessionID

        if let existing = activities[activityKey] {
            await existing.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
            lastContent[activityKey] = content
            LiveActivityRunningAgentsWidget.syncFromSystemActivities()
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
            Self.diagLogger.info("Activity.request succeeded, id=\(activity.id, privacy: .public)")
            startTokenMonitor(for: activity, activityKey: activityKey, deviceSessionID: deviceSessionID)
            // Same chokepoint as push-to-start island content — keep Home
            // Screen AgentStatusWidget aligned without requiring Workspaces
            // Agents to be mounted.
            LiveActivityRunningAgentsWidget.syncFromSystemActivities()
        } catch {
            // ActivityKit refuses (off in Settings, system busy, etc.) —
            // silent failure is correct; the in-app inbox still works.
            Self.diagLogger.error("Activity.request FAILED: \(error, privacy: .public)")
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
        startActivityUpdatesMonitorIfNeeded()
    }

    /// Observe ActivityKit activity create/end so Home Screen Agents widget
    /// tracks push-to-start LAs without requiring Workspaces Agents to poll.
    private func startActivityUpdatesMonitorIfNeeded() {
        guard activityUpdatesTask == nil else { return }
        activityUpdatesTask = Task { [weak self] in
            for await _ in Activity<LancerSessionAttributes>.activityUpdates {
                self?.syncRunningAgentsWidget()
            }
        }
        // Immediate + deferred passes: Activity.activities can be empty for a
        // beat after cold launch even when the Dynamic Island is already up.
        syncRunningAgentsWidget()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.syncRunningAgentsWidget()
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
        LiveActivityRunningAgentsWidget.syncFromSystemActivities()
    }

    /// Status/agent-only update that preserves the pending-approval fields from
    /// the activity's current content. `ShellLiveBridge` owns status transitions
    /// while `RelayApprovalIngest.updatePendingApprovals` owns the pending
    /// count/ID/risk — a full `update(...)` from the status side would rewrite
    /// pendingApprovals back to 0 and drop `pendingApprovalID` (hiding the
    /// Approve/Reject buttons, the exact MAJOR-14 failure) on every mid-run
    /// status change.
    public func updateStatus(activityKey: String, status: String, agentName: String? = nil) async {
        guard let activity = activities[activityKey] else { return }
        let base = lastContent[activityKey]
        let content = LancerSessionAttributes.ContentState(
            status: status,
            pendingApprovals: base?.pendingApprovals ?? 0,
            agentName: agentName ?? base?.agentName,
            pendingApprovalID: base?.pendingApprovalID,
            pendingApprovalRisk: base?.pendingApprovalRisk,
            isStreaming: base?.isStreaming ?? false,
            cost: base?.cost
        )
        await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
        lastContent[activityKey] = content
        LiveActivityRunningAgentsWidget.syncFromSystemActivities()
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
    public func updatePendingApprovals(_ count: Int, highestRisk: Int? = nil, pendingApprovalID: String? = nil) async {
        // Remembered fleet-wide even when NO activity is currently running:
        // an approval can arrive before the run's activity starts, and `start`
        // seeds from this so the new activity doesn't under-report 0 pending
        // (2026-07-18 review finding — the caller-side dedup this replaces
        // cached the count without knowing nobody had received it).
        fleetPendingCount = count
        fleetPendingRisk = count > 0 ? highestRisk : nil
        fleetPendingID = count > 0 ? (pendingApprovalID ?? fleetPendingID) : nil
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
                pendingApprovalID: count > 0 ? (pendingApprovalID ?? base.pendingApprovalID) : nil,
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
        LiveActivityRunningAgentsWidget.syncFromSystemActivities()
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
    /// Also clears push-backend's per-activity token via `tokenClear` — a
    /// token left on file after its activity ends permanently suppresses the
    /// NEXT app-closed push-to-start (root cause b, 2026-07-19).
    public func end(activityKey: String) async {
        guard let activity = activities[activityKey] else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        activities.removeValue(forKey: activityKey)
        lastContent.removeValue(forKey: activityKey)
        tokenTasks[activityKey]?.cancel()
        tokenTasks.removeValue(forKey: activityKey)
        if let deviceSessionID = deviceSessionIDs.removeValue(forKey: activityKey) {
            await tokenClear?(deviceSessionID)
        }
        LiveActivityRunningAgentsWidget.syncFromSystemActivities()
    }

    /// Re-read ActivityKit's live activities into the Home Screen widget.
    /// Call on foreground — covers push-to-start LAs that never went through
    /// in-process `start(...)` while the app was closed.
    public func syncRunningAgentsWidget() {
        startActivityUpdatesMonitorIfNeeded()
        let system = Activity<LancerSessionAttributes>.activities
        if !system.isEmpty {
            LiveActivityRunningAgentsWidget.syncFromSystemActivities()
            return
        }
        // System list empty: still emit in-process ShellLiveBridge /
        // SessionViewModel activities (Activity.activities can lag briefly
        // after cold launch / upgrade-install).
        let inputs: [LiveActivityRunningAgentsWidget.SnapshotInput] = lastContent.compactMap { key, state in
            guard let activity = activities[key] else { return nil }
            return .init(
                agentName: state.agentName,
                hostName: activity.attributes.hostName,
                hostID: activity.attributes.hostID,
                status: state.status,
                isStreaming: state.isStreaming
            )
        }
        LiveActivityRunningAgentsWidget.writeSnapshot(inputs: inputs)
    }

    // MARK: - Push token monitoring

    private func startTokenMonitor(
        for activity: Activity<LancerSessionAttributes>,
        activityKey: String,
        deviceSessionID: String
    ) {
        tokenTasks[activityKey]?.cancel()
        Self.diagLogger.info("startTokenMonitor watching pushTokenUpdates for activityKey=\(activityKey, privacy: .public)")
        tokenTasks[activityKey] = Task { [weak self] in
            for await tokenData in activity.pushTokenUpdates {
                let hexToken = tokenData.map { String(format: "%02x", $0) }.joined()
                Self.diagLogger.info("pushTokenUpdates delivered token, len=\(hexToken.count)")
                await self?.tokenRegistration?(deviceSessionID, hexToken, false)
            }
        }
    }
}

#endif // os(iOS)
