#if os(iOS)
import SwiftUI
import UIKit
import PersistenceKit
import LancerCore

/// Workspaces launch screen — real repos derived from conversations +
/// user-added paths; honest empty state when none exist.
public struct WorkspacesView: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(WorkspaceDataStore.self) private var workspaceData
    @Environment(ShellLiveBridge.self) private var shellLiveBridge
    @Environment(\.scenePhase) private var scenePhase
    @State private var isProfilePresented = false
    @State private var isComposerPresented = false
    @State private var isAddRepoPresented = false
    @State private var isSearchPresented = false
    @State private var activeLiveThread: LiveThreadIdentifier?
    @Namespace private var composerMorphNamespace
    private let composerMorphSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    @Environment(TerminalSessionCoordinator.self) private var terminalCoordinator
    #if DEBUG
    @Environment(RelayApprovalIngest.self) private var relayApprovalIngest
    @State private var isSettingsPresented = false
    @State private var isAccountsPresented = false
    @State private var isComposerRepoPickerPresented = false
    @State private var isRepoPickerDirectPresented = false
    @State private var isThreadListDirectPresented = false
    @State private var isContextDirectPresented = false
    @State private var isThreadDetailDirectPresented = false
    @State private var isPRDetailDirectPresented = false
    @State private var isTrustedMachinesDirectPresented = false
    @State private var isAttachmentPreviewDirectPresented = false
    @State private var isReviewPresented = false
    #endif

    public init() {}

    private var repos: [WorkspaceRepo] { workspaceData.repos }

    public var body: some View {
        ZStack {
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

                ScrollView {
                    VStack(spacing: 0) {
                        PendingApprovalsBanner { machineID, approval in
                            shellLiveBridge.focusMachineForPendingApproval(machineID)
                            let cwd = approval.cwd.isEmpty
                                ? (repos.first?.cwd ?? "")
                                : approval.cwd
                            activeLiveThread = LiveThreadIdentifier(prompt: "", cwd: cwd)
                        }

                        NavigationLink {
                            ThreadListView(workspace: .allRepos)
                        } label: {
                            WorkspaceRowView(
                                title: "All Repos",
                                systemImage: "square.stack",
                                subtitle: "\(workspaceData.allReposThreadCount)",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, 58)

                        if repos.isEmpty {
                            Text("Add a repo to get started")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 20)
                            Divider()
                                .padding(.leading, 58)
                        } else {
                            ForEach(repos) { repo in
                                NavigationLink {
                                    ThreadListView(workspace: .repo(repo))
                                } label: {
                                    WorkspaceRowView(
                                        title: repo.name,
                                        systemImage: "folder",
                                        subtitle: "\(repo.threadCount)",
                                        showsChevron: true
                                    )
                                }
                                .buttonStyle(.plain)
                                Divider()
                                    .padding(.leading, 58)
                            }
                        }

                        Button {
                            isAddRepoPresented = true
                        } label: {
                            WorkspaceRowView(
                                title: "Add Repo",
                                systemImage: "folder.badge.plus",
                                subtitle: nil,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, 58)

                        RunningAgentsSection { session, prompt in
                            // Agents row tap passes an empty prompt: arm + present
                            // LiveThread directly; adopt hydrates, first follow-up continues.
                            shellLiveBridge.armObservedContinue(
                                vendor: session.provider,
                                sessionId: session.sessionId,
                                cwd: session.cwd
                            )
                            activeLiveThread = LiveThreadIdentifier(
                                prompt: prompt,
                                cwd: session.cwd
                            )
                        }
                    }
                    .padding(.bottom, 16)
                }
            }

            if isComposerPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        collapseComposer(animated: true)
                    }
                    .accessibilityHidden(true)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if isComposerPresented {
                    inlineExpandedComposer
                        .matchedGeometryEffect(id: "workspacesComposer", in: composerMorphNamespace)
                        .transition(.identity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                } else {
                    Button {
                        expandComposer()
                    } label: {
                        composer
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("New Chat"))
                    .accessibilityIdentifier("cursor-composer-tap")
                    .matchedGeometryEffect(id: "workspacesComposer", in: composerMorphNamespace)
                    .transition(.identity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .animation(composerMorphSpring, value: isComposerPresented)
        .task {
            await workspaceData.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await workspaceData.refresh() }
        }
        .sheet(isPresented: $isProfilePresented) {
            ProfileView()
                .environment(relayFleetStore)
                .environment(terminalCoordinator)
        }
        .sheet(isPresented: $isAddRepoPresented) {
            AddRepoView { name, cwd in
                workspaceData.addRepo(name: name, cwd: cwd)
            }
        }
        .sheet(isPresented: $isSearchPresented) {
            SearchView()
        }
        .liveThreadPresentation($activeLiveThread)
        #if DEBUG
        .sheet(isPresented: $isSettingsPresented) {
            AppSettingsView()
                .environment(relayFleetStore)
                .environment(terminalCoordinator)
        }
        .sheet(isPresented: $isAccountsPresented) {
            NavigationStack {
                AccountsUsageView()
                    .environment(relayFleetStore)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isAccountsPresented = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isRepoPickerDirectPresented) {
            RepoPickerView(repos: repos, selectedCwd: repos.first?.cwd, onSelect: { _ in })
        }
        .sheet(isPresented: $isContextDirectPresented) {
            ContextAttachView()
        }
        .sheet(isPresented: $isTrustedMachinesDirectPresented) {
            NavigationStack {
                TrustedMachinesView(embedsInParentNavigation: true)
            }
            .environment(relayFleetStore)
            .environment(terminalCoordinator)
        }
        .sheet(isPresented: $isAttachmentPreviewDirectPresented) {
            AttachmentPreviewDemoView()
        }
        .sheet(isPresented: $isReviewPresented) {
            ReviewSheetView(
                conversationID: "debug-review-fixture",
                scope: .session,
                dataSource: FixtureReviewDataSource.shared
            )
        }
        .navigationDestination(isPresented: $isThreadListDirectPresented) {
            if let first = repos.first {
                ThreadListView(workspace: .repo(first))
            } else {
                ThreadListView(workspace: .allRepos)
            }
        }
        .navigationDestination(isPresented: $isThreadDetailDirectPresented) {
            if let first = workspaceData.threads(forCwd: nil, allRepos: true).first {
                ThreadDetailView(thread: first)
            } else {
                ThreadDetailView(
                    thread: ThreadListItem(
                        id: "debug-empty",
                        title: "No threads yet",
                        statusKind: .idle,
                        statusLabel: WorkspaceRepoCatalog.statusLabel(.idle),
                        repoName: nil,
                        cwd: "",
                        lastActivityAt: .now
                    )
                )
            }
        }
        .navigationDestination(isPresented: $isPRDetailDirectPresented) {
            PRDetailView()
        }
        .onAppear {
            switch ProcessInfo.processInfo.environment["LANCER_DESTINATION"] {
            case "profile":
                isProfilePresented = true
            case "settings", "governance":
                // governance → Settings with honest deferred Policy & Governance
                // (no fake Apply / PolicyHome). Same sheet as settings.
                isSettingsPresented = true
            case "accounts":
                isAccountsPresented = true
            case "review":
                // DEBUG fixture seam for ReviewSheetView (LANCER_DESTINATION=review
                // was removed with CursorStyle; restore for sim/UITest without host diffs).
                isReviewPresented = true
            case "approval":
                Task {
                    await relayApprovalIngest.hydratePendingForUITestIfRequested()
                    shellLiveBridge.configureUITestMachineContextIfNeeded()
                    let prompt = ProcessInfo.processInfo.environment["LANCER_LIVETHREAD_PROMPT"]
                        ?? "Review the pending approval"
                    let cwd = ProcessInfo.processInfo.environment["LANCER_LIVETHREAD_CWD"]
                        ?? workspaceData.defaultRepo?.cwd
                        ?? "/home/ubuntu/myapp"
                    activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: cwd)
                }
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
            case "attachmentPreview":
                isAttachmentPreviewDirectPresented = true
            case "liveThread":
                Task {
                    // Match `terminal`: hydrate + auto-pair can take >20s; opening
                    // the thread immediately raced `waitForConnectedMachine`'s
                    // empty-fleet fail-fast (L1 serial 2026-07-19).
                    var connected = relayFleetStore.firstConnectedMachine
                    let deadline = Date().addingTimeInterval(45)
                    while connected == nil, Date() < deadline {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        connected = relayFleetStore.firstConnectedMachine
                    }
                    let prompt = ProcessInfo.processInfo.environment["LANCER_LIVETHREAD_PROMPT"]
                        ?? "Can you take a look at the onboarding flow?"
                    let cwd = ProcessInfo.processInfo.environment["LANCER_LIVETHREAD_CWD"]
                        ?? workspaceData.defaultRepo?.cwd
                        ?? ""
                    guard !cwd.isEmpty else { return }
                    activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: cwd)
                }
            case "search":
                isSearchPresented = true
            case "terminal":
                Task {
                    // Hydration + autoPair run in AppRoot.task; wait before opening.
                    var connected = relayFleetStore.firstConnectedMachine
                    let deadline = Date().addingTimeInterval(30)
                    while connected == nil, Date() < deadline {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        connected = relayFleetStore.firstConnectedMachine
                    }
                    let startup = ProcessInfo.processInfo.environment["LANCER_TERMINAL_STARTUP_COMMAND"]
                    await terminalCoordinator.openOnFirstConnectedMachine(startupCommand: startup)
                }
            default:
                break
            }
        }
        #endif
    }

    private func handleSend(_ prompt: String, _ cwd: String, _ attachments: [ConversationAttachmentReference] = []) {
        guard WorkspaceRepoCatalog.isAbsoluteSendTarget(cwd) else { return }
        let normalized = WorkspaceRepoCatalog.normalizeCwd(cwd)
        // Collapse the inline composer immediately (no spring) before the
        // live thread pushes — otherwise the composer's TextEditor
        // (still showing the just-sent prompt) remains enumerable by the
        // accessibility tree during its morph-out at the same time the live
        // thread's prompt bubble renders, reading as a duplicate turn to
        // AX-tree-based tests (found in the 2026-07-15 reconnect re-proof).
        collapseComposer(animated: false)
        activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: normalized, attachments: attachments)
    }

    private func expandComposer() {
        withAnimation(composerMorphSpring) {
            isComposerPresented = true
        }
    }

    private func collapseComposer(animated: Bool) {
        #if DEBUG
        isComposerRepoPickerPresented = false
        #endif
        if animated {
            withAnimation(composerMorphSpring) {
                isComposerPresented = false
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isComposerPresented = false
            }
        }
    }

    @ViewBuilder
    private var inlineExpandedComposer: some View {
        #if DEBUG
        NewChatComposerView(
            initiallyShowsRepoPicker: isComposerRepoPickerPresented,
            initialRepo: workspaceData.defaultRepo,
            hostStyle: .inline,
            onCollapse: { collapseComposer(animated: true) },
            onSend: handleSend
        )
        #else
        NewChatComposerView(
            initialRepo: workspaceData.defaultRepo,
            hostStyle: .inline,
            onCollapse: { collapseComposer(animated: true) },
            onSend: handleSend
        )
        #endif
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
                    expandComposer()
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
    }
}

