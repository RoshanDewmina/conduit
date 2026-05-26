import SwiftUI
import ConduitCore

@main
struct ConduitWatchApp: App {
    @State private var store: WatchStore

    init() {
        let connector = WatchConnector()
        _store = State(initialValue: WatchStore(connector: connector))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .onAppear {
                    store.start()
                    #if targetEnvironment(simulator)
                    injectMockData()
                    #endif
                }
        }
    }

    #if targetEnvironment(simulator)
    private func injectMockData() {
        store.approvals = [
            WatchApprovalTransfer(
                id: UUID().uuidString, sessionID: UUID().uuidString,
                agent: "claudeCode", kind: "command",
                command: "rm -rf /tmp/build && npm install && npm run build",
                cwd: "/home/user/my-project", risk: 2,
                createdAt: Date().timeIntervalSinceReferenceDate - 90
            ),
            WatchApprovalTransfer(
                id: UUID().uuidString, sessionID: UUID().uuidString,
                agent: "claudeCode", kind: "command",
                command: "sudo systemctl restart nginx",
                cwd: "/etc/nginx", risk: 3,
                createdAt: Date().timeIntervalSinceReferenceDate - 10
            ),
        ]
        store.sessionStatus = WatchSessionStatus(
            hostName: "gcp-server",
            hostname: "35.201.3.231",
            isConnected: true,
            agentActive: true,
            pendingCount: 2,
            connectedAt: Date().timeIntervalSinceReferenceDate - 7800
        )
        store.recentActivity = [
            WatchActivityBlock(
                id: UUID().uuidString,
                command: "git status",
                outputPreview: "On branch main\nYour branch is up to date",
                exitCode: 0, isSuccess: true,
                startedAt: Date().timeIntervalSinceReferenceDate - 300,
                duration: 0.12
            ),
            WatchActivityBlock(
                id: UUID().uuidString,
                command: "npm run test",
                outputPreview: "PASS src/auth.test.ts\nPASS src/api.test.ts\n✓ 47 tests passed",
                exitCode: 0, isSuccess: true,
                startedAt: Date().timeIntervalSinceReferenceDate - 120,
                duration: 18.4
            ),
            WatchActivityBlock(
                id: UUID().uuidString,
                command: "cargo build --release",
                outputPreview: nil as String? ?? "",
                exitCode: nil, isSuccess: nil,
                startedAt: Date().timeIntervalSinceReferenceDate - 15,
                duration: nil
            ),
        ]
        store.snippets = [
            WatchSnippet(id: UUID().uuidString, name: "Disk usage", body: "df -h /"),
            WatchSnippet(id: UUID().uuidString, name: "Memory", body: "free -h"),
            WatchSnippet(id: UUID().uuidString, name: "Top processes", body: "ps aux --sort=-%cpu | head -5"),
            WatchSnippet(id: UUID().uuidString, name: "Restart nginx", body: "sudo systemctl restart nginx"),
            WatchSnippet(id: UUID().uuidString, name: "Git status", body: "git status && git log --oneline -5"),
        ]
    }
    #endif
}

// MARK: - Root tab container

struct RootTabView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        TabView {
            // Tab 1: Approval inbox
            NavigationStack {
                InboxListView()
            }
            .containerBackground(.black.gradient, for: .tabView)

            // Tab 2: Session status + emergency stop
            NavigationStack {
                SessionStatusView()
            }
            .containerBackground(.black.gradient, for: .tabView)

            // Tab 3: Recent activity feed
            NavigationStack {
                ActivityFeedView()
            }
            .containerBackground(.black.gradient, for: .tabView)

            // Tab 4: Snippet runner
            NavigationStack {
                SnippetRunnerView()
            }
            .containerBackground(.black.gradient, for: .tabView)
        }
        .tabViewStyle(.verticalPage)
    }
}
