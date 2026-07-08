#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit

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
    @State private var detailWorkspace: CursorShellLiveBridge.WorkspaceRow? = nil

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
        case "workThread":
            path.append(CursorRoute.workThread("Fix onboarding pairing flow"))
        case "receiptCard":
            path.append(CursorRoute.workThread("Receipt card UI test"))
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
                onClose: { showingSearchOverlay = false },
                onSelectResult: { conversationID, title in
                    showingSearchOverlay = false
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
        .sheet(isPresented: $showingRepoPicker) {
            CursorRepoPickerSheet(
                onClose: { showingRepoPicker = false },
                onSelect: { _ in showingRepoPicker = false }
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
                           let row = bridge.threads(for: name).first(where: { $0.title == title }) {
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
                onClearInvalid: liveBridge?.onClearInvalid
            )
        }
    }

    // MARK: Composer sheet chain

    /// `CursorRunOnSheet` / `CursorModelSheet` are presented as their own
    /// nested `.sheet`s directly on `CursorComposerSheet` — SwiftUI supports
    /// sheet-on-sheet via separate `@State` bools. Both dismiss themselves on
    /// selection since there's no real state to persist yet.
    private var composerSheetChain: some View {
        CursorComposerSheet(
            threadID: liveBridge?.selectedThreadID ?? "composer.new",
            repoName: liveBridge?.composerCWD.isEmpty == false ? (liveBridge?.composerCWD ?? "lancer-ios") : "lancer-ios",
            modelName: liveBridge?.composerModelLabel ?? ManagedModel.claudeHaiku.label,
            placeholder: composerPlaceholder,
            prefillText: liveBridge?.composerPrefillText,
            onPickRepo: { showingRepoPicker = true },
            onPickRunTarget: { showingRunOnSheet = true },
            onPickModel: { showingModelSheet = true },
            onSend: liveBridge == nil ? nil : { payload in
                guard let liveBridge else { return }
                let repoName = liveBridge.composerCWD.isEmpty ? "command-center" : liveBridge.composerCWD
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
                liveBridge?.composerPrefillText = nil
                showingComposerSheet = false
            }
        )
        .sheet(isPresented: $showingRunOnSheet) {
            CursorRunOnSheet(
                onClose: { showingRunOnSheet = false },
                onSelect: { _ in showingRunOnSheet = false }
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
}
#endif
