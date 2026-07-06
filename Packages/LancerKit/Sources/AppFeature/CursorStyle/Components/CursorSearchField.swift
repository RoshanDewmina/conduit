#if os(iOS)
import SwiftUI
import DesignSystem

/// Rounded pill search input: leading magnifying-glass icon, `TextField` with
/// placeholder "Search", light gray fill — used inside the Model-picker sheet.
public struct CursorSearchField: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Binding private var text: String

    public init(text: Binding<String>) {
        self._text = text
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: CursorMetrics.searchFieldIconSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(colors.secondaryText)
            TextField("Search", text: $text)
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
                .tint(colors.primaryText)
        }
        .padding(.horizontal, CursorMetrics.searchFieldHorizontalPadding)
        .frame(height: CursorMetrics.searchFieldHeight)
        .background(
            Capsule().fill(colors.composerBackground)
        )
        .padding(.horizontal, CursorMetrics.searchFieldMargin)
    }
}
#endif
