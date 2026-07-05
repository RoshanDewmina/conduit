#if os(iOS)
import SwiftUI

/// Visual clone of Cursor's mobile Workspaces list: an "All Repos" entry plus
/// one row per repo. Static seed data only — no daemon/network wiring.
public struct CursorWorkspacesView: View {
    public init() {}

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
                .foregroundColor(CursorPalette.primaryText)
                .padding(.leading, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 0) {
                    CursorListRow(
                        iconSystemName: "square.stack.3d.up",
                        title: "All Repos",
                        trailingCount: 3,
                        showChevron: true
                    )
                    CursorListRow(
                        iconSystemName: "folder",
                        title: "lancer-ios",
                        trailingCount: 4,
                        showChevron: true
                    )
                    CursorListRow(
                        iconSystemName: "folder",
                        title: "push-backend",
                        trailingCount: 2,
                        showChevron: true
                    )
                    CursorListRow(
                        iconSystemName: "folder",
                        title: "lancer-mac",
                        trailingCount: nil,
                        showChevron: true
                    )
                    CursorListRow(
                        iconSystemName: "folder.badge.plus",
                        title: "Add Repo",
                        trailingCount: nil,
                        showChevron: false
                    )
                }
            }
        }
        .background(CursorPalette.pageBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CursorBottomComposer()
        }
        .environment(\.colorScheme, .light)
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
