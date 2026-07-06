#if os(iOS)
import SwiftUI

/// Visual clone of Cursor's mobile Home: a cross-repo ledger of recent threads
/// grouped by day, each row tagged with its originating repo. Static seed data
/// only — no daemon/network wiring.
public struct CursorHomeView: View {
    private let onSelectThread: (String) -> Void
    private let onOpenComposer: () -> Void

    public init(
        onSelectThread: @escaping (String) -> Void = { _ in },
        onOpenComposer: @escaping () -> Void = {}
    ) {
        self.onSelectThread = onSelectThread
        self.onOpenComposer = onOpenComposer
    }

    private var todayThreads: [CursorThreadRowModel] {
        [
            CursorThreadRowModel(
                title: "Fix onboarding pairing flow",
                repoName: "lancer-ios",
                isActive: true,
                statusLine: .checksPassed(diffAdded: 142, diffRemoved: 18)
            ),
            CursorThreadRowModel(
                title: "Update relay retry backoff",
                repoName: "push-backend",
                isActive: false,
                statusLine: .checksPassed(diffAdded: 31, diffRemoved: 4)
            )
        ]
    }

    private var yesterdayThreads: [CursorThreadRowModel] {
        [
            CursorThreadRowModel(
                title: "Review Siri intent donations",
                repoName: "lancer-ios",
                isActive: false,
                statusLine: .noChanges
            ),
            CursorThreadRowModel(
                title: "Widget timeline refresh",
                repoName: "lancer-mac",
                isActive: false,
                statusLine: .checksPassed(diffAdded: 58, diffRemoved: 9)
            )
        ]
    }

    public var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(avatarCircle),
                trailing: [
                    CursorIconButton(systemImageName: "magnifyingglass", action: {})
                ]
            )

            Text("Home")
                .font(CursorType.pageTitle)
                .foregroundColor(CursorColors.light.primaryText)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 0) {
                    CursorSectionHeader("Today")
                    ForEach(todayThreads) { model in
                        Button(action: { onSelectThread(model.title) }) {
                            CursorThreadRow(model: model, showRepoTag: true)
                        }
                        .buttonStyle(.plain)
                    }

                    CursorSectionHeader("Yesterday")
                    ForEach(yesterdayThreads) { model in
                        Button(action: { onSelectThread(model.title) }) {
                            CursorThreadRow(model: model, showRepoTag: true)
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
}
#endif
