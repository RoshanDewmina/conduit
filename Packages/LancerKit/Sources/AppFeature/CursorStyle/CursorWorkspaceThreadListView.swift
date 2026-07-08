#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual clone of Cursor's mobile per-repo thread list: unlike `CursorHomeView`
/// (a cross-repo aggregate), this is scoped to a single workspace, with a
/// back-chevron + search + hamburger header instead of the avatar+search+plus
/// header Home/Workspaces use. Uses live bridge threads when wired; seed data
/// fallback for mock UI tests.
public struct CursorWorkspaceThreadListView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let workspaceName: String
    private let onBack: () -> Void
    private let onSelectThread: (String) -> Void
    private let onOpenComposer: () -> Void
    private let onOpenSearch: () -> Void
    private let onOpenMenu: () -> Void

    public init(
        workspaceName: String,
        onBack: @escaping () -> Void = {},
        onSelectThread: @escaping (String) -> Void = { _ in },
        onOpenComposer: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {},
        onOpenMenu: @escaping () -> Void = {}
    ) {
        self.workspaceName = workspaceName
        self.onBack = onBack
        self.onSelectThread = onSelectThread
        self.onOpenComposer = onOpenComposer
        self.onOpenSearch = onOpenSearch
        self.onOpenMenu = onOpenMenu
    }

    // MARK: - Live "All Repos" grouped path

    /// Groups threads from every workspace keyed by repo name for the All Repos section-header layout.
    private struct RepoGroup: Identifiable {
        let repoName: String
        let threads: [CursorThreadRowModel]
        var id: String { repoName }
    }

    /// All live threads across every workspace in the bridge (used when workspaceName == "All Repos").
    private var allLiveThreads: [CursorShellLiveBridge.ThreadRow] {
        guard let liveBridge else { return [] }
        return liveBridge.threadsByWorkspace.values.flatMap { $0 }
    }

    private var scopedLiveRows: [CursorShellLiveBridge.ThreadRow] {
        guard let liveBridge else { return [] }
        if workspaceName == "All Repos" { return allLiveThreads }
        return liveBridge.threads(for: workspaceName)
    }

    private var hasLiveThreads: Bool {
        liveBridge != nil && !scopedLiveRows.isEmpty
    }

    private func threadState(for row: CursorShellLiveBridge.ThreadRow) -> CursorThreadAttention.ThreadState {
        liveBridge?.threadStates[row.id] ?? CursorThreadAttention.ThreadState()
    }

    private func sortedLiveRows(_ rows: [CursorShellLiveBridge.ThreadRow]) -> [CursorShellLiveBridge.ThreadRow] {
        guard let liveBridge else { return rows }
        return sortThreadsByAttention(
            rows,
            updatedAt: \.updatedAt,
            threadState: { row in
                liveBridge.threadStates[row.id] ?? CursorThreadAttention.ThreadState()
            }
        )
    }

    private var sortedScopedLiveRows: [CursorShellLiveBridge.ThreadRow] {
        sortedLiveRows(scopedLiveRows)
    }

    private var needsYouLiveRows: [CursorShellLiveBridge.ThreadRow] {
        sortedScopedLiveRows.filter { isNeedsYouThread(threadState(for: $0)) }
    }

    private var needsYouCount: Int { needsYouLiveRows.count }

    private var needsYouIDs: Set<String> {
        Set(needsYouLiveRows.map(\.id))
    }

    private var homeAttentionStatus: String? {
        guard let liveBridge else { return nil }
        return homeAttentionStatusMessage(
            needsYouCount: needsYouCount,
            relayHealthy: liveBridge.relayHealthy,
            lastSnapshotAt: liveBridge.lastSnapshotAt
        )
    }

    private func rowModel(
        from row: CursorShellLiveBridge.ThreadRow,
        isActive: Bool
    ) -> CursorThreadRowModel {
        let derived = CursorThreadAttention.derive(threadState(for: row))
        return CursorThreadRowModel(
            id: UUID(uuidString: row.id) ?? UUID(),
            title: row.title,
            repoName: row.repoName,
            isActive: isActive,
            statusLine: .noChanges,
            attention: derived.0,
            attentionDetail: derived.2
        )
    }

    private func liveThreadModels(
        _ rows: [CursorShellLiveBridge.ThreadRow],
        markFirstActive: Bool = false
    ) -> [CursorThreadRowModel] {
        rows.enumerated().map { index, row in
            rowModel(from: row, isActive: markFirstActive && index == 0)
        }
    }

    private var needsYouThreadModels: [CursorThreadRowModel] {
        liveThreadModels(needsYouLiveRows)
    }

    private func nonNeedsYouRows(matching predicate: (Date) -> Bool) -> [CursorShellLiveBridge.ThreadRow] {
        sortedScopedLiveRows.filter { row in
            guard !needsYouIDs.contains(row.id) else { return false }
            guard let updatedAt = row.updatedAt else { return false }
            return predicate(updatedAt)
        }
    }

    @ViewBuilder
    private func homeAttentionSection(colors: CursorColors) -> some View {
        if let status = homeAttentionStatus {
            Text(status)
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.mutedText)
                .padding(.horizontal, CursorMetrics.sectionHeaderHorizontalPadding)
                .padding(.top, CursorMetrics.sectionHeaderTopPadding)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("home-attention-status")
        }

        if needsYouCount > 0 {
            CursorSectionHeader("Needs you (\(needsYouCount))")
                .accessibilityIdentifier("home-needs-you-header")
            ForEach(needsYouThreadModels) { model in
                Button(action: { onSelectThread(model.title) }) {
                    CursorThreadRow(model: model, showRepoTag: workspaceName == "All Repos")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-needs-you-row")
            }
        }
    }

    /// True when the All Repos view should render grouped-by-repo sections from live data.
    private var showRepoGrouped: Bool {
        workspaceName == "All Repos" && liveBridge != nil && !allLiveThreads.isEmpty
    }

    /// Live threads grouped by repoName, excluding rows already shown under Needs you.
    private var liveThreadsGroupedByRepo: [RepoGroup] {
        var order: [String] = []
        var grouped: [String: [CursorShellLiveBridge.ThreadRow]] = [:]
        let remainder = sortedLiveRows(allLiveThreads).filter { !needsYouIDs.contains($0.id) }
        for row in remainder {
            if grouped[row.repoName] == nil {
                order.append(row.repoName)
                grouped[row.repoName] = []
            }
            grouped[row.repoName]!.append(row)
        }
        return order.compactMap { repoName in
            let rows = grouped[repoName]!
            guard !rows.isEmpty else { return nil }
            return RepoGroup(
                repoName: repoName,
                threads: liveThreadModels(rows)
            )
        }
    }

    // MARK: - Single-workspace live / seed paths

    // Real date-bucketed grouping. Previously `todayThreads` returned every
    // live thread unconditionally (no date check at all) and `yesterdayThreads`
    // returned `[]` whenever there was any live data — so a 3-day-old
    // conversation rendered under "Today" and "Yesterday" never showed
    // anything for a live workspace. `updatedAt` is nil-safe: a row with no
    // timestamp sorts into "Earlier" rather than defaulting to "Today".
    private var todayThreads: [CursorThreadRowModel] {
        if hasLiveThreads {
            let rows = nonNeedsYouRows { Calendar.current.isDateInToday($0) }
            return liveThreadModels(rows, markFirstActive: true)
        }
        return seedTodayThreads
    }

    private var yesterdayThreads: [CursorThreadRowModel] {
        if hasLiveThreads {
            let rows = nonNeedsYouRows { Calendar.current.isDateInYesterday($0) }
            return liveThreadModels(rows)
        }
        return seedYesterdayThreads
    }

    private var earlierThreads: [CursorThreadRowModel] {
        guard hasLiveThreads else { return [] }
        let rows = sortedScopedLiveRows.filter { row in
            guard !needsYouIDs.contains(row.id) else { return false }
            guard let updatedAt = row.updatedAt else { return true }
            return !Calendar.current.isDateInToday(updatedAt) && !Calendar.current.isDateInYesterday(updatedAt)
        }
        return liveThreadModels(rows)
    }

    private var seedTodayThreads: [CursorThreadRowModel] {
        switch workspaceName {
        case "push-backend":
            return [
                CursorThreadRowModel(
                    title: "Fix relay reconnect race on redeploy",
                    repoName: workspaceName,
                    isActive: true,
                    statusLine: .checksPassed(diffAdded: 88, diffRemoved: 12)
                ),
                CursorThreadRowModel(
                    title: "Add App Attest verification to /approval",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .checksPassed(diffAdded: 54, diffRemoved: 3)
                )
            ]
        case "lancer-mac":
            return [
                CursorThreadRowModel(
                    title: "Wire menu-bar diagnostics folder picker",
                    repoName: workspaceName,
                    isActive: true,
                    statusLine: .checksPassed(diffAdded: 71, diffRemoved: 9)
                ),
                CursorThreadRowModel(
                    title: "Fix MenuBarExtra cold-launch window",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .noChanges
                )
            ]
        case "All Repos":
            return [
                CursorThreadRowModel(
                    title: "Fix onboarding pairing flow",
                    repoName: workspaceName,
                    isActive: true,
                    statusLine: .checksPassed(diffAdded: 142, diffRemoved: 18)
                ),
                CursorThreadRowModel(
                    title: "Update relay retry backoff",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .checksPassed(diffAdded: 31, diffRemoved: 4)
                )
            ]
        default:
            return [
                CursorThreadRowModel(
                    title: "Fix onboarding pairing flow",
                    repoName: workspaceName,
                    isActive: true,
                    statusLine: .checksPassed(diffAdded: 142, diffRemoved: 18)
                ),
                CursorThreadRowModel(
                    title: "Review Siri intent donations",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .noChanges
                )
            ]
        }
    }

    private var seedYesterdayThreads: [CursorThreadRowModel] {
        switch workspaceName {
        case "push-backend":
            return [
                CursorThreadRowModel(
                    title: "Add APP_ATTEST_* env var validation on boot",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .checksPassed(diffAdded: 22, diffRemoved: 2)
                )
            ]
        case "lancer-mac":
            return [
                CursorThreadRowModel(
                    title: "HostControlKit authed socket client",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .checksPassed(diffAdded: 96, diffRemoved: 14)
                )
            ]
        case "All Repos":
            return [
                CursorThreadRowModel(
                    title: "Widget timeline refresh",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .checksPassed(diffAdded: 58, diffRemoved: 9)
                ),
                CursorThreadRowModel(
                    title: "Review Siri intent donations",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .noChanges
                )
            ]
        default:
            return [
                CursorThreadRowModel(
                    title: "Widget timeline refresh",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .checksPassed(diffAdded: 58, diffRemoved: 9)
                ),
                CursorThreadRowModel(
                    title: "Tighten TOFU host-key prompt copy",
                    repoName: workspaceName,
                    isActive: false,
                    statusLine: .noChanges
                )
            ]
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(
                    CursorIconButton(systemImageName: "chevron.left", action: onBack)
                ),
                trailing: [
                    CursorIconButton(systemImageName: "magnifyingglass", action: onOpenSearch),
                    CursorIconButton(systemImageName: "line.3.horizontal", action: onOpenMenu)
                ]
            )

            Text(workspaceName)
                .font(CursorType.pageTitle)
                .foregroundColor(CursorColors.light.primaryText)
                .lineLimit(1)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 0) {
                    if showRepoGrouped {
                        homeAttentionSection(colors: CursorColors.resolve(.light))
                        ForEach(liveThreadsGroupedByRepo) { group in
                            CursorSectionHeader(group.repoName)
                                .accessibilityIdentifier("repo-section-\(group.repoName)")
                            ForEach(group.threads) { model in
                                Button(action: { onSelectThread(model.title) }) {
                                    CursorThreadRow(model: model, showRepoTag: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        homeAttentionSection(colors: CursorColors.resolve(.light))

                        if !todayThreads.isEmpty {
                            CursorSectionHeader("Today")
                            ForEach(todayThreads) { model in
                                Button(action: { onSelectThread(model.title) }) {
                                    CursorThreadRow(model: model, showRepoTag: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !yesterdayThreads.isEmpty {
                            CursorSectionHeader("Yesterday")
                            ForEach(yesterdayThreads) { model in
                                Button(action: { onSelectThread(model.title) }) {
                                    CursorThreadRow(model: model, showRepoTag: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !earlierThreads.isEmpty {
                            CursorSectionHeader("Earlier")
                            ForEach(earlierThreads) { model in
                                Button(action: { onSelectThread(model.title) }) {
                                    CursorThreadRow(model: model, showRepoTag: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if liveBridge != nil,
                           todayThreads.isEmpty,
                           yesterdayThreads.isEmpty,
                           earlierThreads.isEmpty {
                            liveEmptyState
                        }
                    }
                }
            }
        }
        .background(CursorColors.light.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CursorBottomComposer(onTap: onOpenComposer)
        }
        .environment(\.cursorScheme, .light)
    }

    private var liveEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No threads yet")
                .font(CursorType.rowTitle)
                .foregroundColor(CursorColors.light.primaryText)
            Text("Send a prompt from this workspace to start the first conversation.")
                .font(CursorType.rowSecondary)
                .foregroundColor(CursorColors.light.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
