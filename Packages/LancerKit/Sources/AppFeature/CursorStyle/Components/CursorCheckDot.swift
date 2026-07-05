#if os(iOS)
import SwiftUI

/// Small reusable checkbox-style circle: filled with a checkmark when done,
/// empty outline when not — used by Work Thread's to-do card rows.
public struct CursorCheckDot: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let isChecked: Bool

    public init(isChecked: Bool) {
        self.isChecked = isChecked
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        ZStack {
            if isChecked {
                Circle()
                    .fill(colors.mutedText)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(colors.cardBackground)
            } else {
                Circle()
                    .stroke(colors.mutedText, lineWidth: CursorMetrics.checkDotBorderWidth)
            }
        }
        .frame(width: CursorMetrics.checkDotDiameter, height: CursorMetrics.checkDotDiameter)
    }
}
#endif
