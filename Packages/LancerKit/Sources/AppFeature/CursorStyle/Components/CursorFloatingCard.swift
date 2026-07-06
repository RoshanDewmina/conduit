#if os(iOS)
import SwiftUI

/// Floating card chrome matching Cursor mobile: rounded on all corners, subtle
/// shadow, inset from the screen edges — used by the expanded composer sheet.
public struct CursorFloatingCard<Content: View>: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        content()
            .background(colors.sheetBackground)
            .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.floatingCardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CursorMetrics.floatingCardCornerRadius, style: .continuous)
                    .stroke(colors.hairline, lineWidth: 0.5)
            )
            .shadow(
                color: Color.black.opacity(0.10),
                radius: CursorMetrics.floatingCardShadowRadius,
                y: CursorMetrics.floatingCardShadowYOffset
            )
    }
}
#endif
