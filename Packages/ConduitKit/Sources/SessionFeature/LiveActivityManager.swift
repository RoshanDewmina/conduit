// Tier 1.5.1 — iOS Live Activity for an active Conduit session.
//
// Surfaces "<agent> running on <host> — N pending" on the lock screen
// and Dynamic Island while the user is connected. Termius leads their
// AI-on-mobile marketing with Live Activities; Conduit matches it.
//
// Lifecycle:
//   • SessionViewModel.connect() success → ConduitLiveActivityManager.start(...)
//   • ApprovalRepository.upserts → manager.updatePendingApprovals(_:)
//   • SessionViewModel.disconnect() / app shutdown → manager.endAll()
//
// Requires:
//   • NSSupportsLiveActivities = YES in Info.plist (set in project.yml)
//   • A Widget Extension target that imports this file and renders the
//     `ActivityAttributes`/`ContentState` — see ConduitLiveActivityWidget
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
public struct ConduitSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String           // "connected" / "reconnecting" / "suspended"
        public var pendingApprovals: Int
        public var agentName: String?       // "Claude Code" when an agent is running
        public var pendingApprovalID: String?
        public var isStreaming: Bool        // agent is actively executing (drives the blue glyph)
        public var cost: Double?            // accumulated cost in USD
        public var lastUpdate: Date

        public init(
            status: String,
            pendingApprovals: Int = 0,
            agentName: String? = nil,
            pendingApprovalID: String? = nil,
            isStreaming: Bool = false,
            cost: Double? = nil,
            lastUpdate: Date = .now
        ) {
            self.status = status
            self.pendingApprovals = pendingApprovals
            self.agentName = agentName
            self.pendingApprovalID = pendingApprovalID
            self.isStreaming = isStreaming
            self.cost = cost
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

/// Thin wrapper around ActivityKit for Conduit's session activities. One
/// activity per active host; calling `start(...)` again for an existing host
/// updates its content rather than creating a duplicate.
@available(iOS 16.2, *)
@MainActor
public final class ConduitLiveActivityManager {
    public static let shared = ConduitLiveActivityManager()

    private var activities: [String: Activity<ConduitSessionAttributes>] = [:]
    // Last content pushed per host, so partial updates (e.g. approval count
    // only) can preserve the other fields instead of resetting them.
    private var lastContent: [String: ConduitSessionAttributes.ContentState] = [:]

    private init() {}

    /// True when the OS allows Live Activities (user toggle in Settings →
    /// Notifications → Conduit). Calls are safe when false — they no-op.
    public var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start a Live Activity for a host, or update its content if one is
    /// already running.
    public func start(
        hostID: String,
        hostName: String,
        status: String = "connected",
        agentName: String? = nil,
        pendingApprovals: Int = 0,
        pendingApprovalID: String? = nil
    ) async {
        guard isEnabled else { return }

        let content = ConduitSessionAttributes.ContentState(
            status: status,
            pendingApprovals: pendingApprovals,
            agentName: agentName,
            pendingApprovalID: pendingApprovalID,
            cost: lastContent[hostID]?.cost
        )

        if let existing = activities[hostID] {
            await existing.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
            lastContent[hostID] = content
            return
        }

        let attrs = ConduitSessionAttributes(hostName: hostName, hostID: hostID)
        do {
            let activity = try Activity.request(
                attributes: attrs,
                content: .init(state: content, staleDate: Date().addingTimeInterval(1800)),
                pushType: nil
            )
            activities[hostID] = activity
            lastContent[hostID] = content
        } catch {
            // ActivityKit refuses (off in Settings, system busy, etc.) —
            // silent failure is correct; the in-app inbox still works.
        }
    }

    /// Update an existing activity's content. No-ops if no activity is
    /// running for the given host.
    public func update(
        hostID: String,
        status: String,
        agentName: String? = nil,
        pendingApprovals: Int = 0,
        pendingApprovalID: String? = nil
    ) async {
        guard let activity = activities[hostID] else { return }
        let content = ConduitSessionAttributes.ContentState(
            status: status,
            pendingApprovals: pendingApprovals,
            agentName: agentName,
            pendingApprovalID: pendingApprovalID,
            cost: lastContent[hostID]?.cost
        )
        await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
        lastContent[hostID] = content
    }

    /// Update the pending-approval count on every running activity, preserving
    /// each one's other fields. This is the glanceable signal the Dynamic Island
    /// exists for, so it must stay live while the app is backgrounded. No-ops
    /// when no activities are running.
    public func updatePendingApprovals(_ count: Int) async {
        for (hostID, activity) in activities {
            guard let base = lastContent[hostID] else { continue }
            // Construct a fresh value (not a mutated copy of stored actor state)
            // so it forms its own isolation region and is safe to send.
            //
            // MAJOR-14: preserve `pendingApprovalID` — the Live Activity / Dynamic
            // Island Approve/Reject buttons only render when it is non-empty, so
            // dropping it here stripped the buttons exactly when an approval was
            // pending. Carry it through whenever there's still a pending approval
            // (clear it only when the count drops to zero).
            let content = ConduitSessionAttributes.ContentState(
                status: base.status,
                pendingApprovals: count,
                agentName: base.agentName,
                pendingApprovalID: count > 0 ? base.pendingApprovalID : nil,
                isStreaming: base.isStreaming,
                cost: base.cost
            )
            await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
            lastContent[hostID] = content
        }
    }

    /// Reflect whether the agent is actively executing on a host, preserving the
    /// activity's other fields. Drives the island glyph's blue "streaming" tint.
    /// No-ops when no activity is running for the host.
    public func updateStreaming(hostID: String, isStreaming: Bool) async {
        guard let activity = activities[hostID], let base = lastContent[hostID] else { return }
        guard base.isStreaming != isStreaming else { return }
        let content = ConduitSessionAttributes.ContentState(
            status: base.status,
            pendingApprovals: base.pendingApprovals,
            agentName: base.agentName,
            isStreaming: isStreaming,
            cost: base.cost
        )
        await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
        lastContent[hostID] = content
    }

    /// Update the accumulated cost for a host's activity. No-ops when no activity
    /// is running for the host.
    public func updateCost(hostID: String, cost: Double?) async {
        guard let activity = activities[hostID], let base = lastContent[hostID] else { return }
        let content = ConduitSessionAttributes.ContentState(
            status: base.status,
            pendingApprovals: base.pendingApprovals,
            agentName: base.agentName,
            pendingApprovalID: base.pendingApprovalID,
            isStreaming: base.isStreaming,
            cost: cost
        )
        await activity.update(.init(state: content, staleDate: Date().addingTimeInterval(1800)))
        lastContent[hostID] = content
    }

    /// End the activity for a single host (e.g. user disconnected).
    public func end(hostID: String) async {
        guard let activity = activities[hostID] else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        activities.removeValue(forKey: hostID)
        lastContent.removeValue(forKey: hostID)
    }

    /// End every activity (e.g. app entering termination).
    public func endAll() async {
        for (id, activity) in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            activities.removeValue(forKey: id)
        }
        lastContent.removeAll()
    }
}

#endif // os(iOS)
