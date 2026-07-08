import SwiftUI
import AppFeature
import LancerCore
import DesignSystem
import NotificationsKit
import SessionFeature
import SettingsFeature
import UserNotifications
#if canImport(Sentry)
import Sentry
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CloudKit)
import CloudKit
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif

// RELEASE GATE: Paste your Sentry DSN here before App Store submission.
// Create a project at https://sentry.io (or your self-hosted instance) to get a DSN.
// Leave empty to disable crash reporting entirely (SDK never starts).
// Opt-out key: "dev.lancer.crashReportingOptedOut" (bool) in UserDefaults.
private let sentryDSN = ""

@main
struct LancerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        DesignSystemFonts.register()
        configureSentry()
        // Without a reference to LancerAppShortcuts from the app target itself,
        // Xcode's app-intents metadata merge step silently drops it from the
        // final Metadata.appintents ("No AppShortcuts found - Skipping" in the
        // build log) even though it extracts correctly at the SessionFeature
        // library level — the type is otherwise never reachable from Lancer's
        // own linked binary. This call is also Apple's documented pattern for
        // re-registering shortcuts after a locale/parameter change.
        if #available(iOS 17.0, *) {
            LancerAppShortcuts.updateAppShortcutParameters()
            SiriSurfaceBootstrap.install()
            SiriSurfaceBootstrap.refreshOnLaunch()
        }
    }

    private func configureSentry() {
        #if canImport(Sentry)
        guard !sentryDSN.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: "dev.lancer.crashReportingOptedOut") else { return }
        SentrySDK.start { options in
            options.dsn = sentryDSN
            options.debug = false
            options.tracesSampleRate = 0    // no performance tracing — crash reports only
            options.sendDefaultPii = false  // no user PII (email, IP, etc.)
        }
        #if DEBUG
        // Uncomment one line below, run on device, then re-comment to verify symbolication:
        // SentrySDK.crash()
        #endif
        #endif
    }

    var body: some Scene {
        WindowGroup {
            appRoot
        }
    }

    private var appRoot: some View {
        AppRoot()
            .onOpenURL { url in
                guard url.scheme == "lancer" else { return }
                // Defense-in-depth (SEC-1): the supported hosts take no path. Reject
                // any extra path segments so a crafted `lancer://auth/<smuggled>`
                // can't reach a future path-dispatched handler. Query/fragment are
                // intentionally allowed — the auth callback carries its tokens there.
                guard url.path.isEmpty || url.path == "/" else { return }
                switch url.host {
                case "billing":
                    // Store the return URL so BillingView / settings can surface it.
                    UserDefaults.standard.set(url.absoluteString, forKey: "dev.lancer.lastBillingReturnURL")
                    // Refresh StoreKit entitlements — the user may have completed a
                    // purchase (StoreKit or Stripe) and returned via the deep link.
                    Task {
                        await PurchaseManager.shared.restore()
                        await PurchaseManager.shared.refreshCloudEntitlement()
                    }
                case "auth":
                    NotificationCenter.default.post(name: .lancerAuthCallback, object: url)
                default:
                    break
                }
            }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Singleton notification delegate kept alive for the app lifetime.
    private let notificationDelegate = LancerNotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register approval + run-complete action categories.
        Notifications.shared.registerCategories()
        // Foreground banner + action-response handling.
        UNUserNotificationCenter.current().delegate = notificationDelegate
        application.registerForRemoteNotifications()
        configureLiveActivityTokens()
        return true
    }

    /// Wire up Live Activity push token registration alongside the APNs device-token path.
    /// Sets the tokenRegistration closure on LancerLiveActivityManager so new activity
    /// tokens and the push-to-start token are forwarded to push-backend.
    /// AppRoot starts the push-to-start monitor once the stable session ID is
    /// available and forwards every token through the daemon-held relay secret.
    private func configureLiveActivityTokens() {
        #if os(iOS)
        if #available(iOS 16.2, *) {
            let manager = LancerLiveActivityManager.shared
            manager.tokenRegistration = { sessionID, activityToken, isPushToStart in
                NotificationCenter.default.post(
                    name: .lancerLiveActivityTokenReady,
                    object: nil,
                    userInfo: [
                        "sessionID": sessionID,
                        "activityToken": activityToken,
                        "isPushToStart": isPushToStart,
                    ]
                )
            }
        }
        #endif
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await Notifications.shared.setPendingAPNSToken(hexToken) }
        NotificationCenter.default.post(
            name: .lancerAPNSTokenReceived,
            object: nil,
            userInfo: ["token": hexToken]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected in simulator — APNs only works on physical device.
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // A CloudKit database-change push (Task 8 / B9 background pull) and an
        // APNs approval/run-complete push both arrive through this one
        // delegate method — route by payload shape rather than assuming.
        // `ConversationSyncEngine` re-derives the `CKNotification` itself and
        // confirms the subscription ID before acting, so forwarding the raw
        // dictionary here (rather than trying to interpret it) can't
        // misroute an approval push as a CloudKit one or vice versa.
        #if canImport(CloudKit)
        if CKNotification(fromRemoteNotificationDictionary: userInfo) != nil {
            NotificationCenter.default.post(
                name: .lancerCloudKitRemoteNotification,
                object: nil,
                userInfo: userInfo
            )
            completionHandler(.newData)
            return
        }
        #endif
        // Broadcast so the Inbox can refresh approval/run-complete state in background.
        NotificationCenter.default.post(
            name: .lancerRemoteApprovalReceived,
            object: nil,
            userInfo: userInfo
        )
        completionHandler(.newData)
    }
}

