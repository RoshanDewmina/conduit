#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual clone of Cursor's mobile Workspaces list: an "All Repos" entry plus
/// one row per repo. Live shell rows come from `CursorShellLiveBridge`; seeded
/// rows are restricted to the no-bridge DEBUG/mock shell.
public struct CursorWorkspacesView: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    /// Local-only presentation state for the "Add Repo" sheet (row 6 of the
    /// 2026-07-08 Cursor screen map). Owned entirely by this view rather than
    /// threaded through `CursorAppShell` — the "Add Repo" row previously had
    /// no `Button` wrapper at all (a documented no-op, asserted by
    /// `CursorAppShellExhaustiveTests.testWorkspacesRoot_HeaderAndRows`), so
    /// making it open a locally-owned sheet is additive and can't regress
    /// that or any other existing wiring.
    @State private var showingAddRepoSheet = false

    private let onSelectWorkspace: (String) -> Void
    private let onShowWorkspaceDetail: (String) -> Void
    private let onOpenComposer: () -> Void
    private let onOpenProfile: () -> Void
    private let onOpenSearch: () -> Void
    private let onRequestPairing: () -> Void

    public init(
        onSelectWorkspace: @escaping (String) -> Void = { _ in },
        onShowWorkspaceDetail: @escaping (String) -> Void = { _ in },
        onOpenComposer: @escaping () -> Void = {},
        onOpenProfile: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {},
        onRequestPairing: @escaping () -> Void = {}
    ) {
        self.onSelectWorkspace = onSelectWorkspace
        self.onShowWorkspaceDetail = onShowWorkspaceDetail
        self.onOpenComposer = onOpenComposer
        self.onOpenProfile = onOpenProfile
        self.onOpenSearch = onOpenSearch
        self.onRequestPairing = onRequestPairing
    }

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    private func pendingApprovalBanner(_ liveBridge: CursorShellLiveBridge) -> some View {
        CursorApprovalBanner(
            count: 1,
            onApprove: {
                guard let approvalID = liveBridge.pendingApprovalID else { return }
                Task { await liveBridge.onDecide?(approvalID, .approved) }
            },
            onReject: {
                guard let approvalID = liveBridge.pendingApprovalID else { return }
                Task { await liveBridge.onDecide?(approvalID, .rejected) }
            },
            onOpenReview: {
                liveBridge.onOpenReview?()
            }
        )
        .accessibilityIdentifier("workspaces-approval-banner")
        .padding(.horizontal, CursorMetrics.actionRailHorizontalPadding)
        .padding(.top, 4)
    }

    public var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(
                    Button(action: onOpenProfile) { avatarCircle }
                        .buttonStyle(.plain)
                ),
                trailing: [
                    CursorIconButton(systemImageName: "magnifyingglass", action: onOpenSearch),
                    CursorIconButton(systemImageName: "plus", action: onRequestPairing)
                ]
            )

            if let liveBridge, liveBridge.connectionPhase != .connected {
                CursorConnectionBanner(
                    phase: liveBridge.connectionPhase,
                    onPair: liveBridge.onRequestPairing
                )
            }

            if let liveBridge, liveBridge.pendingApprovalID != nil {
                pendingApprovalBanner(liveBridge)
            }

            Text("Workspaces")
                .font(CursorType.pageTitle)
                .foregroundColor(colors.primaryText)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 0) {
                    if let liveBridge {
                        if liveBridge.workspaces.isEmpty {
                            liveEmptyState
                        } else {
                            liveWorkspaceRows(liveBridge)
                        }
                    } else {
                        seedWorkspaceRows
                        addRepoRow
                    }
                }
            }
        }
        .background(colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CursorBottomComposer(onTap: onOpenComposer)
        }
        .sheet(isPresented: $showingAddRepoSheet) {
            CursorAddRepoSheet(onClose: { showingAddRepoSheet = false })
        }
    }

    @ViewBuilder
    private func liveWorkspaceRows(_ liveBridge: CursorShellLiveBridge) -> some View {
        let total = liveBridge.workspaces.reduce(0) { $0 + $1.threadCount }
        Button(action: { onSelectWorkspace("All Repos") }) {
            CursorListRow(
                iconSystemName: "square.stack.3d.up",
                title: "All Repos",
                trailingCount: total,
                showChevron: true
            )
        }
        .buttonStyle(.plain)

        ForEach(liveBridge.workspaces) { workspace in
            Button(action: { onSelectWorkspace(workspace.name) }) {
                workspaceRow(workspace)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workspace-row")
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                onShowWorkspaceDetail(workspace.name)
            })
        }

        addRepoRow
    }

    /// The trailing "Add Repo" row (folder+ icon, no chevron — matches
    /// IMG_2408) that presents the Add Repo sheet (screen-map row 6).
    private var addRepoRow: some View {
        Button(action: { showingAddRepoSheet = true }) {
            CursorListRow(
                iconSystemName: "folder.badge.plus",
                title: "Add Repo",
                trailingCount: nil,
                showChevron: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-repo-row")
    }

    private var liveEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No conversations yet")
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
            Text("Pair a machine or send a prompt from the composer to create the first workspace.")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func workspaceRow(_ workspace: CursorShellLiveBridge.WorkspaceRow) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(spacing: 0) {
            HStack(spacing: CursorMetrics.rowSpacing) {
                Image(systemName: "folder")
                    .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                    .foregroundColor(colors.secondaryText)
                    .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                    if let meta = runTargetMetaLine(workspace) {
                        Text(meta)
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.secondaryText)
                    }
                }
                Spacer()
                if workspace.threadCount > 0 {
                    Text("\(workspace.threadCount)")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colors.mutedText)
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)
            Rectangle()
                .fill(colors.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
        }
        .contentShape(Rectangle())
    }

    private func runTargetMetaLine(_ workspace: CursorShellLiveBridge.WorkspaceRow) -> String? {
        let targets = workspace.runTargets
        guard !targets.isEmpty else { return nil }
        if targets.count == 1 {
            return targets[0].hostName
        }
        let names = targets.prefix(2).map(\.hostName).joined(separator: ", ")
        let extra = targets.count > 2 ? " +\(targets.count - 2)" : ""
        return "\(names)\(extra) · \(workspace.threadCount) threads"
    }

    private var avatarCircle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.29, green: 0.42, blue: 0.94),
                        Color(red: 0.62, green: 0.31, blue: 0.87)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var seedWorkspaceRows: some View {
        Button(action: { onSelectWorkspace("All Repos") }) {
            CursorListRow(
                iconSystemName: "square.stack.3d.up",
                title: "All Repos",
                trailingCount: 3,
                showChevron: true
            )
        }
        .buttonStyle(.plain)

        Button(action: { onSelectWorkspace("lancer-ios") }) {
            CursorListRow(
                iconSystemName: "folder",
                title: "lancer-ios",
                trailingCount: 4,
                showChevron: true
            )
        }
        .buttonStyle(.plain)
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            onShowWorkspaceDetail("lancer-ios")
        })

        Button(action: { onSelectWorkspace("push-backend") }) {
            CursorListRow(
                iconSystemName: "folder",
                title: "push-backend",
                trailingCount: 2,
                showChevron: true
            )
        }
        .buttonStyle(.plain)
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            onShowWorkspaceDetail("push-backend")
        })

        Button(action: { onSelectWorkspace("lancer-mac") }) {
            CursorListRow(
                iconSystemName: "folder",
                title: "lancer-mac",
                trailingCount: nil,
                showChevron: true
            )
        }
        .buttonStyle(.plain)
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            onShowWorkspaceDetail("lancer-mac")
        })
    }
}

