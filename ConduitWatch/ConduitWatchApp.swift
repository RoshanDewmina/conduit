import SwiftUI
import ConduitCore

@main
struct ConduitWatchApp: App {
    @State private var viewModel: WatchInboxViewModel

    init() {
        let connector = WatchConnector()
        _viewModel = State(initialValue: WatchInboxViewModel(connector: connector))
    }

    var body: some Scene {
        WindowGroup {
            InboxListView()
                .environment(viewModel)
                .onAppear {
                    viewModel.start()
                    #if targetEnvironment(simulator)
                    injectMockData()
                    #endif
                }
        }
    }

    #if targetEnvironment(simulator)
    private func injectMockData() {
        viewModel.approvals = [
            WatchApprovalTransfer(
                id: UUID().uuidString, sessionID: UUID().uuidString,
                agent: "claudeCode", kind: "command",
                command: "rm -rf /tmp/build && npm install && npm run build",
                cwd: "/home/user/my-project", risk: 2,
                createdAt: Date().timeIntervalSinceReferenceDate - 90
            ),
            WatchApprovalTransfer(
                id: UUID().uuidString, sessionID: UUID().uuidString,
                agent: "claudeCode", kind: "fileWrite",
                command: nil as String?,
                cwd: "/home/user/my-project/src/main.rs", risk: 1,
                createdAt: Date().timeIntervalSinceReferenceDate - 30
            ),
            WatchApprovalTransfer(
                id: UUID().uuidString, sessionID: UUID().uuidString,
                agent: "claudeCode", kind: "command",
                command: "sudo systemctl restart nginx",
                cwd: "/etc/nginx", risk: 3,
                createdAt: Date().timeIntervalSinceReferenceDate - 10
            ),
        ]
    }
    #endif
}
