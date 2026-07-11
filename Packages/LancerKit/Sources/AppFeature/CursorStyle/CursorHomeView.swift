#if os(iOS)
import SwiftUI
import LancerCore
import AgentKit

/// Home root — needs-you + recent threads + docked composer (dispatch to `~`).
public struct CursorHomeView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let onOpenThread: (String) -> Void
    private let onDispatchedNewThread: () -> Void
    private let onOpenSearch: () -> Void

    public init(
        onOpenThread: @escaping (String) -> Void = { _ in },
        onDispatchedNewThread: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {}
    ) {
        self.onOpenThread = onOpenThread
        self.onDispatchedNewThread = onDispatchedNewThread
        self.onOpenSearch = onOpenSearch
    }

    private var allLiveThreads: [CursorShellLiveBridge.ThreadRow] {
        guard let liveBridge else { return [] }
        return liveBridge.threadsByWorkspace.values.flatMap { $0 }
    }

    private func threadState(for row: CursorShellLiveBridge.ThreadRow) -> CursorThreadAttention.ThreadState {
        liveBridge?.threadStates[row.id] ?? CursorThreadAttention.ThreadState()
    }

    private var sortedThreads: [CursorShellLiveBridge.ThreadRow] {
        guard liveBridge != nil else { return [] }
        return sortThreadsByAttention(allLiveThreads, updatedAt: \.updatedAt, threadState: { threadState(for: $0) })
    }

    private var needsYouRows: [CursorShellLiveBridge.ThreadRow] {
        sortedThreads.filter { isNeedsYouThread(threadState(for: $0)) }
    }

    private var recentRows: [CursorShellLiveBridge.ThreadRow] {
        let needsIDs = Set(needsYouRows.map(\.id))
        return sortedThreads.filter { !needsIDs.contains($0.id) }.prefix(10).map { $0 }
    }

    private var statusMessage: String? {
        guard let liveBridge else { return nil }
        return homeAttentionStatusMessage(
            needsYouCount: needsYouRows.count,
            relayHealthy: liveBridge.relayHealthy,
            lastSnapshotAt: liveBridge.lastSnapshotAt
        )
    }

    public var body: some View {
        List {
            if let liveBridge, liveBridge.connectionPhase != .connected {
                Section {
                    connectionRow(liveBridge)
                }
            }
            if let liveBridge, liveBridge.pendingApprovalID != nil {
                Section {
                    approvalRow(liveBridge)
                        .accessibilityIdentifier("home-approval-banner")
                }
            }
            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("home-attention-status")
                }
            }
            if !needsYouRows.isEmpty {
                Section("Needs you (\(needsYouRows.count))") {
                    ForEach(needsYouRows) { row in
                        Button { onOpenThread(row.id) } label: { threadLabel(row) }
                            .accessibilityIdentifier("home-needs-you-row")
                    }
                }
                .accessibilityIdentifier("home-needs-you-header")
            }
            if !recentRows.isEmpty {
                Section("Recent") {
                    ForEach(recentRows) { row in
                        Button { onOpenThread(row.id) } label: { threadLabel(row) }
                    }
                }
            }
            if liveBridge != nil, needsYouRows.isEmpty, recentRows.isEmpty {
                Section {
                    Text("All clear")
                    Text("Start a prompt below, or pair a machine.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass", action: onOpenSearch)
            }
        }
        .safeAreaInset(edge: .bottom) {
            CursorDockedComposer(
                placeholder: "Plan, ask, build...",
                draftKey: "composer.home",
                cwdResolution: .init(path: "~", blocked: false, message: nil),
                isWorking: liveBridge?.activeThreadIsWorking == true && liveBridge?.selectedThreadID == nil,
                onSend: { prompt in
                    if let liveBridge {
                        let model = ManagedModel.cliDispatchSlug(for: liveBridge.composerModelSlug)
                        liveBridge.activeThreadPrompt = prompt
                        liveBridge.activeThreadResponse = ""
                        liveBridge.activeRunID = nil
                        liveBridge.selectedThreadID = nil
                        liveBridge.activeThreadError = nil
                        Task { await liveBridge.onDispatch?(prompt, "~", model, nil) }
                    }
                    onDispatchedNewThread()
                }
            )
        }
    }

    private func threadLabel(_ row: CursorShellLiveBridge.ThreadRow) -> some View {
        let detail = CursorThreadAttention.derive(threadState(for: row)).2
        return VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
            HStack {
                Text(row.repoName).font(.caption).foregroundStyle(.secondary)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func connectionRow(_ bridge: CursorShellLiveBridge) -> some View {
        HStack {
            Text(connectionLabel(bridge.connectionPhase))
            Spacer()
            if bridge.connectionPhase == .needsPairing {
                Button("Pair") { bridge.onRequestPairing?() }
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

    private func approvalRow(_ bridge: CursorShellLiveBridge) -> some View {
        HStack {
            Text("Approval pending")
            Spacer()
            Button("Review") { bridge.onOpenReview?() }
            Button("Approve") {
                guard let id = bridge.pendingApprovalID else { return }
                Task { await bridge.onDecide?(id, .approved) }
            }
            Button("Reject", role: .destructive) {
                guard let id = bridge.pendingApprovalID else { return }
                Task { await bridge.onDecide?(id, .rejected) }
            }
        }
    }
}
#endif
