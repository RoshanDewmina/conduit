#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import NotificationsKit
import PersistenceKit

/// Every reachable push destination in the Cursor-style shell. Case names are a public
/// contract (Siri / APNs / Live Activity deep-link destinations, brief §"Deep-link route
/// names must survive") — do not rename even though this rebuild replaced every view that
/// used to render them.
private enum CursorRoute: Hashable {
    case workspaceThreadList(String)
    case workThread(String?)
    case prDetail
    case reviewDiff
}

/// Which of the 3 IA roots (`ARCHITECTURE.md` §4.1: Home / Workspaces / Settings) is
/// active. Not `enum Tab` from `AppRoot` (that one is vestigial/unrelated) and never a
/// `Control`/`Activity` root.
private enum CursorShellRoot: Hashable {
    case home
    case workspaces
    case settings
}

/// Cursor-style 3-root shell wiring every rebuilt `CursorStyle/` screen together, live or
/// mock. Rebuilt 2026-07-09 against the unchanged `CursorShellLiveBridge` contract — see
/// `docs/plans/2026-07-09-orca-shell-port-design.md` for the Orca-informed behavior fixes
/// (post-pair landing, docked composer, Nth-turn live update) folded into this file and
/// its child views.
public struct CursorAppShell: View {
    private let liveBridge: CursorShellLiveBridge?

    #if DEBUG
    @State private var hasCompletedOnboarding: Bool
    #else
    @State private var hasCompletedOnboarding = false
    #endif

    @State private var selectedRoot: CursorShellRoot = .workspaces
    @State private var homePath = NavigationPath()
    @State private var workspacesPath = NavigationPath()
    @State private var showingSearchOverlay = false
    @State private var pendingSearchQuery: String?
    /// Tracks the trusted-machine count so a pairing success (from onboarding, the
    /// Workspaces `+`, or Settings → Trusted machines — any presentation site) can land
    /// the user on Workspaces exactly once per new pairing, never re-triggering on an
    /// unrelated bridge refresh. Ported from stablyai/orca (MIT)
    /// mobile/app/pair-confirm.tsx (`router.replace` on pairing success) — see design
    /// note §1.
    @State private var lastKnownMachineCount: Int?

    public init(liveBridge: CursorShellLiveBridge? = nil) {
        self.liveBridge = liveBridge
        #if DEBUG
        let skipEnv = ProcessInfo.processInfo.environment["LANCER_SKIP_CURSOR_ONBOARDING"] == "1"
        _hasCompletedOnboarding = State(initialValue: liveBridge != nil || skipEnv)
        #else
        _hasCompletedOnboarding = State(initialValue: liveBridge != nil)
        #endif
    }

