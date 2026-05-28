import SwiftUI
import AppFeature
import NotificationsKit
#if canImport(UIKit)
import UIKit
#endif

/// GCP VM push backend. Switch to HTTPS before public App Store release.
private let pushBackendURL = "http://35.201.3.231:8080"

@main
struct ConduitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    guard url.scheme == "conduit", url.host == "billing" else { return }
                    UserDefaults.standard.set(url.absoluteString, forKey: "dev.conduit.lastBillingReturnURL")
                }
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
