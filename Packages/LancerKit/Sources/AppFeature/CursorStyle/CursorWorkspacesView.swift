#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual clone of Cursor's mobile Workspaces list: an "All Repos" entry plus
/// one row per repo. Static seed data only — no daemon/network wiring.
public struct CursorWorkspacesView: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let onSelectWorkspace: (String) -> Void
    private let onOpenComposer: () -> Void
    private let onOpenProfile: () -> Void
    private let onOpenSearch: () -> Void
    private let onRequestPairing: () -> Void

    public init(
        onSelectWorkspace: @escaping (String) -> Void = { _ in },
        onOpenComposer: @escaping () -> Void = {},
        onOpenProfile: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {},
        onRequestPairing: @escaping () -> Void = {}
    ) {
        self.onSelectWorkspace = onSelectWorkspace
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
                    if let liveBridge, !liveBridge.workspaces.isEmpty {
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
                                CursorListRow(
                                    iconSystemName: "folder",
                                    title: workspace.name,
                                    trailingCount: workspace.threadCount > 0 ? workspace.threadCount : nil,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        seedWorkspaceRows
                    }

                    CursorListRow(
                        iconSystemName: "folder.badge.plus",
                        title: "Add Repo",
                        trailingCount: nil,
                        showChevron: false
                    )
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

        Button(action: { onSelectWorkspace("push-backend") }) {
            CursorListRow(
                iconSystemName: "folder",
                title: "push-backend",
                trailingCount: 2,
                showChevron: true
            )
        }
        .buttonStyle(.plain)

        Button(action: { onSelectWorkspace("lancer-mac") }) {
            CursorListRow(
                iconSystemName: "folder",
                title: "lancer-mac",
                trailingCount: nil,
                showChevron: true
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
