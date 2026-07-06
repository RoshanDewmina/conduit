#if os(iOS)
import SwiftUI

/// Floating horizontal row of `CursorPillButton`s plus an optional trailing
/// chevron-down "collapse" icon button, pinned above the bottom composer via
/// `.safeAreaInset`. Background is a solid translucent fill approximating the
/// blurred bar seen in the Work Thread screenshots (IMG_2357/2360/2361).
public struct CursorActionRail: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let buttons: [CursorPillButton]
    private let onCollapse: (() -> Void)?

    public init(buttons: [CursorPillButton], onCollapse: (() -> Void)? = nil) {
        self.buttons = buttons
        self.onCollapse = onCollapse
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: CursorMetrics.actionRailSpacing) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                button
            }
            if let onCollapse {
                Spacer()
                CursorIconButton(
                    systemImageName: "chevron.down",
                    diameter: CursorMetrics.pillButtonHeight,
                    action: onCollapse
                )
            }
        }
        .padding(.horizontal, CursorMetrics.actionRailHorizontalPadding)
        .padding(.vertical, CursorMetrics.actionRailVerticalPadding)
        .background(colors.background.opacity(0.85))
    }
}
#endif
