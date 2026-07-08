import SwiftUI
import AppFeature
import LancerCore
import DesignSystem
import NotificationsKit
import PersistenceKit
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
                guard let route = DeepLinkRoute.parse(url) else { return }
                switch route {
                case .billing(let returnURL):
                    UserDefaults.standard.set(returnURL.absoluteString, forKey: "dev.lancer.lastBillingReturnURL")
                    Task {
                        await PurchaseManager.shared.restore()
                        await PurchaseManager.shared.refreshCloudEntitlement()
                    }
                case .authCallback(let callbackURL):
                    NotificationCenter.default.post(name: .lancerAuthCallback, object: callbackURL)
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

/// UNUserNotificationCenterDelegate's completion handlers are plain, non-`Sendable`
/// closures. Wrapping one lets it cross into an unstructured `Task` (needed so the
/// lock-screen decision POST can finish before the handler is called) without
/// tripping Swift 6 region-isolation checks; it is only ever invoked once, from
/// wherever this box ends up running.
private struct CompletionHandlerBox: @unchecked Sendable {
    let run: () -> Void
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
    ///
    /// Approve/Reject must not depend on `AppRoot`'s SwiftUI view graph running:
    /// when the app is force-quit, iOS invokes this delegate method by launching
    /// the process in the background WITHOUT connecting a `WindowGroup` scene
    /// (no `.foreground` option on either action), so `AppRoot`'s body — and the
    /// `.task`/`.onReceive` modifiers that used to be the only place decisions
    /// were forwarded — never executes. Proven on-device 2026-07-08 (checkpoint
    /// 5c): `ApprovalActionBuffer.record` + the `NotificationCenter` post ran,
    /// but the daemon's `audit.log` never saw the decision because nothing ever
    /// drained the buffer. This method now forwards the decision itself, inline,
    /// via `deliverDecision`, so delivery no longer depends on any scene
    /// connecting. The buffer + notification post are kept for the warm/foreground
    /// case (they update the live Inbox view models); both paths write to the
    /// same first-decision-wins `ApprovalRelay.enqueue`, so replaying is a no-op.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info      = response.notification.request.content.userInfo
        let approvalId = info["approvalId"] as? String ?? ""
        let sessionId  = info["sessionId"]  as? String ?? ""

        switch response.actionIdentifier {
        case "approval.approve", "approval.reject":
            let decision: Approval.Decision = response.actionIdentifier == "approval.approve" ? .approved : .rejected
            let action = response.actionIdentifier == "approval.approve" ? "approve" : "reject"
            // Buffer + post for the warm-app case: if AppRoot's view graph IS
            // running (app was foregrounded/backgrounded, not force-quit), this
            // updates the live Inbox view model immediately.
            ApprovalActionBuffer.shared.record(
                PendingApprovalAction(approvalID: approvalId, sessionID: sessionId, action: action)
            )
            NotificationCenter.default.post(
                name: .lancerApprovalAction,
                object: nil,
                userInfo: ["approvalId": approvalId, "sessionId": sessionId, "action": action]
            )
            guard !approvalId.isEmpty else {
                completionHandler()
                return
            }
            let handlerBox = CompletionHandlerBox(run: completionHandler)
            Task { @MainActor in
                let taskID = UIApplication.shared.beginBackgroundTask(withName: "dev.lancer.approvalDecision")
                await Self.deliverDecision(approvalID: approvalId, decision: decision)
                handlerBox.run()
                if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            }
            return
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

    /// Delivers a lock-screen Approve/Reject decision directly to the daemon,
    /// independent of `AppRoot`/`AppEnvironment` ever being constructed in this
    /// process launch. Opens its own `AppDatabase` handle (GRDB `DatabasePool`
    /// supports multiple pool instances against the same WAL-mode file within one
    /// process) and reuses `ApprovalRelay`'s existing cold-launch path — Keychain
    /// credential hydration, SSH-channel-then-backend-relay fallback, and the
    /// on-disk redelivery queue — so this is the same delivery guarantee the
    /// Live Activity intent path already relies on, just invoked from a place
    /// that is guaranteed to run even when no scene connects.
    private static func deliverDecision(approvalID: String, decision: Approval.Decision) async {
        guard let db = try? AppDatabase.openShared() else { return }
        await ApprovalRelay.shared.enqueue(approvalID: approvalID, decision: decision, db: db, hostID: "")
    }
}
