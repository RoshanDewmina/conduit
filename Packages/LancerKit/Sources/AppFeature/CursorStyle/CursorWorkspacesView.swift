#if os(iOS)
import SwiftUI

/// Visual clone of Cursor's mobile Workspaces list: an "All Repos" entry plus
/// one row per repo. Static seed data only — no daemon/network wiring.
public struct CursorWorkspacesView: View {
    private let onSelectWorkspace: (String) -> Void
    private let onOpenComposer: () -> Void

    public init(
        onSelectWorkspace: @escaping (String) -> Void = { _ in },
        onOpenComposer: @escaping () -> Void = {}
    ) {
        self.onSelectWorkspace = onSelectWorkspace
        self.onOpenComposer = onOpenComposer
    }

    public var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(avatarCircle),
                trailing: [
                    CursorIconButton(systemImageName: "magnifyingglass", action: {}),
                    CursorIconButton(systemImageName: "plus", action: {})
                ]
            )

            Text("Workspaces")
                .font(CursorType.pageTitle)
                .foregroundColor(CursorColors.light.primaryText)
                .padding(.leading, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 0) {
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
