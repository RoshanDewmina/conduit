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
    }
}
