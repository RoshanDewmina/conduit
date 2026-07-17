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
    public func writeApprovalWidgetSnapshot() async {
        guard let pending = try? await self.pending() else { return }
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID) else { return }
        defaults.set(pending.count, forKey: WidgetSnapshot.pendingApprovalsKey)
        // `pending()` already orders by createdAt DESC, so `first` is the newest.
        if let newest = pending.first {
            defaults.set(Self.summaryLine(for: newest), forKey: WidgetSnapshot.pendingApprovalSummaryKey)
        } else {
            defaults.removeObject(forKey: WidgetSnapshot.pendingApprovalSummaryKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: WidgetSnapshot.lastUpdatedKey)
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
