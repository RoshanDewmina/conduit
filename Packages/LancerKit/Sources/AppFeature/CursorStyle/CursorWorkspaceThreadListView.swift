#if os(iOS)
import SwiftUI

/// Visual clone of Cursor's mobile per-repo thread list: unlike `CursorHomeView`
/// (a cross-repo aggregate), this is scoped to a single workspace, with a
/// back-chevron + search + hamburger header instead of the avatar+search+plus
/// header Home/Workspaces use. Static seed data only — no daemon/network wiring.
public struct CursorWorkspaceThreadListView: View {
    private let workspaceName: String
    private let onBack: () -> Void
    private let onSelectThread: (String) -> Void
    private let onOpenComposer: () -> Void

    public init(
        workspaceName: String,
        onBack: @escaping () -> Void = {},
        onSelectThread: @escaping (String) -> Void = { _ in },
        onOpenComposer: @escaping () -> Void = {}
    ) {
        self.workspaceName = workspaceName
        self.onBack = onBack
        self.onSelectThread = onSelectThread
        self.onOpenComposer = onOpenComposer
    }

    private var todayThreads: [CursorThreadRowModel] {
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

    private var yesterdayThreads: [CursorThreadRowModel] {
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
                    CursorIconButton(systemImageName: "magnifyingglass", action: {}),
                    CursorIconButton(systemImageName: "line.3.horizontal", action: {})
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
        .background(CursorColors.light.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CursorBottomComposer()
                .overlay(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onOpenComposer)
                )
        }
        .environment(\.cursorScheme, .light)
    }
}
#endif
