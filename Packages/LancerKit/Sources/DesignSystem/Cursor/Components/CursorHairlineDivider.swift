#if os(iOS)
import SwiftUI

/// Canonical 1px hairline separator for flat Cursor list surfaces.
public struct CursorHairlineDivider: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let leadingInset: CGFloat
    private let trailingInset: CGFloat

    public init(leadingInset: CGFloat = 0, trailingInset: CGFloat = 0) {
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        Rectangle()
            .fill(colors.hairline)
            .frame(height: CursorMetrics.rowHairlineHeight)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .accessibilityHidden(true)
    }
}
#endif
