#if os(iOS)
import SwiftUI

/// Detail/sheet header: optional back, breadcrumb, title, trailing controls.
public struct CursorDetailHeader<Trailing: View>: View {
    @Environment(\.cursorScheme) private var cursorScheme

    let title: String
    let breadcrumb: String?
    let onBack: (() -> Void)?
    let trailing: Trailing

    public init(
        _ title: String,
        breadcrumb: String? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.breadcrumb = breadcrumb
        self.onBack = onBack
        self.trailing = trailing()
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: 10) {
            if let onBack {
                CursorIconButton(systemImageName: "chevron.left", action: onBack)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let breadcrumb {
                    Text(breadcrumb)
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                        .lineLimit(1)
                }
                Text(title)
                    .font(CursorType.sheetTitle)
                    .foregroundColor(colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, CursorMetrics.headerHorizontalPadding)
        .padding(.top, CursorMetrics.headerTopPadding)
        .padding(.bottom, 8)
    }
}
#endif
