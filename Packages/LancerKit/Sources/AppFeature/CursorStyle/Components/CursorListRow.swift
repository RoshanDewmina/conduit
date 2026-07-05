#if os(iOS)
import SwiftUI

/// A simple list row: optional leading icon, title, optional trailing count
/// badge, optional chevron, with a bottom hairline divider inset to the title.
public struct CursorListRow: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let iconSystemName: String?
    private let title: String
    private let trailingCount: Int?
    private let showChevron: Bool

    public init(
        iconSystemName: String? = nil,
        title: String,
        trailingCount: Int? = nil,
        showChevron: Bool = false
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.trailingCount = trailingCount
        self.showChevron = showChevron
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(spacing: 0) {
            HStack(spacing: CursorMetrics.rowSpacing) {
                if let iconSystemName {
                    Image(systemName: iconSystemName)
                        .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
                }
                Text(title)
                    .font(CursorType.rowTitle)
                    .foregroundColor(colors.primaryText)
                Spacer()
                if let trailingCount {
                    Text("\(trailingCount)")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                }
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.mutedText)
                }
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)
            Rectangle()
                .fill(colors.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, iconSystemName != nil ? CursorMetrics.rowHairlineLeadingInsetWithIcon : CursorMetrics.rowHorizontalPadding)
        }
    }
}
#endif
