import SwiftUI
import DesignSystem

@main
struct LancerMacApp: App {
    @State private var host = HostModel()

    init() {
        DesignSystemFonts.register()
    }

    var body: some Scene {
        MenuBarExtra("Lancer", systemImage: "bolt.horizontal.circle") {
            MenuBarContentView()
                .environment(host)
                .task {
                    host.startPolling()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Lancer", id: "management") {
            ManagementView()
                .environment(host)
        }
        // Screenshot/QA harness, mirroring the iOS app's `LANCER_GALLERY`
        // convention: a MenuBarExtra-only app opens no window on launch, which
        // makes automated screenshots of the management panes impossible. When
        // LANCER_MAC_OPEN_MANAGEMENT is set, present the window at launch.
        .defaultLaunchBehavior(openManagementOnLaunch ? .presented : .automatic)
    }

    private var openManagementOnLaunch: Bool {
        ProcessInfo.processInfo.environment["LANCER_MAC_OPEN_MANAGEMENT"] != nil
    }
}
