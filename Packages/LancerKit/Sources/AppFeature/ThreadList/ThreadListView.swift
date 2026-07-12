#if os(iOS)
import SwiftUI
import PersistenceKit

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

/// Per-workspace thread list backed by `WorkspaceDataStore` conversations.
public struct ThreadListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceDataStore.self) private var workspaceData
    @State private var isSearchPresented = false
    @State private var isComposerPresented = false
    @State private var activeLiveThread: LiveThreadIdentifier?

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

    private var groups: [(title: String, items: [ThreadListItem])] {
        WorkspaceRepoCatalog.groupByRecency(threads)
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

                if threads.isEmpty {
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

                                ForEach(group.items) { thread in
                                    NavigationLink {
                                        ThreadDetailView(thread: thread)
                                    } label: {
                                        ThreadListRow(
                                            thread: thread,
                                            showsRepoName: workspace.isAllRepos
                                        )
                                    }
                                    .buttonStyle(.plain)
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

    private func handleSend(_ prompt: String, _ cwd: String) {
        guard WorkspaceRepoCatalog.isAbsoluteSendTarget(cwd) else { return }
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: normalized)
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

                circleButton(systemImage: "line.3.horizontal")
                    .accessibilityHidden(true)
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

#Preview {
    let db = try! PersistenceKit.AppDatabase.inMemory()
    let chatRepo = ChatConversationRepository(db)
    return NavigationStack {
        ThreadListView(workspace: .allRepos)
    }
    .environment(WorkspaceDataStore(chatRepo: chatRepo))
}
#endif
