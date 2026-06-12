import SwiftUI
import AppFeature
import ConduitCore
import DesignSystem
import NotificationsKit
import SettingsFeature
import UserNotifications
#if canImport(Sentry)
import Sentry
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Push backend HTTPS URL, injected from build config via Info.plist.
/// Set CONDUIT_PUSH_BACKEND_URL in project.yml (or Xcode build settings) to your
/// Cloud Run service URL — e.g. "https://conduit-push-HASH-ts.a.run.app".
/// Empty string disables push registration silently (safe for local/simulator runs).
/// ATS blocks any plain http:// URL in Release builds so no fallback is provided.
private var pushBackendURL: String {
    #if DEBUG
    if let envURL = ProcessInfo.processInfo.environment["CONDUIT_PUSH_BACKEND_URL"],
       !envURL.isEmpty {
        return envURL
    }
    #endif
    return Bundle.main.infoDictionary?["CONDUIT_PUSH_BACKEND_URL"] as? String ?? ""
}

// RELEASE GATE: Paste your Sentry DSN here before App Store submission.
// Create a project at https://sentry.io (or your self-hosted instance) to get a DSN.
// Leave empty to disable crash reporting entirely (SDK never starts).
// Opt-out key: "dev.conduit.crashReportingOptedOut" (bool) in UserDefaults.
private let sentryDSN = ""

@main
struct ConduitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        DesignSystemFonts.register()
        configureSentry()
    }

    private func configureSentry() {
        #if canImport(Sentry)
        guard !sentryDSN.isEmpty else { return }
        guard !UserDefaults.standard.bool(forKey: "dev.conduit.crashReportingOptedOut") else { return }
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
            rootView
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CONDUIT_TERMINAL_TEST"] == "1" {
            // New SwiftTerm-based terminal harness (live SSH). See DebugTerminalHarness.
            DebugTerminalHarness()
        } else {
            appRoot
        }
        #else
        appRoot
        #endif
    }

    private var appRoot: some View {
        AppRoot()
            .onOpenURL { url in
                guard url.scheme == "conduit", url.host == "billing" else { return }
                // Store the return URL so BillingView / settings can surface it.
                UserDefaults.standard.set(url.absoluteString, forKey: "dev.conduit.lastBillingReturnURL")
                // Refresh StoreKit entitlements — the user may have completed a
                // purchase (StoreKit or Stripe) and returned via the deep link.
                Task {
                    await PurchaseManager.shared.restore()
                    await PurchaseManager.shared.refreshCloudEntitlement()
                }
            }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Singleton notification delegate kept alive for the app lifetime.
    private let notificationDelegate = ConduitNotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register approval + run-complete action categories.
        Notifications.shared.registerCategories()
        // Foreground banner + action-response handling.
        UNUserNotificationCenter.current().delegate = notificationDelegate
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard !pushBackendURL.isEmpty else { return }
        Task {
            await Notifications.shared.registerDeviceToken(
                deviceToken,
                sessionID: DeviceIdentity.sessionID(),
                backendURL: pushBackendURL
            )
        }
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
        // Broadcast so the Inbox can refresh approval/run-complete state in background.
        NotificationCenter.default.post(
            name: .conduitRemoteApprovalReceived,
            object: nil,
            userInfo: userInfo
        )
        completionHandler(.newData)
    }
}

// MARK: - Notification delegate (separate class avoids Swift 6 actor-isolation conflict)

/// Handles UNUserNotificationCenter callbacks: foreground banner display and
/// action-button responses (Approve/Reject from the lock screen).
final class ConduitNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

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
                name: .conduitApprovalAction,
                object: nil,
                userInfo: ["approvalId": approvalId, "sessionId": sessionId, "action": "approve"]
            )
        case "approval.reject":
            ApprovalActionBuffer.shared.record(
                PendingApprovalAction(approvalID: approvalId, sessionID: sessionId, action: "reject")
            )
            NotificationCenter.default.post(
                name: .conduitApprovalAction,
                object: nil,
                userInfo: ["approvalId": approvalId, "sessionId": sessionId, "action": "reject"]
            )
        case "run.view":
            NotificationCenter.default.post(
                name: .conduitRunCompleteAction,
                object: nil,
                userInfo: ["sessionId": sessionId]
            )
        case UNNotificationDefaultActionIdentifier:
            // Tapping the notification body (not an action button) — bring the
            // user to the relevant session rather than doing nothing.
            NotificationCenter.default.post(
                name: .conduitRunCompleteAction,
                object: nil,
                userInfo: ["sessionId": sessionId]
            )
        default:
            break
        }
        completionHandler()
    }
}
