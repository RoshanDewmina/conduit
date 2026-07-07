#if os(iOS)
import SwiftUI

/// A simple list row: optional leading icon, title, optional trailing count
/// badge, optional chevron, with a bottom hairline divider inset to the title.
public struct CursorListRow: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let iconSystemName: String?
    private let title: String
    private let titleColor: Color?
    private let trailingCount: Int?
    private let trailingText: String?
    private let showChevron: Bool

    public init(
        iconSystemName: String? = nil,
        title: String,
        titleColor: Color? = nil,
        trailingCount: Int? = nil,
        trailingText: String? = nil,
        showChevron: Bool = false
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.titleColor = titleColor
        self.trailingCount = trailingCount
        self.trailingText = trailingText
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
                    .foregroundColor(titleColor ?? colors.primaryText)
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                }
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
        // Without this, a tap in the `Spacer()` gap between the title and
        // trailing content (or anywhere else with no rendered glyph) misses
        // every gesture recognizer entirely — the accessibility frame still
        // reports the full row, so a tap synthesized at its center (which is
        // exactly where that gap usually falls) silently no-ops instead of
        // firing whatever Button wraps this row. Confirmed via XCUITest: a
        // synthesized tap on this row's accessibility element never fired
        // the wrapping Button's action until this was added.
        .contentShape(Rectangle())
    }
}
#endif
