#if os(iOS)
import SwiftUI
import DesignSystem

/// Renders "+142" in green and "-18" in red as one inline unit. Shared by
/// `CursorThreadRow`'s status line and PR file-list rows (Ship & History).
public struct CursorDiffStatText: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let added: Int
    private let removed: Int
    private let font: Font

    public init(added: Int, removed: Int, font: Font = CursorType.rowSecondary) {
        self.added = added
        self.removed = removed
        self.font = font
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: 4) {
            Text("+\(added)")
                .font(font)
                .foregroundColor(colors.successGreen)
            Text("-\(removed)")
                .font(font)
                .foregroundColor(colors.dangerRed)
        }
    }
}
#endif
