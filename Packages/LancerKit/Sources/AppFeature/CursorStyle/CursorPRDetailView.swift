#if os(iOS)
import SwiftUI
import DesignSystem

/// Visual clone of Cursor's mobile PR detail / Ship & History screen
/// (IMG_2364-2367): header with back/link/menu actions, the PR title, a
/// status-pills row, an all-checks-passed card with a full-width "Mark Ready"
/// button, and a scrollable file list that expands one file's unified diff
/// inline. The real Git/PR data source is not wired for V1 yet, so the live
/// surface renders an explicit deferred state instead of fake PR contents.
public struct CursorPRDetailView: View {
    private let onBack: () -> Void

    public init(onBack: @escaping () -> Void = {}) {
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ship history not built yet")
                        .font(CursorType.pageTitle)
                        .foregroundColor(CursorColors.light.primaryText)
                    Text("Lancer does not yet have a real PR, inline diff, or GitHub status data source in the live Cursor shell. This screen is intentionally withheld from the default navigation path until it can show real host data.")
                        .font(CursorType.bodyText)
                        .foregroundColor(CursorColors.light.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, CursorMetrics.pageTitleLeadingPadding)
                .padding(.top, CursorMetrics.pageTitleTopPadding)
                .padding(.bottom, 24)
            }
        }
        .background(CursorColors.light.background.ignoresSafeArea())
        .environment(\.cursorScheme, .light)
    }

    // MARK: Header

    private var header: some View {
        CursorHeaderBar(
            leading: AnyView(CursorIconButton(systemImageName: "chevron.left", action: onBack)),
            trailing: []
        )
    }
}
#endif
