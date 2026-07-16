#if os(iOS)
import SwiftUI
import PersistenceKit
import LancerCore

/// Scope for a thread list — either every conversation or one real repo cwd.
public enum ThreadListWorkspace: Hashable {
    case allRepos
    case repo(WorkspaceRepo)

    public var title: String {
        switch self {
        case .allRepos: return "All Repos"
        case .repo(let repo): return repo.name
        }
    }

    public var cwd: String? {
        switch self {
        case .allRepos: return nil
        case .repo(let repo): return repo.cwd
        }
    }

    public var isAllRepos: Bool {
        if case .allRepos = self { return true }
        return false
    }
}

/// Unified list row so ledger threads and desktop observed sessions share one
/// recency-grouped list without corrupting the ledger model.
enum ThreadListRowKind: Identifiable {
    case ledger(ThreadListItem)
    case desktopSession(ObservedSession)

    var id: String {
        switch self {
        case .ledger(let t): return t.id
        case .desktopSession(let s): return s.id
        }
    }

    var sortDate: Date {
        switch self {
        case .ledger(let t): return t.lastActivityAt
        case .desktopSession(let s): return s.lastActivity
        }
    }
}

/// Per-workspace thread list backed by `WorkspaceDataStore` conversations.
public struct ThreadListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceDataStore.self) private var workspaceData
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(ShellLiveBridge.self) private var bridge
    @State private var isSearchPresented = false
    @State private var isComposerPresented = false
    @State private var activeLiveThread: LiveThreadIdentifier?
    @State private var observedSessions: [ObservedSession] = []

    let workspace: ThreadListWorkspace

    public init(workspace: ThreadListWorkspace) {
        self.workspace = workspace
    }

    /// Convenience for callers that only have a display name + cwd.
    public init(workspaceName: String, cwd: String) {
        self.workspace = .repo(
            WorkspaceRepo(name: workspaceName, cwd: cwd, threadCount: 0, isUserAdded: false)
        )
    }

    private var threads: [ThreadListItem] {
        workspaceData.threads(forCwd: workspace.cwd, allRepos: workspace.isAllRepos)
    }

    /// Desktop sessions scoped to this list: all (claudeCode) for All Repos,
    /// cwd-matched for a single-repo list.
    private var scopedObservedSessions: [ObservedSession] {
        guard let cwd = workspace.cwd else { return observedSessions }
        // Exact-path equality misses sessions that ran in a worktree
        // subdirectory of this repo (e.g. `.claude/worktrees/<slug>`) — the
        // exact case that produced every session tonight. `isEqualOrUnder`
        // is the same repo/descendant check the rest of the app already uses.
        return observedSessions.filter {
            WorkspaceRepoCatalog.isEqualOrUnder(cwd: $0.cwd, repoPath: cwd)
        }
    }

    private var groups: [(title: String, items: [ThreadListRowKind])] {
        let rows: [ThreadListRowKind] =
            threads.map(ThreadListRowKind.ledger)
            + scopedObservedSessions.map(ThreadListRowKind.desktopSession)
        let sorted = rows.sorted { $0.sortDate > $1.sortDate }
        return WorkspaceRepoCatalog.groupByRecency(sorted, date: \.sortDate)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Text(workspace.title)
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 8)

                if threads.isEmpty && scopedObservedSessions.isEmpty {
                    Text("No threads yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(groups, id: \.title) { group in
                                sectionHeader(group.title)
                                    .padding(.top, group.title == groups.first?.title ? 0 : 20)

                                ForEach(group.items) { row in
                                    switch row {
                                    case .ledger(let thread):
                                        NavigationLink {
                                            ThreadDetailView(thread: thread)
                                                .onAppear {
                                                    workspaceData.markThreadOpened(thread.id)
                                                }
                                        } label: {
                                            ThreadListRow(
                                                thread: thread,
                                                showsRepoName: workspace.isAllRepos
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    case .desktopSession(let session):
                                        Button {
                                            // Match WorkspacesView RunningAgentsSection continue path.
                                            bridge.armObservedContinue(
                                                vendor: session.provider,
                                                sessionId: session.sessionId,
                                                cwd: session.cwd
                                            )
                                            activeLiveThread = LiveThreadIdentifier(
                                                prompt: "",
                                                cwd: session.cwd
                                            )
                                        } label: {
                                            DesktopSessionListRow(
                                                session: session,
                                                showsRepoName: workspace.isAllRepos,
                                                isHostConnected: relayFleetStore.firstConnectedMachine != nil
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Divider()
                                        .padding(.leading, 40)
                                }
                            }
                        }
                        .padding(.bottom, 90)
                    }
                }
            }

            Button {
                isComposerPresented = true
            } label: {
                composer
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("New Chat"))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await workspaceData.refresh()
            await loadObservedSessions()
        }
        .sheet(isPresented: $isSearchPresented) {
            SearchView()
        }
        .sheet(isPresented: $isComposerPresented) {
            NewChatComposerView(
                initialRepo: workspaceCwdRepo,
                // Inside a specific repo the composer is pinned to it —
                // never silently substitute another repo (owner report).
                lockRepo: isInsideSpecificRepo,
                onSend: handleSend
            )
        }
        .liveThreadPresentation($activeLiveThread)
    }

    private func loadObservedSessions() async {
        guard let machine = relayFleetStore.firstConnectedMachine else {
            observedSessions = []
            return
        }
        let sessions = (try? await machine.bridge.relayListSessions()) ?? []
        // Other providers (codex, etc.) are future work — model already has `provider`.
        observedSessions = sessions.filter { $0.provider == "claudeCode" }
    }

    private var isInsideSpecificRepo: Bool {
        if case .repo(let repo) = workspace {
            return WorkspaceRepoCatalog.isAbsoluteSendTarget(repo.cwd)
        }
        return false
    }

    private var workspaceCwdRepo: WorkspaceRepo? {
        switch workspace {
        case .allRepos:
            return workspaceData.repos.first { WorkspaceRepoCatalog.isAbsoluteSendTarget($0.cwd) }
        case .repo(let repo):
            if WorkspaceRepoCatalog.isAbsoluteSendTarget(repo.cwd) {
                return repo
            }
            return nil
        }
    }

    private func handleSend(_ prompt: String, _ cwd: String, _ attachments: [ConversationAttachmentReference] = []) {
        guard WorkspaceRepoCatalog.isAbsoluteSendTarget(cwd) else { return }
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        // Same stacked-sheet hazard as WorkspacesView.handleSend — dismiss
        // the composer explicitly instead of letting it race the live-thread
        // sheet's presentation.
        isComposerPresented = false
        activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: normalized, attachments: attachments)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                circleButton(systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            Spacer()

            HStack(spacing: 12) {
                Button {
                    isSearchPresented = true
                } label: {
                    circleButton(systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Search"))
            }
        }
    }

    private func circleButton(systemImage: String) -> some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private var composer: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                )

            Text("Plan, ask, build…")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Spacer()

            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
    }
}

/// Desktop Claude Code session row — matches `ThreadListRow` padding/typography
/// with a desktop icon + "Desktop" capsule badge.
private struct DesktopSessionListRow: View {
    let session: ObservedSession
    var showsRepoName: Bool = false
    var isHostConnected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 8, alignment: .center)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.title.isEmpty ? "Untitled session" : session.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Desktop")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }

                HStack(spacing: 4) {
                    Text(isHostConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 14))
                        .foregroundStyle(isHostConnected ? .green : .secondary)

                    Text("· \(relativeActivity)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    if showsRepoName {
                        Text("· \(WorkspaceRepoCatalog.displayName(forCwd: session.cwd))")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var relativeActivity: String {
        ThreadListMetadata.relativeActivity(session.lastActivity)
    }
}

#Preview {
    let db = try! PersistenceKit.AppDatabase.inMemory()
    let chatRepo = ChatConversationRepository(db)
    return NavigationStack {
        ThreadListView(workspace: .allRepos)
    }
    .environment(WorkspaceDataStore(chatRepo: chatRepo))
}
#endif
