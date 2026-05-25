import SwiftUI
import AppFeature
import NotificationsKit
#if canImport(UIKit)
import UIKit
#endif

/// Fill this in after deploying daemon/push-backend/ to Fly.io (or Railway/Render).
/// Example: "https://conduit-push.fly.dev"
private let pushBackendURL = ""

@main
struct ConduitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
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
                sessionID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
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
        // Background push received — handled by existing local notification flow.
        completionHandler(.noData)
    }
}
