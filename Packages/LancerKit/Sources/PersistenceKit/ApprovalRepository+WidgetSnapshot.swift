#if os(iOS)
import Foundation
import LancerCore
import WidgetKit

/// Keeps the Home Screen `PendingApprovalsWidget` current. Called from both
/// the ingest path (a new approval arrives, `ApprovalIngest.handleApprovalPending`)
/// and the decision path (`ApprovalRelay.enqueue`, count drops), so the widget
/// doesn't rely solely on `WidgetSnapshot`'s occasional session-status refresh
/// (`SessionViewModel.writeWidgetSnapshot`) — pending-approval count changes on
/// its own cadence, independent of connection status.
extension ApprovalRepository {
    /// - Parameter suiteName: Overridable only for tests, which need an
    ///   isolated `UserDefaults` domain instead of the real device's shared
    ///   App Group (`WidgetSnapshot.appGroupID`, the production default) —
    ///   matches the per-test random-suite convention already used
    ///   throughout `LancerKitTests` (e.g. `DeviceIdentityTests`,
    ///   `GovernanceFeatureTests`).
    public func writeApprovalWidgetSnapshot(suiteName: String = WidgetSnapshot.appGroupID) async {
        // Sweep corpses before counting — daemon-side resolutions never
        // retire phone rows, so a stale pending set would otherwise be
        // written straight into the App Group and shown on the Home Screen.
        _ = try? await expireStalePending()
        guard let pending = try? await self.pending() else { return }
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(pending.count, forKey: WidgetSnapshot.pendingApprovalsKey)
        // `pending()` already orders by createdAt DESC, so `first` is the newest.
        if let newest = pending.first {
            defaults.set(Self.summaryLine(for: newest), forKey: WidgetSnapshot.pendingApprovalSummaryKey)
        } else {
            defaults.removeObject(forKey: WidgetSnapshot.pendingApprovalSummaryKey)
        }
        let now = Date().timeIntervalSince1970
        defaults.set(now, forKey: WidgetSnapshot.lastUpdatedKey)
        defaults.set(now, forKey: WidgetSnapshot.pendingApprovalsUpdatedKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "PendingApprovalsWidget")
    }

    private static func summaryLine(for approval: Approval) -> String {
        let riskLabel: String
        switch approval.risk {
        case .low: riskLabel = "Low"
        case .medium: riskLabel = "Medium"
        case .high: riskLabel = "High"
        case .critical: riskLabel = "Critical"
        }
        let action = approval.command
            ?? (approval.patch != nil ? "Patch review" : nil)
            ?? approval.question
            ?? approval.toolName
            ?? "Action pending"
        return "\(action) · \(riskLabel) risk"
    }
}
#endif
