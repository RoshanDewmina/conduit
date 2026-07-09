#if os(iOS)
import SwiftUI

/// Workspaces root: All Repos + one row per repo. Live from bridge; DEBUG seed when mock.
public struct CursorWorkspacesView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let onSelectWorkspace: (String) -> Void
    private let onOpenSearch: () -> Void
    private let onRequestPairing: () -> Void

    public init(
        onSelectWorkspace: @escaping (String) -> Void = { _ in },
        onOpenSearch: @escaping () -> Void = {},
        onRequestPairing: @escaping () -> Void = {}
    ) {
        self.onSelectWorkspace = onSelectWorkspace
        self.onOpenSearch = onOpenSearch
        self.onRequestPairing = onRequestPairing
    }

    private var seedWorkspaces: [CursorShellLiveBridge.WorkspaceRow] {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["LANCER_CURSOR_MOCK_RUN_TARGETS"] == "1" else {
            return [CursorShellLiveBridge.WorkspaceRow(id: "lancer-ios", name: "lancer-ios", threadCount: 1)]
        }
        return [
            CursorShellLiveBridge.WorkspaceRow(
                id: "lancer-ios",
                name: "lancer-ios",
                threadCount: 1,
                runTargets: [.init(machineID: "mac-mini-studio", hostName: "Mac Mini Studio")]
            )
        ]
        #else
        return []
        #endif
    }

    private var rows: [CursorShellLiveBridge.WorkspaceRow] {
        liveBridge?.workspaces ?? seedWorkspaces
    }

    public var body: some View {
        List {
            if let liveBridge, liveBridge.connectionPhase != .connected {
                Section {
                    HStack {
                        Text(connectionLabel(liveBridge.connectionPhase))
                        Spacer()
                        if liveBridge.connectionPhase == .needsPairing {
                            Button("Pair") { liveBridge.onRequestPairing?() }
                        }
                    }
                }
            }
            if let liveBridge, liveBridge.pendingApprovalID != nil {
                Section {
                    HStack {
                        Text("Approval pending")
                        Spacer()
                        Button("Review") { liveBridge.onOpenReview?() }
                        Button("Approve") {
                            guard let id = liveBridge.pendingApprovalID else { return }
                            Task { await liveBridge.onDecide?(id, .approved) }
                        }
                        Button("Reject", role: .destructive) {
                            guard let id = liveBridge.pendingApprovalID else { return }
                            Task { await liveBridge.onDecide?(id, .rejected) }
                        }
                    }
                    .accessibilityIdentifier("workspaces-approval-banner")
                }
            }

            if liveBridge != nil, rows.isEmpty {
                Section {
                    Text("No conversations yet")
                    Text("Pair a machine or send a prompt from Home.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("workspaces-empty-state")
            } else {
                Section {
                    Button {
                        onSelectWorkspace("All Repos")
                    } label: {
                        LabeledContent("All Repos", value: "\(rows.reduce(0) { $0 + $1.threadCount })")
                    }
                    .accessibilityIdentifier("workspace-row-all-repos")

                    ForEach(rows) { workspace in
                        Button {
                            onSelectWorkspace(workspace.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                LabeledContent(workspace.name, value: workspace.threadCount > 0 ? "\(workspace.threadCount)" : "")
                                if let meta = runTargetMeta(workspace) {
                                    Text(meta).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("workspace-row")
                    }
                }
            }
        }
        .navigationTitle("Workspaces")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass", action: onOpenSearch)
                Button("Pair", systemImage: "plus", action: onRequestPairing)
            }
        }
    }

    private func connectionLabel(_ phase: CursorShellLiveBridge.ConnectionPhase) -> String {
        switch phase {
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .offline: return "Offline"
        case .needsPairing: return "Needs pairing"
        }
    }

    private func runTargetMeta(_ workspace: CursorShellLiveBridge.WorkspaceRow) -> String? {
        let targets = workspace.runTargets
        guard !targets.isEmpty else { return nil }
        if targets.count == 1 { return targets[0].hostName }
        let names = targets.prefix(2).map(\.hostName).joined(separator: ", ")
        let extra = targets.count > 2 ? " +\(targets.count - 2)" : ""
        return "\(names)\(extra)"
    }
}
#endif
