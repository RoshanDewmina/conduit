#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import NotificationsKit
import PersistenceKit

/// Every reachable push destination in the Cursor-style demo shell. There is
/// exactly one navigation stack — no tab bar — matching Cursor's own app,
/// which has a single root (Workspaces) with everything else either pushed
/// onto that one stack or presented as a sheet/drawer on top of it.
private enum CursorRoute: Hashable {
    case workspaceThreadList(String)
    case workThread(String)
    case prDetail
    case reviewDiff
}

/// Cohesive, clickable navigation shell wiring every Cursor-styled mock screen
/// in `CursorStyle/` together with mock/seeded data. Navigation-only — no real
/// data wiring, no daemon calls. Lets the owner tap through the whole
/// redesign end-to-end before any real backend integration happens.
///
/// Deliberately has no `TabView`: Cursor's own app is a single stack rooted at
/// the Workspaces list, with account (Profile drawer), repo switching (Repo
/// Picker drawer), and search all presented as sheets/overlays on top of that
/// one stack rather than separate tab roots.
public struct CursorAppShell: View {
    private let liveBridge: CursorShellLiveBridge?

    // `LANCER_SKIP_CURSOR_ONBOARDING=1` lets automated UI tests (and manual
    // debugging) reach the main shell directly without re-tapping through
    // onboarding every launch — same pattern as AppRoot's existing
    // `LANCER_DESTINATION`/`LANCER_SEED_DEMO` DEBUG-only launch seams.
    #if DEBUG
    @State private var hasCompletedOnboarding: Bool
    // `LANCER_CURSOR_MOCK_RUN_TARGETS=1` seeds fake run targets for the mock
    // shell (liveBridge == nil) so UITests can reach CursorWorkspaceDetailSheet
    // without any real daemon connection.
    private let mockWorkspaces: [CursorShellLiveBridge.WorkspaceRow]
    #else
    @State private var hasCompletedOnboarding = false
    #endif
    @State private var path = NavigationPath()

    @State private var showingProfileDrawer = false
    @State private var showingSettingsFromProfile = false
    @State private var showingSearchOverlay = false
    @State private var showingRepoPicker = false
    @State private var showingComposerSheet = false
    @State private var showingRunOnSheet = false
    @State private var showingModelSheet = false
    @State private var composerPlaceholder = "Plan, ask, build..."
    @State private var mockSelectedRunTargetID = "mock-mac-mini-studio"
    @State private var detailWorkspace: CursorShellLiveBridge.WorkspaceRow? = nil
    /// Set by `handleSiriNavigation(.search)` right before opening the search
    /// overlay so it can prefill/run the same query Siri already spoke a
    /// result count for, instead of opening a blank search (I2).
    @State private var pendingSearchQuery: String? = nil

    private var composerRepoName: String {
        guard let liveBridge else { return "lancer-ios" }
        return liveBridge.composerCWD.isEmpty ? "Home" : liveBridge.composerCWD
    }

    private var runTargetOptions: [CursorRunOnSheet.CursorRunTargetOption] {
        guard let liveBridge else { return [] }
        let selectedID = liveBridge.selectedRunTargetMachineID
        var seen: Set<String> = []
        var options: [CursorRunOnSheet.CursorRunTargetOption] = []
        for target in liveBridge.workspaces.flatMap(\.runTargets) where !seen.contains(target.machineID) {
            seen.insert(target.machineID)
            options.append(.init(
                id: target.machineID,
                icon: "desktopcomputer",
                title: target.hostName,
                isSelected: target.machineID == selectedID
            ))
        }
        return options
    }

    private var runTargetSheetActive: [CursorRunOnSheet.CursorRunTargetOption] {
        if liveBridge == nil {
            return mockRunTargetOptions.filter(\.isSelected)
        }
        let selected = runTargetOptions.filter(\.isSelected)
        return selected.isEmpty ? [] : selected
    }

    private var runTargetSheetMore: [CursorRunOnSheet.CursorRunTargetOption] {
        if liveBridge == nil {
            return mockRunTargetOptions.filter { !$0.isSelected }
        }
        return runTargetOptions.filter { !$0.isSelected }
    }

    private var composerRunTargetName: String? {
        if let liveBridge {
            return liveBridge.selectedRunTargetHostName
        }
        return mockRunTargetOptions.first(where: { $0.id == mockSelectedRunTargetID })?.title
    }

    private var activeRepoOption: CursorRepoPickerOption? {
        guard liveBridge != nil else { return nil }
        return CursorRepoPickerOption(
            id: "live-\(composerRepoName)",
            orgName: "Local",
            repoName: composerRepoName,
            branchName: nil
        )
    }