// MARK: - Notification delegate (separate class avoids Swift 6 actor-isolation conflict)

/// Handles UNUserNotificationCenter callbacks: foreground banner display and
/// action-button responses (Approve/Reject from the lock screen).
final class LancerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Show banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Route lock-screen action buttons (Approve / Reject / View) into the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info      = response.notification.request.content.userInfo
        let approvalId = info["approvalId"] as? String ?? ""
        let sessionId  = info["sessionId"]  as? String ?? ""

        switch response.actionIdentifier {
        case "approval.approve":
            // Buffer first (MAJOR-6): on a cold launch the post below races
            // AppRoot's subscriber and is dropped; AppRoot drains the buffer once
            // its graph is ready. The post still drives the warm-launch path.
            ApprovalActionBuffer.shared.record(
                PendingApprovalAction(approvalID: approvalId, sessionID: sessionId, action: "approve")
            )
            NotificationCenter.default.post(
                name: .lancerApprovalAction,
                object: nil,
                userInfo: ["approvalId": approvalId, "sessionId": sessionId, "action": "approve"]
            )
        case "approval.reject":
            ApprovalActionBuffer.shared.record(
                PendingApprovalAction(approvalID: approvalId, sessionID: sessionId, action: "reject")
            )
            NotificationCenter.default.post(
                name: .lancerApprovalAction,
                object: nil,
                userInfo: ["approvalId": approvalId, "sessionId": sessionId, "action": "reject"]
            )
        case "run.view":
            NotificationCenter.default.post(
                name: .lancerRunCompleteAction,
                object: nil,
                userInfo: ["sessionId": sessionId]
            )
        case UNNotificationDefaultActionIdentifier:
            // Tapping the notification body (not an action button) — bring the
            // user to the relevant session rather than doing nothing.
            NotificationCenter.default.post(
                name: .lancerRunCompleteAction,
                object: nil,
                userInfo: ["sessionId": sessionId]
            )
            // When the body tap is for an approval, also open the detail sheet.
            // Record to the buffer first (cold-launch guard) then post for warm case.
            if !approvalId.isEmpty {
                OpenApprovalBuffer.shared.record(approvalID: approvalId)
                NotificationCenter.default.post(
                    name: .lancerOpenApproval,
                    object: nil,
                    userInfo: ["approvalId": approvalId]
                )
            }
        default:
            break
        }
        completionHandler()
    }
}
