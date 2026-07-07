#if os(iOS)
import SwiftUI
import DesignSystem

/// Collapsed composer chrome pinned above the safe area.
public enum CursorCollapsedComposerStyle: Sendable {
    /// Workspaces root — placeholder only inside the pill.
    case compact
    /// Work thread follow-up — `+` and mic flank the placeholder (Cursor IMG_2357–2361).
    case followUp
}

/// Floating stadium-shaped composer pinned above the safe area.
///
/// When `onTap` is set the field is a tap target that opens the expanded
/// composer sheet — the inline field is visual-only and an invisible button on
/// top forwards the touch.
public struct CursorBottomComposer: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var text: String = ""

    private let placeholder: String
    private let style: CursorCollapsedComposerStyle
    private let hasDraft: Bool
    private let onTap: (() -> Void)?

    public init(
        placeholder: String = "Plan, ask, build...",
        style: CursorCollapsedComposerStyle = .compact,
        hasDraft: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self.style = style
        self.hasDraft = hasDraft
        self.onTap = onTap
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(alignment: .leading, spacing: 0) {
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

            if hasDraft {
                Text("Draft saved")
                    .font(CursorType.logLine)
                    .foregroundColor(colors.mutedText)
                    .padding(.horizontal, CursorMetrics.composerHorizontalMargin + CursorMetrics.composerInnerHorizontalPadding)
                    .padding(.top, 4)
            }
        }
        .padding(.bottom, CursorMetrics.composerBottomPadding)
    }

    @ViewBuilder
    private func composerChrome(colors: CursorColors, editable: Bool) -> some View {
        HStack(spacing: CursorMetrics.composerSpacing) {
            if style == .followUp && !editable {
                accessoryIcon(systemName: "plus", colors: colors)
            }

            if editable {
                TextField(placeholder, text: $text)
                    .font(CursorType.composerPlaceholder)
                    .foregroundColor(colors.primaryText)
                    .tint(colors.primaryText)
            } else {
                Text(placeholder)
                    .font(CursorType.composerPlaceholder)
                    .foregroundColor(colors.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if style == .followUp && !editable {
                accessoryIcon(systemName: "mic", colors: colors)
            } else if editable {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: CursorMetrics.composerSendIconSize, weight: .regular))
                    .foregroundColor(colors.primaryText)
            }
        }
        .padding(.horizontal, CursorMetrics.composerInnerHorizontalPadding)
        .frame(height: CursorMetrics.composerHeight)
        .background(
            RoundedRectangle(cornerRadius: CursorMetrics.composerCornerRadius, style: .continuous)
                .fill(colors.sheetBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CursorMetrics.composerCornerRadius, style: .continuous)
                .stroke(colors.hairline, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(cursorScheme == .light ? 0.08 : 0), radius: 12, y: 4)
    }

    private func accessoryIcon(systemName: String, colors: CursorColors) -> some View {
        Image(systemName: systemName)
            .font(.system(size: CursorMetrics.composerAccessoryIconSize, weight: .medium))
            .foregroundColor(colors.secondaryText)
            .frame(width: CursorMetrics.composerAccessoryTapSize, height: CursorMetrics.composerAccessoryTapSize)
    }
}
#endif
