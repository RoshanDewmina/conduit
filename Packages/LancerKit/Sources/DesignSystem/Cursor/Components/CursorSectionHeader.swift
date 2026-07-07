#if os(iOS)
import SwiftUI

/// Small muted section label, e.g. "Today" / "Yesterday".
public struct CursorSectionHeader: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        Text(title)
            .font(CursorType.sectionHeader)
            .foregroundColor(colors.secondaryText)
            .padding(.horizontal, CursorMetrics.sectionHeaderHorizontalPadding)
            .padding(.top, CursorMetrics.sectionHeaderTopPadding)
            .padding(.bottom, CursorMetrics.sectionHeaderBottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
