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

    /// True when the All Repos view should render grouped-by-repo sections from live data.
    private var showRepoGrouped: Bool {
        workspaceName == "All Repos" && liveBridge != nil && !allLiveThreads.isEmpty
    }

    /// Live threads grouped by repoName, in first-seen order (deterministic for a given bridge snapshot).
    private var liveThreadsGroupedByRepo: [RepoGroup] {
        var order: [String] = []
        var grouped: [String: [CursorShellLiveBridge.ThreadRow]] = [:]
        for row in allLiveThreads {
            if grouped[row.repoName] == nil {
                order.append(row.repoName)
                grouped[row.repoName] = []
            }
            grouped[row.repoName]!.append(row)
        }
        return order.map { repoName in
            let rows = grouped[repoName]!
            return RepoGroup(
                repoName: repoName,
                threads: rows.enumerated().map { index, row in
                    CursorThreadRowModel(
                        id: UUID(uuidString: row.id) ?? UUID(),
                        title: row.title,
                        repoName: row.repoName,
                        isActive: index == 0,
                        statusLine: .noChanges,
                        attention: liveBridge?.threadAttention[row.id]
                    )
                }
            )
        }
    }

    // MARK: - Single-workspace live / seed paths

    private var todayThreads: [CursorThreadRowModel] {
        if let liveBridge, !liveBridge.threads(for: workspaceName).isEmpty {
            return liveThreadsSection(liveBridge.threads(for: workspaceName))
        }
        return seedTodayThreads
    }

    private var yesterdayThreads: [CursorThreadRowModel] {
        if let liveBridge, !liveBridge.threads(for: workspaceName).isEmpty {
            return []
        }
        return seedYesterdayThreads
    }

    private func liveThreadsSection(_ rows: [CursorShellLiveBridge.ThreadRow]) -> [CursorThreadRowModel] {
        rows.enumerated().map { index, row in
            CursorThreadRowModel(
                id: UUID(uuidString: row.id) ?? UUID(),
                title: row.title,
                repoName: row.repoName,
                isActive: index == 0,
                statusLine: .noChanges,
                attention: liveBridge?.threadAttention[row.id]
            )
        }
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
                        CursorSectionHeader("Today")
                        ForEach(todayThreads) { model in
                            Button(action: { onSelectThread(model.title) }) {
                                CursorThreadRow(model: model, showRepoTag: false)
                            }
                            .buttonStyle(.plain)
                        }

                        CursorSectionHeader("Yesterday")
                        ForEach(yesterdayThreads) { model in
                            Button(action: { onSelectThread(model.title) }) {
                                CursorThreadRow(model: model, showRepoTag: false)
                            }
                            .buttonStyle(.plain)
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
}
#endif
