import Foundation
import UserNotifications
import ConduitCore

/// Local + remote notification orchestration. For M3 we use only local
/// notifications driven by the side-channel WebSocket; APNs registration is
/// added in M4 alongside the control plane.
public actor Notifications {
    public static let shared = Notifications()
    private init() {}

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

    public func registerCategories() {
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
        let category = UNNotificationCategory(
            identifier: "approval",
            actions: [approve, reject],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
