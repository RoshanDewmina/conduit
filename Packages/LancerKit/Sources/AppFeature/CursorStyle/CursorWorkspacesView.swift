#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual clone of Cursor's mobile Workspaces list: an "All Repos" entry plus
/// one row per repo. Live shell rows come from `CursorShellLiveBridge`; seeded
/// rows are restricted to the no-bridge DEBUG/mock shell.
public struct CursorWorkspacesView: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.cursorShellLiveBridge) private var liveBridge

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

                        CursorListRow(
                            iconSystemName: "folder.badge.plus",
                            title: "Add Repo",
                            trailingCount: nil,
                            showChevron: false
                        )
                    }
                }
            }
        }
        .background(colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CursorBottomComposer(onTap: onOpenComposer)
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
#endif