    private var liveRepoOptions: [CursorRepoPickerOption]? {
        guard let liveBridge else { return nil }
        return liveBridge.workspaces.map {
            CursorRepoPickerOption(id: "live-\($0.id)", orgName: "Local", repoName: $0.name)
        }
    }

    private var mockRepoPickerActive: CursorRepoPickerOption {
        CursorRepoPickerOption(id: "mock-active-lancer-ios", orgName: "RoshanDewmina", repoName: "lancer-ios", branchName: "master")
    }

    private var mockRepoPickerMore: [CursorRepoPickerOption] {
        [
            CursorRepoPickerOption(id: "mock-more-command-center", orgName: "RoshanDewmina", repoName: "command-center"),
            CursorRepoPickerOption(id: "mock-more-hermes", orgName: "roshandewmina", repoName: "hermes")
        ]
    }

    private var mockRunTargetOptions: [CursorRunOnSheet.CursorRunTargetOption] {
        [
            .init(id: "mock-mac-mini-studio", icon: "desktopcomputer", title: "Mac Mini Studio", isSelected: mockSelectedRunTargetID == "mock-mac-mini-studio"),
            .init(id: "mock-home-server", icon: "server.rack", title: "Home Server", isSelected: mockSelectedRunTargetID == "mock-home-server")
        ]
    }

    public init(liveBridge: CursorShellLiveBridge? = nil) {
        self.liveBridge = liveBridge
        #if DEBUG
        let skipEnv = ProcessInfo.processInfo.environment["LANCER_SKIP_CURSOR_ONBOARDING"] == "1"
        _hasCompletedOnboarding = State(initialValue: liveBridge != nil || skipEnv)
        if ProcessInfo.processInfo.environment["LANCER_CURSOR_MOCK_RUN_TARGETS"] == "1" {
            mockWorkspaces = [
                .init(
                    id: "lancer-ios",
                    name: "lancer-ios",
                    threadCount: 4,
                    runTargets: [
                        .init(machineID: "mac-mini-studio", hostName: "Mac Mini Studio"),
                        .init(machineID: "home-server",     hostName: "Home Server"),
                    ]
                )
            ]
        } else {
            mockWorkspaces = []
        }
        #else
        _hasCompletedOnboarding = State(initialValue: liveBridge != nil)
        #endif
    }

