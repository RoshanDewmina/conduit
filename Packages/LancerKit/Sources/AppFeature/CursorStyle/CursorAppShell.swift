#if os(iOS)
import SwiftUI

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
                mainStack
            } else {
                CursorOnboardingView(onComplete: { hasCompletedOnboarding = true })
            }
        }
        .environment(\.cursorShellLiveBridge, liveBridge)
    }

    // MARK: Root stack

    private var mainStack: some View {
        NavigationStack(path: $path) {
            CursorWorkspacesView(
                onSelectWorkspace: { name in
                    liveBridge?.composerCWD = name == "All Repos" ? "" : name
                    path.append(CursorRoute.workspaceThreadList(name))
                },
                onOpenComposer: { showingComposerSheet = true },
                onOpenProfile: { showingProfileDrawer = true },
                onOpenSearch: { showingSearchOverlay = true }
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
                onSelectResult: { title in
                    showingSearchOverlay = false
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
        }
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
                        }
                        path.append(CursorRoute.workThread(title))
                    },
                    onOpenComposer: { showingComposerSheet = true },
                    onOpenSearch: { showingSearchOverlay = true },
                    onOpenMenu: { showingRepoPicker = true }
                )
            case .workThread(let title):
                CursorWorkThreadView(
                    missionTitle: title,
                    onBack: { popIfPossible() },
                    onViewPR: { path.append(CursorRoute.prDetail) },
                    onOpenReview: { path.append(CursorRoute.reviewDiff) },
                    onOpenComposer: { showingComposerSheet = true }
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
            if let liveBridge, liveBridge.onOpenSettings != nil {
                CursorSettingsView(onOpenRealSettings: liveBridge.onOpenSettings)
            } else {
                CursorSettingsView()
            }
        }
    }

    // MARK: Composer sheet chain

    /// `CursorRunOnSheet` / `CursorModelSheet` are presented as their own
    /// nested `.sheet`s directly on `CursorComposerSheet` — SwiftUI supports
    /// sheet-on-sheet via separate `@State` bools. Both dismiss themselves on
    /// selection since there's no real state to persist yet.
    private var composerSheetChain: some View {
        CursorComposerSheet(
            repoName: liveBridge?.composerCWD.isEmpty == false ? (liveBridge?.composerCWD ?? "lancer-ios") : "lancer-ios",
            onPickRunTarget: { showingRunOnSheet = true },
            onPickModel: { showingModelSheet = true },
            onSend: liveBridge == nil ? nil : { prompt in
                guard let liveBridge else { return }
                let cwd = liveBridge.composerCWD.isEmpty ? "command-center" : liveBridge.composerCWD
                if let threadID = liveBridge.selectedThreadID {
                    Task { await liveBridge.onContinue?(threadID, prompt) }
                } else {
                    Task { await liveBridge.onDispatch?(prompt, cwd) }
                }
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
                onClose: { showingModelSheet = false },
                onSelect: { _ in showingModelSheet = false }
            )
        }
    }
}
#endif
