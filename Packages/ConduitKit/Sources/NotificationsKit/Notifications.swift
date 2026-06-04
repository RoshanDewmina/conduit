import Foundation
import UserNotifications
import ConduitCore

// MARK: - NSNotification names for in-process routing of push action responses.

public extension Notification.Name {
    /// Posted when the user taps Approve/Reject on an approval push notification.
    /// userInfo: ["approvalId": String, "sessionId": String, "action": "approve"|"reject"]
    static let conduitApprovalAction    = Notification.Name("dev.conduit.approvalAction")
    /// Posted when the user taps View on a run-complete push notification.
    /// userInfo: ["sessionId": String]
    static let conduitRunCompleteAction = Notification.Name("dev.conduit.runCompleteAction")
    /// Posted when a background remote (APNs) push is received so the Inbox
    /// can refresh approval / run-complete state without the user opening the app.
    /// userInfo: the raw APNs userInfo dictionary forwarded from the push payload.
    static let conduitRemoteApprovalReceived = Notification.Name("dev.conduit.remoteApprovalReceived")
}

/// Controls which approval notifications are delivered.
/// Stored in UserDefaults so user preferences persist across launches.
public struct NotificationFilter: Codable, Sendable, Equatable {
    public var minRisk: Approval.Risk = .low
    /// nil = all agents; non-nil = only the listed agent raw values
    public var enabledAgents: Set<String>? = nil
    public var quietHoursEnabled: Bool = false
    /// Hour of day (0–23) when quiet hours begin
    public var quietHoursStart: Int = 22
    /// Hour of day (0–23) when quiet hours end (exclusive)
    public var quietHoursEnd: Int = 8

    public init() {}

    public func shouldDeliver(risk: Approval.Risk, agent: Approval.AgentSource) -> Bool {
        guard risk.rawValue >= minRisk.rawValue else { return false }
        if let agents = enabledAgents, !agents.contains(agent.rawValue) { return false }
        guard !quietHoursEnabled else { return !isCurrentlyQuiet() }
        return true
    }

    private func isCurrentlyQuiet() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        // start == end is treated as "all day quiet" (full 24-hour block).
        if quietHoursStart == quietHoursEnd { return true }
        if quietHoursStart < quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        }
        // Spans midnight (e.g. 22:00 → 08:00)
        return hour >= quietHoursStart || hour < quietHoursEnd
    }
}

/// Local + remote notification orchestration. For M3 we use only local
/// notifications driven by the side-channel WebSocket; APNs registration is
/// added in M4 alongside the control plane.
public actor Notifications {
    public static let shared = Notifications()
    private init() {}

    // MARK: - Notification filter

    private static let filterKey = "dev.conduit.notificationFilter"

    private var _filter: NotificationFilter = {
        guard let data = UserDefaults.standard.data(forKey: filterKey),
              let f = try? JSONDecoder().decode(NotificationFilter.self, from: data)
        else { return NotificationFilter() }
        return f
    }()

    public var filter: NotificationFilter {
        get { _filter }
        set {
            _filter = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.filterKey)
            }
        }
    }

    public func loadFilter() -> NotificationFilter {
        _filter
    }

    public func saveFilter(_ filter: NotificationFilter) {
        self.filter = filter
    }

    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    /// Schedule a local notification representing a pending approval. The
    /// notification body uses `userInfo` to deep-link into the Inbox tab.
    public func notifyPendingApproval(_ approval: Approval, hostName: String) async {
        guard _filter.shouldDeliver(risk: approval.risk, agent: approval.agent) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Approval needed · \(hostName)"
        content.body = approval.command ?? approval.patch.map { _ in "Patch ready for review" } ?? "Action pending"
        content.sound = .defaultCritical
        content.threadIdentifier = approval.sessionID.uuidString
        content.userInfo = [
            "kind": "approval",
            "approvalId": approval.id.uuidString,
            "sessionId":  approval.sessionID.uuidString,
        ]
        // Actionable category — registered in registerCategories().
        content.categoryIdentifier = "approval"

        let req = UNNotificationRequest(
            identifier: approval.id.uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        do { try await UNUserNotificationCenter.current().add(req) }
        catch { /* notification dropped; UI still surfaces it */ }
    }

    /// Posts a local notification informing the user that automatic reconnection
    /// to `hostName` failed after all retry attempts were exhausted.
    public func notifyReconnectFailed(hostName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Connection lost"
        content.body = "Could not reconnect to \(hostName)"
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "reconnect-failed-\(hostName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // deliver immediately
        )
        do { try await UNUserNotificationCenter.current().add(req) }
        catch { /* notification dropped; status bar already shows disconnected */ }
    }

    /// Posts a local notification when the SSH session is suspended due to
    /// iOS background task expiration.
    public func postSessionSuspended(hostName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Session suspended"
        content.body = "Connection to \(hostName) was suspended. Tap to reconnect."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "session-suspended-\(hostName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        do { try await UNUserNotificationCenter.current().add(req) }
        catch { }
    }

    /// Registers the device token with the push backend so remote approvals
    /// (when the app is killed) reach the device. Call from AppDelegate /
    /// UIApplicationDelegate after UIApplication.registerForRemoteNotifications().
    ///
    /// backendURL: the base URL of your push-backend deployment, e.g.
    ///   "https://conduit-push.fly.dev"
    public func registerDeviceToken(_ token: Data, sessionID: String, backendURL: String) async {
        let hexToken = token.map { String(format: "%02x", $0) }.joined()
        guard let url = URL(string: "\(backendURL)/register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["sessionId": sessionID, "deviceToken": hexToken]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Posts a local notification when a run or agent task completes.
    public func notifyRunComplete(
        hostName: String,
        command: String,
        exitCode: Int,
        sessionID: String
    ) async {
        let ok = exitCode == 0
        let content = UNMutableNotificationContent()
        content.title = ok ? "Run complete · \(hostName)" : "Run failed · \(hostName)"
        content.body = "\(command) — exit \(exitCode)"
        content.sound = ok ? .default : .defaultCritical
        content.threadIdentifier = sessionID
        content.categoryIdentifier = "run-complete"
        content.userInfo = [
            "kind": "runComplete",
            "sessionId": sessionID,
            "exitCode": exitCode,
        ]
        let req = UNNotificationRequest(
            identifier: "run-\(sessionID)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        do { try await UNUserNotificationCenter.current().add(req) }
        catch { }
    }

    public nonisolated func registerCategories() {
        let approve = UNNotificationAction(
            identifier: "approval.approve",
            title: "Approve",
            options: [.authenticationRequired]
        )
        let reject = UNNotificationAction(
            identifier: "approval.reject",
            title: "Reject",
            options: [.destructive]
        )
        let approvalCategory = UNNotificationCategory(
            identifier: "approval",
            actions: [approve, reject],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let viewRun = UNNotificationAction(
            identifier: "run.view",
            title: "View",
            options: [.foreground]
        )
        let runCategory = UNNotificationCategory(
            identifier: "run-complete",
            actions: [viewRun],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([approvalCategory, runCategory])
    }
}