    public var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainStack
            } else {
                CursorOnboardingView(onComplete: { hasCompletedOnboarding = true })
            }
        }
        .environment(\.cursorShellLiveBridge, liveBridge)
    }

    #if DEBUG
    private func applyDebugRouteIfNeeded() {
        guard hasCompletedOnboarding, path.isEmpty else { return }
        switch ProcessInfo.processInfo.environment["LANCER_CURSOR_ROUTE"] {
        case "reviewDiff":
            path.append(CursorRoute.reviewDiff)
        case "prDetail":
            path.append(CursorRoute.prDetail)
        case "workThread":
            path.append(CursorRoute.workThread("Fix onboarding pairing flow"))
        case "receiptCard":
            path.append(CursorRoute.workThread("Receipt card UI test"))
        case "returnPacket":
            path.append(CursorRoute.workThread("Return packet UI test"))
        default:
            break
        }
    }
    #endif

    // MARK: Root stack

    private var mainStack: some View {
        NavigationStack(path: $path) {
            CursorWorkspacesView(
                onSelectWorkspace: { name in
                    // Tapping a repo always opens its thread list, matching the
                    // reference product's behavior exactly — a repo row is not
                    // an interstitial. Run-target info (which machine has a
                    // checkout) is reachable via long-press instead of gating
                    // the primary tap (see onShowWorkspaceDetail below).
                    liveBridge?.composerCWD = name == "All Repos" ? "" : name
                    // Being at a workspace's thread list means no specific
                    // thread is selected. Without this, a `selectedThreadID`
                    // left over from a thread visited earlier in the session
                    // silently hijacks the NEXT composer send into
                    // `onContinue` on that stale thread instead of a fresh
                    // dispatch — `onContinue` has no navigation logic at all,
                    // so the send appears to do nothing and you're left
                    // exactly where you were ("it just goes back to
                    // workspace" — reproduced 2026-07-07).
                    liveBridge?.selectedThreadID = nil
                    path.append(CursorRoute.workspaceThreadList(name))
                },
                onShowWorkspaceDetail: { name in
                    // Live bridge is checked first; the DEBUG mock seam
                    // (LANCER_CURSOR_MOCK_RUN_TARGETS=1) covers the no-bridge
                    // mock shell path for UITests.
                    if let workspace = liveBridge?.workspaces.first(where: { $0.name == name }),
                       !workspace.runTargets.isEmpty {
                        detailWorkspace = workspace
                        return
                    }
                    #if DEBUG
                    if let workspace = mockWorkspaces.first(where: { $0.name == name }),
                       !workspace.runTargets.isEmpty {
                        detailWorkspace = workspace
                    }
                    #endif
                },
                onOpenComposer: { openComposer(placeholder: "Plan, ask, build...") },
                onOpenProfile: { showingProfileDrawer = true },
                onOpenSearch: { showingSearchOverlay = true },
                onRequestPairing: { liveBridge?.onRequestPairing?() }
            )
            .navigationDestination(for: CursorRoute.self) { route in
                destinationView(for: route)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingProfileDrawer) {
            profileDrawerChain
        }
        .sheet(isPresented: $showingSearchOverlay) {
            CursorSearchOverlay(
                initialQuery: pendingSearchQuery,
                onClose: {
                    showingSearchOverlay = false
                    pendingSearchQuery = nil
                },
                onSelectResult: { conversationID, title in
                    showingSearchOverlay = false
                    pendingSearchQuery = nil
                    if let bridge = liveBridge {
                        bridge.selectedThreadID = conversationID
                        bridge.activeThreadPrompt = ""
                        bridge.activeThreadResponse = ""
                        bridge.activeThreadError = nil
                        bridge.activeThreadIsWorking = false
                        Task { await bridge.onOpenThread?(conversationID) }
                    }
                    path.append(CursorRoute.workThread(title))
                }
            )
        }
        // Siri navigation (I2): warm-app case. `SearchLancerIntent`/
        // `OpenConversationIntent` post this after `openAppWhenRun` brings
        // Lancer to the foreground, so the shell actually lands on the
        // destination the spoken result described instead of wherever it
        // already was.
        .onReceive(NotificationCenter.default.publisher(for: .lancerSiriNavigation)) { note in
            guard let payload = SiriNavigationPayload(userInfo: note.userInfo ?? [:]) else { return }
            handleSiriNavigation(payload)
        }
        // Cold-launch case: the notification above has no live subscriber
        // until this view exists, so a Siri navigation that triggered a cold
        // launch is buffered (mirrors `OpenApprovalBuffer`'s MAJOR-6 fix) and
        // drained here once the shell is actually up.
        .task {
            for payload in SiriNavigationBuffer.shared.drain() {
                handleSiriNavigation(payload)
            }
        }
        .sheet(isPresented: $showingRepoPicker) {
            CursorRepoPickerSheet(
                active: liveBridge == nil ? mockRepoPickerActive : activeRepoOption,
                recents: liveBridge == nil ? [] : liveRepoOptions,
                more: liveBridge == nil ? mockRepoPickerMore : [],
                onClose: { showingRepoPicker = false },
                onSelect: { option in
                    liveBridge?.composerCWD = option.repoName == "Home" ? "" : option.repoName
                    showingRepoPicker = false
                }
            )
        }
        .sheet(isPresented: $showingComposerSheet) {
            composerSheetChain
                .presentationDetents([.height(380), .large])
                .presentationBackground(.clear)
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(CursorMetrics.floatingCardCornerRadius)
        }
        .sheet(item: $detailWorkspace) { workspace in
            CursorWorkspaceDetailSheet(
                workspace: workspace,
                onClose: { detailWorkspace = nil }
            )
            .environment(\.cursorShellLiveBridge, liveBridge)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        #if DEBUG
        .task { applyDebugRouteIfNeeded() }
        #endif
    }

    // MARK: Pushed destinations

    /// Every pushed screen gets its own nav-bar/back-button hiding applied
    /// here, centrally: `.toolbar(.hidden, for: .navigationBar)` on the
    /// enclosing `NavigationStack` does not reliably propagate onto pushed
    /// `.navigationDestination` content, so without this each pushed screen's
    /// own custom back chevron would double up with the system one.
    @ViewBuilder
    private func destinationView(for route: CursorRoute) -> some View {
        Group {
            switch route {
            case .workspaceThreadList(let name):
                CursorWorkspaceThreadListView(
                    workspaceName: name,
                    onBack: { popIfPossible() },
                    onSelectThread: { title in
                        if let bridge = liveBridge,
                           let row = liveThread(named: title, in: name, bridge: bridge) {
                            bridge.selectedThreadID = row.id
                            bridge.composerCWD = row.repoName
                            // Clear stale state from whatever was last viewed,
                            // then load this thread's real persisted content —
                            // without the clear, a fast tap can show the
                            // PREVIOUS thread's response for a frame; without
                            // the load, an old completed thread always showed
                            // "No output recorded" regardless of its real
                            // saved content.
                            bridge.activeThreadPrompt = ""
                            bridge.activeThreadResponse = ""
                            bridge.activeThreadError = nil
                            bridge.activeThreadIsWorking = false
                            Task { await bridge.onOpenThread?(row.id) }
                        }
                        path.append(CursorRoute.workThread(title))
                    },
                    onSelectObservedSession: { row in
                        openImportedObservedSession(row)
                    },
                    onOpenComposer: { openComposer(placeholder: "Follow up...") },
                    onOpenSearch: { showingSearchOverlay = true },
                    onOpenMenu: { showingRepoPicker = true }
                )
            case .workThread(let title):
                CursorWorkThreadView(
                    missionTitle: title,
                    onBack: { popIfPossible() },
                    onViewPR: { path.append(CursorRoute.prDetail) },
                    onOpenReview: { path.append(CursorRoute.reviewDiff) },
                    onOpenComposer: { openComposer(placeholder: "Follow up...") },
                    onOpenComposerPrefilled: { prefill in
                        openComposer(placeholder: "Follow up...", prefill: prefill)
                    }
                )
            case .prDetail:
                CursorPRDetailView(onBack: { popIfPossible() })
            case .reviewDiff:
                CursorReviewDiffView(onBack: { popIfPossible() })
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private func popIfPossible() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    // MARK: - Siri navigation (I2)

    private func handleSiriNavigation(_ payload: SiriNavigationPayload) {
        switch payload.action {
        case .search:
            pendingSearchQuery = payload.searchQuery
            showingSearchOverlay = true
        case .openConversation:
            guard let conversationID = payload.conversationId else { return }
            Task { await openConversationFromSiri(id: conversationID) }
        }
    }

    /// Same bridge-state + push sequence `CursorSearchOverlay`'s
    /// `onSelectResult` already uses, driven from a conversation ID alone
    /// (Siri only hands over the ID, not a title) — looked up directly via
    /// `ChatConversationRepository` rather than adding a new bridge closure
    /// for a single call site.
    private func openConversationFromSiri(id: String) async {
        guard let db = try? AppDatabase.openShared(),
              let conversation = try? await ChatConversationRepository(db).conversation(id: id)
        else { return }
        if let bridge = liveBridge {
            bridge.selectedThreadID = id
            bridge.activeThreadPrompt = ""
            bridge.activeThreadResponse = ""
            bridge.activeThreadError = nil
            bridge.activeThreadIsWorking = false
            await bridge.onOpenThread?(id)
        }
        path.append(CursorRoute.workThread(conversation.title))
    }

    private func openImportedObservedSession(_ row: CursorObservedSessionMapping.RowModel) {
        guard let bridge = liveBridge, let onImport = bridge.onImportObservedSession else {
            path.append(CursorRoute.workThread(row.title))
            return
        }
        bridge.activeThreadError = nil
        Task {
            switch await onImport(row) {
            case .success(let conversationID):
                bridge.selectedThreadID = conversationID
                bridge.composerCWD = row.repoName
                bridge.activeThreadPrompt = ""
                bridge.activeThreadResponse = ""
                bridge.activeThreadIsWorking = false
                await bridge.onOpenThread?(conversationID)
                path.append(CursorRoute.workThread(row.title))
            case .failure(let error):
                bridge.activeThreadError = error.message
            }
        }
    }

    private func openComposer(placeholder: String, prefill: String? = nil) {
        composerPlaceholder = placeholder
        liveBridge?.composerPrefillText = prefill
        showingComposerSheet = true
    }

    // MARK: Profile drawer -> Settings sheet-on-sheet

    private var profileDrawerChain: some View {
        CursorProfileDrawer(
            onClose: { showingProfileDrawer = false },
            onOpenSettings: { showingSettingsFromProfile = true },
            onSignOut: {
                showingProfileDrawer = false
                path = NavigationPath()
                hasCompletedOnboarding = false
            }
        )
        .sheet(isPresented: $showingSettingsFromProfile) {
            CursorSettingsView(
                relayMachineCount: liveBridge?.relayMachineCount ?? 0,
                invalidMachineCount: liveBridge?.invalidMachineCount ?? 0,
                onPaired: liveBridge?.onPaired,
                onClearInvalid: liveBridge?.onClearInvalid,
                onReset: liveBridge?.onResetAppData
            )
        }
    }

    // MARK: Composer sheet chain

    /// `CursorRunOnSheet` / `CursorModelSheet` are presented as their own
    /// nested `.sheet`s directly on `CursorComposerSheet` — SwiftUI supports
    /// sheet-on-sheet via separate `@State` bools.
    private var composerSheetChain: some View {
        CursorComposerSheet(
            threadID: liveBridge?.selectedThreadID ?? "composer.new",
            repoName: composerRepoName,
            branchName: "main",
            modelName: liveBridge?.composerModelLabel ?? ManagedModel.claudeHaiku.label,
            runTargetName: composerRunTargetName,
            placeholder: composerPlaceholder,
            prefillText: liveBridge?.composerPrefillText,
            onPickRepo: { showingRepoPicker = true },
            onPickRunTarget: { showingRunOnSheet = true },
            onPickModel: { showingModelSheet = true },
            onSend: liveBridge == nil ? nil : { payload in
                guard let liveBridge else { return }
                let repoName = liveBridge.composerCWD.isEmpty ? "Home" : liveBridge.composerCWD
                let model = liveBridge.composerModelSlug
                if let threadID = liveBridge.selectedThreadID {
                    // Same real-state update as a fresh dispatch — without
                    // this a follow-up sent from an existing thread doesn't
                    // update the prompt bubble/narration at all (onContinue
                    // itself had no wiring here until this pass either).
                    liveBridge.activeThreadPrompt = payload.prompt
                    Task { await liveBridge.onContinue?(threadID, payload.prompt, model, payload.contract) }
                } else {
                    // `repoName` is a display name, not a path — the daemon can't
                    // resolve a bare relative name to a real directory (it only
                    // expands `~`). Prefer the real absolute cwd of that repo's
                    // most recent known conversation; "~" (home) is the only safe
                    // fallback for a repo with no history yet, never the bare name.
                    let cwd = liveBridge.repoPaths[repoName] ?? "~"
                    // Reset stale state from whatever thread was last viewed —
                    // otherwise a fresh dispatch briefly shows the PREVIOUS
                    // thread's response text under the new prompt.
                    liveBridge.activeThreadPrompt = payload.prompt
                    liveBridge.activeThreadResponse = ""
                    liveBridge.activeRunID = nil
                    liveBridge.selectedThreadID = nil
                    liveBridge.activeThreadError = nil
                    Task { await liveBridge.onDispatch?(payload.prompt, cwd, model, payload.contract) }
                    // A fresh dispatch has no existing thread to navigate into —
                    // without this, closing the composer sheet just reveals
                    // whatever was underneath it (usually Workspaces root),
                    // regardless of whether the dispatch even succeeds.
                    path.append(CursorRoute.workThread(payload.prompt))
                }
                liveBridge.composerPrefillText = nil
                showingComposerSheet = false
            }
        )
        .sheet(isPresented: $showingRunOnSheet) {
            CursorRunOnSheet(
                activeTargets: runTargetSheetActive,
                moreTargets: runTargetSheetMore,
                onClose: { showingRunOnSheet = false },
                onSelect: { option in
                    if let liveBridge {
                        liveBridge.selectedRunTargetMachineID = option.id
                        liveBridge.selectedRunTargetHostName = option.title
                    } else {
                        mockSelectedRunTargetID = option.id
                    }
                    showingRunOnSheet = false
                }
            )
        }
        .sheet(isPresented: $showingModelSheet) {
            CursorModelSheet(
                activeModels: [
                    .init(
                        id: liveBridge?.composerModelSlug ?? ManagedModel.claudeHaiku.rawValue,
                        title: liveBridge?.composerModelLabel ?? ManagedModel.claudeHaiku.label,
                        isSelected: true
                    )
                ],
                onClose: { showingModelSheet = false },
                onSelect: { option in
                    liveBridge?.composerModelSlug = option.id
                    liveBridge?.composerModelLabel = option.title
                    showingModelSheet = false
                }
            )
        }
    }

    private func liveThread(
        named title: String,
        in workspaceName: String,
        bridge: CursorShellLiveBridge
    ) -> CursorShellLiveBridge.ThreadRow? {
        if workspaceName == "All Repos" {
            return bridge.threadsByWorkspace.values.flatMap { $0 }.first { $0.title == title }
        }
        return bridge.threads(for: workspaceName).first { $0.title == title }
    }
}
#endif
