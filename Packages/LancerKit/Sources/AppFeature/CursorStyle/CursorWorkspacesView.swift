#if os(iOS)
import SwiftUI

/// Cursor-style mobile Workspaces list: an "All Repos" entry plus one row per
/// repo. Uses live bridge data when AppRoot provides it; otherwise falls back
/// to seeded rows for design-review UI tests.
public struct CursorWorkspacesView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let onSelectWorkspace: (String) -> Void
    private let onOpenComposer: () -> Void
    private let onOpenProfile: () -> Void
    private let onOpenSearch: () -> Void
    private let onOpenReview: () -> Void

    public init(
        onSelectWorkspace: @escaping (String) -> Void = { _ in },
        onOpenComposer: @escaping () -> Void = {},
        onOpenProfile: @escaping () -> Void = {},
        onOpenSearch: @escaping () -> Void = {},
        onOpenReview: @escaping () -> Void = {}
    ) {
        self.onSelectWorkspace = onSelectWorkspace
        self.onOpenComposer = onOpenComposer
        self.onOpenProfile = onOpenProfile
        self.onOpenSearch = onOpenSearch
        self.onOpenReview = onOpenReview
    }

    private var showsApprovalBanner: Bool {
        guard let liveBridge else { return false }
        return liveBridge.pendingApprovalID != nil
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
                    CursorIconButton(systemImageName: "plus", action: {})
                ]
            )

            if let liveBridge, liveBridge.connectionPhase != .connected {
                CursorConnectionBanner(
                    phase: liveBridge.connectionPhase,
                    onPair: liveBridge.onRequestPairing
                )
            }

            if showsApprovalBanner {
                approvalBanner
            }

            Text("Workspaces")
                .font(CursorType.pageTitle)
                .foregroundColor(CursorColors.light.primaryText)
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
        .background(CursorColors.light.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CursorBottomComposer(onTap: onOpenComposer)
        }
        .environment(\.cursorScheme, .light)
    }

    private var approvalBanner: some View {
        Button(action: onOpenReview) {
            CursorArtifactCard {
                HStack(spacing: 10) {
                    CursorStatusBadge(kind: .risk(level: .high), label: "Needs your approval")
                    Text("Pending approval")
                        .font(CursorType.bodyText)
                        .foregroundColor(CursorColors.light.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(CursorColors.light.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("approval-banner")
        .padding(.horizontal, 16)
        .padding(.top, 8)
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
