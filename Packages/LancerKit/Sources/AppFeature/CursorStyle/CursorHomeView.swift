#if os(iOS)
import SwiftUI

/// Visual clone of Cursor's mobile Home: a cross-repo ledger of recent threads
/// grouped by day, each row tagged with its originating repo.
public struct CursorHomeView: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let onSelectThread: (String) -> Void
    private let onOpenComposer: () -> Void
    private let onOpenInbox: () -> Void

    public init(
        onSelectThread: @escaping (String) -> Void = { _ in },
        onOpenComposer: @escaping () -> Void = {},
        onOpenInbox: @escaping () -> Void = {}
    ) {
        self.onSelectThread = onSelectThread
        self.onOpenComposer = onOpenComposer
        self.onOpenInbox = onOpenInbox
    }

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    private var liveThreadSections: [(label: String, rows: [CursorThreadRowModel])] {
        guard let liveBridge else { return [] }
        let all = liveBridge.threadsByWorkspace.values.flatMap { $0 }
        guard !all.isEmpty else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        var todayRows: [CursorThreadRowModel] = []
        var yesterdayRows: [CursorThreadRowModel] = []
        var olderRows: [CursorThreadRowModel] = []
        for row in all.sorted(by: { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }) {
            let model = CursorThreadRowModel(
                title: row.title,
                repoName: row.repoName,
                isActive: false,
                statusLine: .noChanges
            )
            guard let updated = row.updatedAt else {
                olderRows.append(model)
                continue
            }
            let day = cal.startOfDay(for: updated)
            if day == today { todayRows.append(model) }
            else if day == yesterday { yesterdayRows.append(model) }
            else { olderRows.append(model) }
        }
        var sections: [(String, [CursorThreadRowModel])] = []
        if !todayRows.isEmpty { sections.append(("Today", todayRows)) }
        if !yesterdayRows.isEmpty { sections.append(("Yesterday", yesterdayRows)) }
        if !olderRows.isEmpty { sections.append(("Earlier", olderRows)) }
        return sections
    }

    private var seedSections: [(label: String, rows: [CursorThreadRowModel])] {
        [
            ("Today", [
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
            ]),
            ("Yesterday", [
                CursorThreadRowModel(
                    title: "Review Siri intent donations",
                    repoName: "lancer-ios",
                    isActive: false,
                    statusLine: .noChanges
                )
            ])
        ]
    }

    private var threadSections: [(label: String, rows: [CursorThreadRowModel])] {
        let live = liveThreadSections
        return live.isEmpty ? seedSections : live
    }

    private var pendingCount: Int {
        liveBridge?.pendingApprovalID != nil ? 1 : 0
    }

    public var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(avatarCircle),
                trailing: [
                    CursorIconButton(systemImageName: "magnifyingglass", action: onOpenComposer)
                ]
            )

            Text("Home")
                .font(CursorType.pageTitle)
                .foregroundColor(colors.primaryText)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            if pendingCount > 0 {
                Button(action: onOpenInbox) {
                    HStack {
                        Text("Needs attention")
                            .font(CursorType.rowTitle)
                            .foregroundColor(colors.primaryText)
                        Spacer()
                        Text("\(pendingCount)")
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(colors.mutedText)
                    }
                    .padding(.horizontal, CursorMetrics.pageTitleLeadingPadding)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(threadSections, id: \.label) { section in
                        CursorSectionHeader(section.label)
                        ForEach(section.rows) { model in
                            Button(action: { onSelectThread(model.title) }) {
                                CursorThreadRow(model: model, showRepoTag: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .background(colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CursorBottomComposer(onTap: onOpenComposer)
        }
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
