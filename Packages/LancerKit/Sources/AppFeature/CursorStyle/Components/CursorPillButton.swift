#if os(iOS)
import SwiftUI

/// Stadium-shaped button used for Work Thread's action rail buttons and
/// Ship & History's "Mark Ready" button.
public struct CursorPillButton: View {
    public enum Style: Sendable {
        /// Dark/filled, e.g. "Mark Ready".
        case primary
        /// Outline, e.g. "View PR +858 -38".
        case secondary
    }

    /// One colored text segment, e.g. `("+858", .green)` or `("View PR", nil)`
    /// for the default label color — lets callers compose colored diffstat
    /// suffixes onto a single pill's label.
    public struct Segment: Sendable {
        public let text: String
        public let color: Color?

        public init(_ text: String, color: Color? = nil) {
            self.text = text
            self.color = color
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme

    private let segments: [Segment]
    private let style: Style
    /// Stretches the capsule to fill its container's width, e.g. Ship &
    /// History's checks-passed card "Mark Ready" button (IMG_2364).
    private let fullWidth: Bool
    private let action: () -> Void

    public init(title: String, style: Style = .secondary, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.segments = [Segment(title)]
        self.style = style
        self.fullWidth = fullWidth
        self.action = action
    }

    public init(segments: [Segment], style: Style = .secondary, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.segments = segments
        self.style = style
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        Button(action: action) {
            HStack(spacing: CursorMetrics.pillButtonSpacing) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Text(segment.text)
                        .font(CursorType.pillLabel)
                        .foregroundColor(segment.color ?? labelColor(colors))
                }
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, CursorMetrics.pillButtonHorizontalPadding)
            .frame(height: CursorMetrics.pillButtonHeight)
            .background(background(colors))
            .overlay(border(colors))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func labelColor(_ colors: CursorColors) -> Color {
        switch style {
        case .primary: return colors.pillPrimaryText
        case .secondary: return colors.pillSecondaryText
        }
    }

    @ViewBuilder
    private func background(_ colors: CursorColors) -> some View {
        switch style {
        case .primary:
            Capsule().fill(colors.pillPrimaryBackground)
        case .secondary:
            Capsule().fill(colors.cardBackground)
        }
    }

    @ViewBuilder
    private func border(_ colors: CursorColors) -> some View {
        switch style {
        case .primary:
            EmptyView()
        case .secondary:
            Capsule().stroke(colors.pillSecondaryBorder, lineWidth: CursorMetrics.pillButtonBorderWidth)
        }
    }
}
#endif