    public var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainTabs
            } else {
                CursorOnboardingView(onComplete: { hasCompletedOnboarding = true })
            }
        }
        .environment(\.cursorShellLiveBridge, liveBridge)
    }

    // MARK: 3-root chrome

    private var mainTabs: some View {
        TabView(selection: $selectedRoot) {
            NavigationStack(path: $homePath) {
                CursorHomeView(
                    onOpenThread: { id in
                        liveBridge?.selectedThreadID = id
                        resetActiveThreadState()
                        Task { await liveBridge?.onOpenThread?(id) }
                        homePath.append(CursorRoute.workThread(id))
                    },
                    onDispatchedNewThread: { homePath.append(CursorRoute.workThread(nil)) },
                    onOpenSearch: { showingSearchOverlay = true }
                )
                .navigationDestination(for: CursorRoute.self) { destinationView(for: $0, path: $homePath) }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(CursorShellRoot.home)
            .accessibilityIdentifier("cursor.tab.home")

            NavigationStack(path: $workspacesPath) {
                CursorWorkspacesView(
                    onSelectWorkspace: { name in
                        liveBridge?.composerCWD = name == "All Repos" ? "" : name
                        liveBridge?.selectedThreadID = nil
                        workspacesPath.append(CursorRoute.workspaceThreadList(name))
                    },
                    onOpenSearch: { showingSearchOverlay = true },
                    onRequestPairing: { liveBridge?.onRequestPairing?() }
                )
                .navigationDestination(for: CursorRoute.self) { destinationView(for: $0, path: $workspacesPath) }
            }
            .tabItem { Label("Workspaces", systemImage: "square.stack.3d.up") }
            .tag(CursorShellRoot.workspaces)
            .accessibilityIdentifier("cursor.tab.workspaces")

            NavigationStack {
                CursorSettingsView(
                    relayMachineCount: liveBridge?.relayMachineCount ?? 0,
                    invalidMachineCount: liveBridge?.invalidMachineCount ?? 0,
                    trustedMachines: liveBridge?.trustedMachines ?? [],
                    invalidTrustedMachines: liveBridge?.invalidTrustedMachines ?? [],
                    onRequestPairing: { liveBridge?.onRequestPairing?() },
                    onPaired: liveBridge?.onPaired,
                    onRemoveMachine: { liveBridge?.onRemoveTrustedMachine?($0) },
                    onClearInvalid: liveBridge?.onClearInvalid,
                    onReset: liveBridge?.onResetAppData
                )
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(CursorShellRoot.settings)
            .accessibilityIdentifier("cursor.tab.settings")
        }
        .sheet(isPresented: $showingSearchOverlay) {
            CursorSearchOverlay(
                initialQuery: pendingSearchQuery,
                onClose: {
                    showingSearchOverlay = false
                    pendingSearchQuery = nil
                },
                onSelectResult: { conversationID, _ in
                    showingSearchOverlay = false
                    pendingSearchQuery = nil
                    openThreadFromDeepLink(conversationID)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerSiriNavigation)) { note in
            guard let payload = SiriNavigationPayload(userInfo: note.userInfo ?? [:]) else { return }
            handleSiriNavigation(payload)
        }
        .task {
            for payload in SiriNavigationBuffer.shared.drain() {
                handleSiriNavigation(payload)
            }
        }
        .onChange(of: liveBridge?.trustedMachines.count) { _, newCount in
            handlePossiblePairingSuccess(newCount: newCount)
        }
        #if DEBUG
        // onAppear is more reliable than .task for NavigationPath deep-links in UITests —
        // TabView + NavigationStack can miss a one-shot task append on first paint.
        .onAppear { applyDebugRouteIfNeeded() }
        .task { applyDebugRouteIfNeeded() }
        #endif
    }

    // MARK: Post-pair landing (Orca `router.replace` semantics — design note §1)

    private func handlePossiblePairingSuccess(newCount: Int?) {
        defer { lastKnownMachineCount = newCount }
        guard let newCount, let previous = lastKnownMachineCount, newCount > previous else { return }
        selectedRoot = .workspaces
        workspacesPath = NavigationPath()
        liveBridge?.selectedThreadID = nil
    }

    // MARK: Pushed destinations

    @ViewBuilder
    private func destinationView(for route: CursorRoute, path: Binding<NavigationPath>) -> some View {
        Group {
            switch route {
            case .workspaceThreadList(let name):
                CursorWorkspaceThreadListView(
                    workspaceName: name,
                    onBack: { popIfPossible(path) },
                    onSelectThread: { conversationID in
                        selectLiveThread(conversationID, in: name)
                        path.wrappedValue.append(CursorRoute.workThread(conversationID))
                    },
                    onSelectObservedSession: { row in openImportedObservedSession(row, path: path) },
                    onDispatchedNewThread: { path.wrappedValue.append(CursorRoute.workThread(nil)) },
                    onOpenSearch: { showingSearchOverlay = true }
                )
            case .workThread(let conversationID):
                CursorWorkThreadView(
                    routedConversationID: conversationID,
                    fallbackTitle: conversationID ?? "Thread",
                    onBack: { popIfPossible(path) },
                    onViewPR: { path.wrappedValue.append(CursorRoute.prDetail) },
                    onOpenReview: { liveBridge?.onOpenReview?() }
                )
            case .prDetail:
                CursorPRDetailView(onBack: { popIfPossible(path) })
            case .reviewDiff:
                CursorReviewDiffView(onBack: { popIfPossible(path) })
            }
        }
    }

    private func popIfPossible(_ path: Binding<NavigationPath>) {
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }

    private func resetActiveThreadState() {
        guard let liveBridge else { return }
        liveBridge.activeThreadPrompt = ""
        liveBridge.activeThreadResponse = ""
        liveBridge.activeThreadError = nil
        liveBridge.activeThreadIsWorking = false
    }

    private func selectLiveThread(_ conversationID: String, in workspaceName: String) {
        guard let liveBridge else { return }
        let matched: CursorShellLiveBridge.ThreadRow? = workspaceName == "All Repos"
            ? liveBridge.threadsByWorkspace.values.flatMap { $0 }.first { $0.id == conversationID }
            : liveBridge.threads(for: workspaceName).first { $0.id == conversationID }
        guard let row = matched else { return }
        liveBridge.selectedThreadID = row.id
        liveBridge.composerCWD = row.repoName
        resetActiveThreadState()
        Task { await liveBridge.onOpenThread?(row.id) }
    }

    private func openImportedObservedSession(_ row: CursorObservedSessionMapping.RowModel, path: Binding<NavigationPath>) {
        guard let liveBridge, let onImport = liveBridge.onImportObservedSession else {
            path.wrappedValue.append(CursorRoute.workThread(nil))
            return
        }
        liveBridge.activeThreadError = nil
        Task {
            switch await onImport(row) {
            case .success(let conversationID):
                liveBridge.selectedThreadID = conversationID
                liveBridge.composerCWD = row.repoName
                resetActiveThreadState()
                await liveBridge.onOpenThread?(conversationID)
                path.wrappedValue.append(CursorRoute.workThread(conversationID))
            case .failure(let error):
                liveBridge.activeThreadError = error.message
            }
        }
    }

    private func openThreadFromDeepLink(_ conversationID: String) {
        selectedRoot = .workspaces
        if let bridge = liveBridge {
            bridge.selectedThreadID = conversationID
            resetActiveThreadState()
            Task { await bridge.onOpenThread?(conversationID) }
        }
        workspacesPath.append(CursorRoute.workThread(conversationID))
    }

    // MARK: Siri navigation (I2) — unchanged wiring, carried into the rebuilt shell

    private func handleSiriNavigation(_ payload: SiriNavigationPayload) {
        switch payload.action {
        case .search:
            selectedRoot = .workspaces
            pendingSearchQuery = payload.searchQuery
            showingSearchOverlay = true
        case .openConversation:
            guard let conversationID = payload.conversationId else { return }
            openThreadFromDeepLink(conversationID)
        }
    }

    #if DEBUG
    private func applyDebugRouteIfNeeded() {
        guard hasCompletedOnboarding, workspacesPath.isEmpty else { return }
        switch ProcessInfo.processInfo.environment["LANCER_CURSOR_ROUTE"] {
        case "reviewDiff":
            selectedRoot = .workspaces
            workspacesPath.append(CursorRoute.reviewDiff)
        case "prDetail":
            selectedRoot = .workspaces
            workspacesPath.append(CursorRoute.prDetail)
        case "workThread":
            selectedRoot = .workspaces
            workspacesPath.append(CursorRoute.workThread("debug-fix-onboarding"))
        default:
            break
        }
    }
    #endif
}
#endif
