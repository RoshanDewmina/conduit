#if os(iOS)
import SwiftUI
import PersistenceKit

/// Section 1 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile "Workspaces" launch screen (owner reference screenshots
/// `IMG_2408`/`IMG_2423`). Visual-only for this milestone — rows and the
/// composer are static sample data with no navigation, no sheets, and no
/// live wiring. System `SF Symbols` + semantic colors only, no DesignSystem
/// module.
public struct WorkspacesView: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(ShellLiveBridge.self) private var shellLiveBridge
    @Environment(RelayApprovalIngest.self) private var relayApprovalIngest
    @State private var isProfilePresented = false
    @State private var isComposerPresented = false
    @State private var isAddRepoPresented = false
    @State private var isSearchPresented = false
    /// M3: set by the composer's send action (`onSend`); presented via
    /// `.sheet(item:)` to show the new live conversation. `Identifiable` so
    /// `.sheet(item:)` can key off it; a fresh `UUID` per send keeps repeat
    /// sends from reusing a stale sheet identity.
    @State private var activeLiveThread: LiveThreadIdentifier?
    /// M3: no repo-picker wiring yet — hardcoded placeholder cwd for the
    /// live send flow (out of scope for this milestone per the brief).
    private static let placeholderCwd = "~"
    #if DEBUG
    @State private var isComposerRepoPickerPresented = false
    @State private var isRepoPickerDirectPresented = false
    @State private var isThreadListDirectPresented = false
    @State private var isContextDirectPresented = false
    @State private var isThreadDetailDirectPresented = false
    @State private var isPRDetailDirectPresented = false
    @State private var isTrustedMachinesDirectPresented = false
    #endif

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Text("Workspaces")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Self.rows) { row in
                        if row.title == "Add Repo" {
                            Button {
                                isAddRepoPresented = true
                            } label: {
                                WorkspaceRowView(row: row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                ThreadListView(workspaceName: row.title)
                            } label: {
                                WorkspaceRowView(row: row)
                            }
                            .buttonStyle(.plain)
                        }
                        Divider()
                            .padding(.leading, 58)
                    }
                }

                Spacer(minLength: 0)
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
        .sheet(isPresented: $isProfilePresented) {
            ProfileView()
                .environment(relayFleetStore)
        }
        .sheet(isPresented: $isComposerPresented) {
            #if DEBUG
            NewChatComposerView(initiallyShowsRepoPicker: isComposerRepoPickerPresented, onSend: handleSend)
            #else
            NewChatComposerView(onSend: handleSend)
            #endif
        }
        .sheet(isPresented: $isAddRepoPresented) {
            AddRepoView()
        }
        .sheet(isPresented: $isSearchPresented) {
            SearchView()
        }
        .sheet(item: $activeLiveThread) { thread in
            LiveThreadView(prompt: thread.prompt, cwd: thread.cwd)
                .environment(shellLiveBridge)
                .environment(relayApprovalIngest)
        }
        #if DEBUG
        .sheet(isPresented: $isRepoPickerDirectPresented) {
            RepoPickerView()
        }
        #endif
        #if DEBUG
        .sheet(isPresented: $isContextDirectPresented) {
            ContextAttachView()
        }
        #endif
        #if DEBUG
        .sheet(isPresented: $isTrustedMachinesDirectPresented) {
            TrustedMachinesView()
                .environment(relayFleetStore)
        }
        #endif
        #if DEBUG
        .navigationDestination(isPresented: $isThreadListDirectPresented) {
            ThreadListView(workspaceName: "conduit")
        }
        #endif
        #if DEBUG
        .navigationDestination(isPresented: $isThreadDetailDirectPresented) {
            ThreadDetailView(thread: ThreadRow(title: "Fix onboarding flow", status: .checksPassed, diffStat: "+142 -18"))
        }
        #endif
        #if DEBUG
        .navigationDestination(isPresented: $isPRDetailDirectPresented) {
            PRDetailView()
        }
        #endif
        #if DEBUG
        .onAppear {
            switch ProcessInfo.processInfo.environment["LANCER_DESTINATION"] {
            case "profile":
                isProfilePresented = true
            case "composer":
                isComposerPresented = true
            case "repoPicker":
                isComposerRepoPickerPresented = true
                isComposerPresented = true
            case "addRepo":
                isAddRepoPresented = true
            case "repoPickerDirect":
                isRepoPickerDirectPresented = true
            case "context":
                isContextDirectPresented = true
            case "threadList":
                isThreadListDirectPresented = true
            case "threadDetail":
                isThreadDetailDirectPresented = true
            case "prDetail":
                isPRDetailDirectPresented = true
            case "trustedMachines":
                isTrustedMachinesDirectPresented = true
            case "liveThread":
                let prompt = ProcessInfo.processInfo.environment["LANCER_LIVETHREAD_PROMPT"]
                    ?? "Can you take a look at the onboarding flow?"
                activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: Self.placeholderCwd)
            case "search":
                isSearchPresented = true
            default:
                break
            }
        }
        #endif
    }

    /// M3: the composer's `onSend` hand-off — presents `LiveThreadView` via
    /// `.sheet(item:)`. `ShellLiveBridge.send` is triggered by that view's
    /// own `.task`, not here, so this stays a pure state-setting hop.
    private func handleSend(_ prompt: String) {
        activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: Self.placeholderCwd)
    }

    private var topBar: some View {
        HStack {
            Button {
                isProfilePresented = true
            } label: {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.75), Color.purple.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Profile"))

            Spacer()

            HStack(spacing: 12) {
                Button {
                    isSearchPresented = true
                } label: {
                    circleButton(systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Search"))

                Button {
                    isComposerPresented = true
                } label: {
                    circleButton(systemImage: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("New Chat"))
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

    fileprivate static let rows: [WorkspaceRow] = [
        WorkspaceRow(title: "All Repos", systemImage: "square.stack", showsChevron: true),
        WorkspaceRow(title: "conduit", systemImage: "folder", showsChevron: true),
        WorkspaceRow(title: "personal-web", systemImage: "folder", showsChevron: true),
        WorkspaceRow(title: "Add Repo", systemImage: "folder.badge.plus", showsChevron: false),
    ]
}

/// M3: identifies one live-send `LiveThreadView` presentation. A fresh id
/// per `handleSend` call ensures `.sheet(item:)` always treats a new send as
/// a new sheet instance, even if the prompt text happens to repeat.
private struct LiveThreadIdentifier: Identifiable {
    let id = UUID()
    let prompt: String
    let cwd: String
}

private struct WorkspaceRow: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let showsChevron: Bool
}

private struct WorkspaceRowView: View {
    let row: WorkspaceRow

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: row.systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(row.title)
                .font(.system(size: 17))
                .foregroundStyle(.primary)

            Spacer()

            if row.showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    let relayFleetStore = RelayFleetStore()
    let db = try! PersistenceKit.AppDatabase.inMemory()
    let chatRepo = ChatConversationRepository(db)
    let coordinator = ConversationSyncCoordinator(chatRepo: chatRepo)
    let bridge = ShellLiveBridge(
        relayFleetStore: relayFleetStore,
        conversationSyncCoordinator: coordinator,
        chatRepo: chatRepo
    )
    let approvalIngest = RelayApprovalIngest(database: db)
    return NavigationStack {
        WorkspacesView()
    }
    .environment(relayFleetStore)
    .environment(bridge)
    .environment(approvalIngest)
}
#endif
