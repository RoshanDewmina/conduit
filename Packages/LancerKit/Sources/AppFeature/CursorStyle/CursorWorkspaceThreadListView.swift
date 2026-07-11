#if os(iOS)
import SwiftUI
import LancerCore
import AgentKit

/// Per-workspace thread list + docked composer for new dispatch.
public struct CursorWorkspaceThreadListView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let workspaceName: String
    private let onBack: () -> Void
    private let onSelectThread: (String) -> Void
    private let onSelectObservedSession: (CursorObservedSessionMapping.RowModel) -> Void
    private let onDispatchedNewThread: () -> Void
    private let onOpenSearch: () -> Void

    public init(
        workspaceName: String,
        onBack: @escaping () -> Void = {},
        onSelectThread: @escaping (String) -> Void = { _ in },
        onSelectObservedSession: @escaping (CursorObservedSessionMapping.RowModel) -> Void = { _ in },
        onDispatchedNewThread: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {}
    ) {
        self.workspaceName = workspaceName
        self.onBack = onBack
        self.onSelectThread = onSelectThread
        self.onSelectObservedSession = onSelectObservedSession
        self.onDispatchedNewThread = onDispatchedNewThread
        self.onOpenSearch = onOpenSearch
    }

    private var allLiveThreads: [CursorShellLiveBridge.ThreadRow] {
        guard let liveBridge else { return [] }
        return liveBridge.threadsByWorkspace.values.flatMap { $0 }
    }

    private var scopedLiveRows: [CursorShellLiveBridge.ThreadRow] {
        guard let liveBridge else { return [] }
        if workspaceName == "All Repos" { return allLiveThreads }
        return liveBridge.threads(for: workspaceName)
    }

    private func threadState(for row: CursorShellLiveBridge.ThreadRow) -> CursorThreadAttention.ThreadState {
        liveBridge?.threadStates[row.id] ?? CursorThreadAttention.ThreadState()
    }

    private var sortedScopedRows: [CursorShellLiveBridge.ThreadRow] {
        sortThreadsByAttention(scopedLiveRows, updatedAt: \.updatedAt, threadState: { threadState(for: $0) })
    }

    private var needsYouRows: [CursorShellLiveBridge.ThreadRow] {
        sortedScopedRows.filter { isNeedsYouThread(threadState(for: $0)) }
    }

    private var needsYouIDs: Set<String> { Set(needsYouRows.map(\.id)) }

    private var remainderRows: [CursorShellLiveBridge.ThreadRow] {
        sortedScopedRows.filter { !needsYouIDs.contains($0.id) }
    }

    private var observedSessionRows: [CursorObservedSessionMapping.RowModel] {
        guard let liveBridge, liveBridge.relayHealthy else { return [] }
        return CursorObservedSessionMapping.RowModel.sorted(
            CursorObservedSessionMapping.RowModel.scoped(liveBridge.observedSessions, workspaceName: workspaceName)
        )
    }

    private var seedThreads: [CursorShellLiveBridge.ThreadRow] {
        #if DEBUG
        guard liveBridge == nil, workspaceName == "lancer-ios" || workspaceName == "All Repos" else {
            return []
        }
        return [
            .init(
                id: "debug-fix-onboarding",
                title: "Fix onboarding pairing flow",
                repoName: "lancer-ios",
                updatedAt: Date().addingTimeInterval(-3600)
            )
        ]
        #else
        return []
        #endif
    }

    private var composerCWDResolution: CursorComposerCWDResolution.Resolution {
        if liveBridge == nil {
            if workspaceName == "All Repos" || workspaceName.isEmpty {
                return .init(path: "~", blocked: false, message: nil)
            }
            return .init(path: "~/Documents/\(workspaceName)", blocked: false, message: nil)
        }
        return CursorComposerCWDResolution.resolve(
            repoName: workspaceName == "All Repos" ? "" : workspaceName,
            repoPaths: liveBridge?.repoPaths ?? [:],
            hasSelectedThread: liveBridge?.selectedThreadID != nil
        )
    }

    private var runTargetOptions: [CursorDockedComposer.RunTargetOption] {
        guard let liveBridge else { return [] }
        var seen: Set<String> = []
        var options: [CursorDockedComposer.RunTargetOption] = []
        for target in liveBridge.workspaces.flatMap(\.runTargets) where !seen.contains(target.machineID) {
            seen.insert(target.machineID)
            options.append(.init(id: target.machineID, title: target.hostName))
        }
        return options
    }

    private var showRepoGrouped: Bool {
        workspaceName == "All Repos" && liveBridge != nil && !allLiveThreads.isEmpty
    }

    private var groupedByRepo: [(repo: String, threads: [CursorShellLiveBridge.ThreadRow])] {
        var order: [String] = []
        var grouped: [String: [CursorShellLiveBridge.ThreadRow]] = [:]
        for row in sortThreadsByAttention(allLiveThreads, updatedAt: \.updatedAt, threadState: { threadState(for: $0) })
        where !needsYouIDs.contains(row.id) {
            if grouped[row.repoName] == nil {
                order.append(row.repoName)
            }
            grouped[row.repoName, default: []].append(row)
        }
        return order.compactMap { repo in
            guard let threads = grouped[repo], !threads.isEmpty else { return nil }
            return (repo, threads)
        }
    }

    public var body: some View {
        List {
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
                    .accessibilityIdentifier("thread-list-approval-banner")
                }
            }

            if !needsYouRows.isEmpty {
                Section("Needs you (\(needsYouRows.count))") {
                    ForEach(needsYouRows) { row in
                        Button { onSelectThread(row.id) } label: { threadLabel(row) }
                            .accessibilityIdentifier("home-needs-you-row")
                    }
                }
                .accessibilityIdentifier("home-needs-you-header")
            }

            if showRepoGrouped {
                ForEach(groupedByRepo, id: \.repo) { group in
                    Section(group.repo) {
                        ForEach(group.threads) { row in
                            Button { onSelectThread(row.id) } label: { threadLabel(row, showRepo: false) }
                        }
                    }
                    .accessibilityIdentifier("repo-section-\(group.repo)")
                }
            } else if !remainderRows.isEmpty {
                Section("Threads") {
                    ForEach(remainderRows) { row in
                        Button { onSelectThread(row.id) } label: { threadLabel(row, showRepo: false) }
                            .accessibilityIdentifier("thread-row")
                    }
                }
            } else if liveBridge == nil, !seedThreads.isEmpty {
                Section("Threads") {
                    ForEach(seedThreads) { row in
                        Button { onSelectThread(row.id) } label: { threadLabel(row) }
                            .accessibilityIdentifier("thread-row")
                    }
                }
            }

            if liveBridge != nil, needsYouRows.isEmpty, remainderRows.isEmpty, observedSessionRows.isEmpty {
                Section {
                    Text("No threads yet")
                    Text("Send a prompt below to start.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("thread-list-empty-state")
            }

            if !observedSessionRows.isEmpty {
                CursorObservedSessionsSection(rows: observedSessionRows, onSelect: onSelectObservedSession)
            }
        }
        .navigationTitle(workspaceName)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: onBack)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass", action: onOpenSearch)
            }
        }
        .safeAreaInset(edge: .bottom) {
            CursorDockedComposer(
                placeholder: "Follow up...",
                draftKey: "composer.\(workspaceName)",
                cwdResolution: composerCWDResolution,
                runTargetOptions: runTargetOptions,
                selectedRunTargetID: liveBridge?.selectedRunTargetMachineID,
                isWorking: liveBridge?.activeThreadIsWorking == true && liveBridge?.selectedThreadID == nil,
                onPickRunTarget: { id in
                    liveBridge?.selectedRunTargetMachineID = id
                    liveBridge?.selectedRunTargetHostName = runTargetOptions.first(where: { $0.id == id })?.title
                },
                onSend: { prompt in
                    let resolution = composerCWDResolution
                    guard !resolution.blocked, let cwd = resolution.path else { return }
                    if let liveBridge {
                        let model = ManagedModel.cliDispatchSlug(for: liveBridge.composerModelSlug)
                        liveBridge.activeThreadPrompt = prompt
                        liveBridge.activeThreadResponse = ""
                        liveBridge.activeRunID = nil
                        liveBridge.selectedThreadID = nil
                        liveBridge.activeThreadError = nil
                        Task { await liveBridge.onDispatch?(prompt, cwd, model, nil) }
                    }
                    onDispatchedNewThread()
                }
            )
        }
        .onAppear { liveBridge?.onRequestRefresh?() }
    }

    private func threadLabel(_ row: CursorShellLiveBridge.ThreadRow, showRepo: Bool = true) -> some View {
        let detail = CursorThreadAttention.derive(threadState(for: row)).2
        return VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
            HStack {
                if showRepo {
                    Text(row.repoName).font(.caption).foregroundStyle(.secondary)
                }
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
#endif
