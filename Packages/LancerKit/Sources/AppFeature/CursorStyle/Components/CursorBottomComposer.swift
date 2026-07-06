#if os(iOS)
import SwiftUI

/// Floating stadium-shaped composer pinned above the safe area.
///
/// When `onTap` is set the field is a tap target that opens the expanded
/// composer sheet — the inline `TextField` is visual-only (disabled) and an
/// invisible button on top forwards the touch. XCUITest can synthesize a tap
/// on the placeholder `TextField` accessibility element; the overlay button
/// uses the same accessibility label so either target opens the sheet.
public struct CursorBottomComposer: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var text: String = ""

    private let placeholder: String
    private let onTap: (() -> Void)?

    public init(
        placeholder: String = "Plan, ask, build...",
        onTap: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self.onTap = onTap
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        Group {
            if let onTap {
                ZStack {
                    composerChrome(colors: colors, editable: false)
                        .allowsHitTesting(false)
                    Button(action: onTap) {
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: CursorMetrics.composerHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(placeholder)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("cursor-composer-tap")
                }
            } else {
                composerChrome(colors: colors, editable: true)
            }
        }
        .padding(.horizontal, CursorMetrics.composerHorizontalMargin)
        .padding(.bottom, CursorMetrics.composerBottomPadding)
    }

    @ViewBuilder
    private func composerChrome(colors: CursorColors, editable: Bool) -> some View {
        HStack(spacing: CursorMetrics.composerSpacing) {
            if editable {
                TextField(placeholder, text: $text)
                    .font(CursorType.composerPlaceholder)
                    .foregroundColor(colors.primaryText)
                    .tint(colors.primaryText)
            } else {
                TextField(placeholder, text: .constant(""))
                    .font(CursorType.composerPlaceholder)
                    .foregroundColor(colors.primaryText)
                    .tint(colors.primaryText)
            }

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: CursorMetrics.composerSendIconSize, weight: .regular))
                .foregroundColor(colors.primaryText)
        }
        .padding(.horizontal, CursorMetrics.composerInnerHorizontalPadding)
        .frame(height: CursorMetrics.composerHeight)
        .background(
            Capsule().fill(colors.composerBackground)
        )
    }
}
#endif
