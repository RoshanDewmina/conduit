import SwiftUI
import AppFeature
import NotificationsKit
#if canImport(UIKit)
import UIKit
#endif

/// GCP VM push backend. Override in DEBUG via CONDUIT_PUSH_BACKEND_URL.
private func pushBackendURL() -> String {
    #if DEBUG
    if let envURL = ProcessInfo.processInfo.environment["CONDUIT_PUSH_BACKEND_URL"],
       !envURL.isEmpty {
        return envURL
    }
    #endif
    if let plist = Bundle.main.infoDictionary?["CONDUIT_PUSH_BACKEND_URL"] as? String,
       !plist.isEmpty {
        return plist
    }
    return "http://35.201.3.231:8080"
}

@main
struct ConduitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRoot()
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
        guard !pushBackendURL().isEmpty else { return }
        Task {
            await Notifications.shared.registerDeviceToken(
                deviceToken,
                sessionID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                backendURL: pushBackendURL()
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