private struct WorkspaceRowView: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(.primary)

            Spacer()

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            if showsChevron {
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

/// DEBUG/UITest destination: seeded attachment bubble (thumbnail + file card)
/// without requiring a live paired daemon.
#if DEBUG
struct AttachmentPreviewDemoView: View {
    @Environment(\.dismiss) private var dismiss
    private let cache: AttachmentPreviewCaching
    private let attachments: [ConversationAttachmentReference]

    init() {
        let resolved: AttachmentPreviewCaching
        if let cache = try? AttachmentPreviewCache() {
            resolved = cache
        } else {
            resolved = NullAttachmentPreviewCache()
        }
        let imageKey = "demo-image"
        let fileKey = "demo-file"
        if let jpeg = Self.tinyJPEG(),
           let preview = AttachmentPreviewCache.makePreviewData(from: jpeg, mimeType: "image/jpeg") {
            try? resolved.storePreview(preview, for: imageKey)
        }
        self.cache = resolved
        let digest = String(repeating: "ab", count: 32)
        self.attachments = [
            ConversationAttachmentReference(
                id: "srv-demo-image", name: "sunset.jpg", mimeType: "image/jpeg",
                byteCount: 24_576, kind: .image,
                hostPath: "/Users/demo/.lancer/attachments/objects/\(digest)",
                previewCacheKey: imageKey,
                contentDigest: digest
            ),
            ConversationAttachmentReference(
                id: "srv-demo-file", name: "notes.pdf", mimeType: "application/pdf",
                byteCount: 8_192, kind: .file,
                hostPath: "/Users/demo/.lancer/attachments/objects/\(String(repeating: "cd", count: 32))",
                previewCacheKey: fileKey,
                contentDigest: String(repeating: "cd", count: 32)
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Seeded attachment render")
                        .font(.headline)
                        .accessibilityIdentifier("attachment-preview-demo.title")
                    ChatUserBubble(
                        text: "Describe this image and the PDF",
                        attachments: attachments,
                        previewCache: cache
                    )
                    .accessibilityIdentifier("attachment-preview-demo.bubble")
                }
                .padding(20)
            }
            .navigationTitle("Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    /// Minimal valid JPEG so thumbnail generation works offline.
    private static func tinyJPEG() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48))
        let image = renderer.image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 12, y: 12, width: 40, height: 24))
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}
#endif

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
    let questionIngest = RelayQuestionIngest(chatRepo: chatRepo)
    let workspaceData = WorkspaceDataStore(chatRepo: chatRepo)
    return NavigationStack {
        WorkspacesView()
    }
    .environment(relayFleetStore)
    .environment(bridge)
    .environment(approvalIngest)
    .environment(questionIngest)
    .environment(workspaceData)
}
#endif
