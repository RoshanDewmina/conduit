#if os(iOS)
import Foundation
import LancerCore
import WidgetKit

/// Keeps the Home Screen `AgentStatusWidget` current from the same daemon
/// poll that feeds Workspaces Agents — not from phone SSH/session
/// `connected` status (`SessionViewModel.writeWidgetSnapshot`).
extension RunningAgentsMapping {
    /// - Parameter suiteName: Overridable for tests (isolated UserDefaults
    ///   domain). Production uses `WidgetSnapshot.appGroupID`.
    public static func writeRunningAgentsWidgetSnapshot(
        rows: [Row],
        status: AgentStatusSnapshot?,
        hostName: String?,
        suiteName: String = WidgetSnapshot.appGroupID
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let count = resolvedRunningCount(rows: rows, status: status)
        let lines = widgetLines(from: rows, status: status, hostName: hostName)
        defaults.set(count, forKey: WidgetSnapshot.runningAgentsCountKey)
        if lines.isEmpty {
            defaults.removeObject(forKey: WidgetSnapshot.runningAgentsLinesKey)
        } else {
            defaults.set(lines, forKey: WidgetSnapshot.runningAgentsLinesKey)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: WidgetSnapshot.runningAgentsUpdatedKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "AgentStatusWidget")
    }
}
#endif