// MARK: - Add Repo sheet (screen-map row 6, IMG_2414 / dark equivalent)

/// Mode selection for `CursorAddRepoSheet` — internal for unit tests.
enum CursorAddRepoSheetPresentation {
    /// Whether the sheet should render the DEBUG mock repo list (mock shell
    /// only). Live shell always gets the honest explainer — no fake success.
    static func showsMockRepoList(liveBridgeIsSet: Bool) -> Bool {
        #if DEBUG
        return !liveBridgeIsSet
        #else
        return false
        #endif
    }
}

/// Cursor-style "Add Repo" sheet: X close, centered "Add Repo" title.
///
/// **Live shell** (`cursorShellLiveBridge` is set): honest deferred state — no
/// GitHub OAuth pretense, no clone button, no fake selectable repo list. Repos
/// appear in Workspaces automatically when an agent runs in them on a paired
/// machine; the sheet explains that and offers a "How to add a repo" guide.
///
/// **Mock shell** (`LANCER_CURSOR_SHELL=1`, no live bridge): DEBUG-only pixel
/// reference list for UI tests/screenshots — clearly not wired to any backend.
private struct CursorAddRepoSheet: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.cursorShellLiveBridge) private var liveBridge
    @State private var searchText: String = ""
    @State private var showingHowToAddRepo = false

    let onClose: () -> Void

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    private var useMockRepoList: Bool {
        CursorAddRepoSheetPresentation.showsMockRepoList(liveBridgeIsSet: liveBridge != nil)
    }

    #if DEBUG
    /// Small static list for mock-shell UI tests (`LANCER_CURSOR_SHELL=1`) —
    /// not shown in the live shell and not wired to any clone/add RPC.
    private static let mockShellRepos: [CursorRepoPickerOption] = [
        .init(id: "add-repo-lancer-ios", orgName: "RoshanDewmina", repoName: "lancer-ios"),
        .init(id: "add-repo-command-center", orgName: "RoshanDewmina", repoName: "command-center"),
        .init(id: "add-repo-push-backend", orgName: "RoshanDewmina", repoName: "push-backend")
    ]
    #endif

    #if DEBUG
    private var filteredMockRepos: [CursorRepoPickerOption] {
        guard !searchText.isEmpty else { return Self.mockShellRepos }
        return Self.mockShellRepos.filter { $0.repoName.localizedCaseInsensitiveContains(searchText) }
    }
    #endif

    var body: some View {
        CursorBottomSheetContainer(
            title: "Add Repo",
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            Group {
                #if DEBUG
                if useMockRepoList {
                    mockRepoListContent
                } else {
                    honestContent
                }
                #else
                honestContent
                #endif
            }
            .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
        }
        .accessibilityIdentifier("add-repo-sheet")
    }

    // MARK: Live — honest deferred state

    private var honestContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Repos appear here automatically when you run an agent in them from a paired machine.")
                .font(CursorType.bodyText)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, CursorMetrics.sheetHeaderHorizontalPadding)
                .padding(.bottom, CursorMetrics.sectionHeaderTopPadding)
                .accessibilityIdentifier("add-repo-honest-message")

            DisclosureGroup(isExpanded: $showingHowToAddRepo) {
                VStack(alignment: .leading, spacing: 14) {
                    howToStep(
                        number: 1,
                        text: "Pair a machine from Settings or tap + on the Workspaces screen."
                    )
                    howToStep(
                        number: 2,
                        text: "On that machine, open a terminal in the repo's directory."
                    )
                    howToStep(
                        number: 3,
                        text: "Start a thread or run an agent there — the repo will show up in Workspaces."
                    )
                }
                .padding(.top, 10)
                .padding(.bottom, 4)
            } label: {
                Text("How to add a repo")
                    .font(CursorType.rowTitle)
                    .foregroundColor(colors.primaryText)
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .accessibilityIdentifier("add-repo-how-to")
        }
    }

    private func howToStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(CursorType.rowSecondary.weight(.semibold))
                .foregroundColor(colors.secondaryText)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: DEBUG mock shell — pixel reference only

    #if DEBUG
    @ViewBuilder
    private var mockRepoListContent: some View {
        VStack(spacing: 0) {
            addRepoSearchField
                .padding(.bottom, CursorMetrics.sectionHeaderTopPadding)

            CursorSectionHeader("Workspaces")
            ForEach(filteredMockRepos) { option in
                mockRepoRow(option)
            }
        }
    }
    #endif

    #if DEBUG
    /// A `CursorSearchField`-alike with the "Repo…" placeholder the reference
    /// uses (IMG_2414) — mock shell only.
    private var addRepoSearchField: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return HStack(spacing: CursorMetrics.searchFieldIconSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(colors.secondaryText)
            TextField("Repo…", text: $searchText)
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
                .tint(colors.primaryText)
        }
        .padding(.horizontal, CursorMetrics.searchFieldHorizontalPadding)
        .frame(height: CursorMetrics.searchFieldHeight)
        .background(Capsule().fill(colors.composerBackground))
        .padding(.horizontal, CursorMetrics.searchFieldMargin)
    }

    private func mockRepoRow(_ option: CursorRepoPickerOption) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Button(action: onClose) {
            VStack(spacing: 0) {
                HStack(spacing: CursorMetrics.rowSpacing) {
                    Image(systemName: "folder")
                        .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)

                    HStack(spacing: 0) {
                        Text("\(option.orgName)/")
                            .font(CursorType.rowTitle)
                            .foregroundColor(colors.secondaryText)
                        Text(option.repoName)
                            .font(CursorType.rowTitle.weight(.semibold))
                            .foregroundColor(colors.primaryText)
                    }
                    .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
                .padding(.vertical, CursorMetrics.rowVerticalPadding)
                Rectangle()
                    .fill(colors.hairline)
                    .frame(height: CursorMetrics.rowHairlineHeight)
                    .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-repo-sheet-row")
    }
    #endif
}
#endif
