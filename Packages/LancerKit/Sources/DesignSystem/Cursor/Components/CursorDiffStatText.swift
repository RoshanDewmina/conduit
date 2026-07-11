#if os(iOS)
import SwiftUI

/// Renders "+N" in green and "-N" in red as one inline unit. Shared by thread
/// status lines, PR file rows, and pill-button diff suffixes (IMG_2409–2411).
public struct CursorDiffStatText: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let added: Int
    private let removed: Int
    private let font: Font
    private let spacing: CGFloat

    public init(
        added: Int,
        removed: Int,
        font: Font = CursorType.rowSecondary,
        spacing: CGFloat = 4
    ) {
        self.added = added
        self.removed = removed
        self.font = font
        self.spacing = spacing
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: spacing) {
            if added > 0 {
                Text("+\(added)")
                    .font(font)
                    .foregroundColor(colors.successGreen)
            }
            if removed > 0 {
                Text("-\(removed)")
                    .font(font)
                    .foregroundColor(colors.dangerRed)
            }
        }
    }
}
#endif
