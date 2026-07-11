#if os(iOS)
import SwiftUI

/// Circular icon button with a hairline border, matching Cursor's header
/// affordances (search, add, close, etc).
public struct CursorIconButton: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let systemImageName: String
    private let diameter: CGFloat
    private let action: () -> Void

    public init(
        systemImageName: String,
        diameter: CGFloat = CursorMetrics.headerButtonDiameter,
        action: @escaping () -> Void
    ) {
        self.systemImageName = systemImageName
        self.diameter = diameter
        self.action = action
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(colors.iconButtonBackground)
                    .overlay(
                        Circle().stroke(colors.iconButtonBorder, lineWidth: 1)
                    )
                    .frame(width: diameter, height: diameter)
                Image(systemName: systemImageName)
                    .font(.system(size: CursorMetrics.headerIconSize, weight: .medium))
                    .foregroundColor(colors.primaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(systemImageName)
    }
}
#endif
