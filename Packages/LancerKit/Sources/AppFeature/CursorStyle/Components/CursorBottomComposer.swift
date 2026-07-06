#if os(iOS)
import SwiftUI

/// Floating stadium-shaped composer pinned above the safe area.
public struct CursorBottomComposer: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var text: String = ""

    private let placeholder: String

    public init(placeholder: String = "Plan, ask, build...") {
        self.placeholder = placeholder
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: CursorMetrics.composerSpacing) {
            TextField(placeholder, text: $text)
                .font(CursorType.composerPlaceholder)
                .foregroundColor(colors.primaryText)
                .tint(colors.primaryText)

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: CursorMetrics.composerSendIconSize, weight: .regular))
                .foregroundColor(colors.primaryText)
        }
        .padding(.horizontal, CursorMetrics.composerInnerHorizontalPadding)
        .frame(height: CursorMetrics.composerHeight)
        .background(
            Capsule().fill(colors.composerBackground)
        )
        .padding(.horizontal, CursorMetrics.composerHorizontalMargin)
        .padding(.bottom, CursorMetrics.composerBottomPadding)
    }
}
#endif
