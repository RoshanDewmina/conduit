#if os(iOS)
import CoreGraphics

/// Every hardcoded spacing/size/radius number used by Cursor-style components,
/// named so a future design tweak is a one-line change here instead of a hunt
/// through component bodies.
public enum CursorMetrics {
    // MARK: Header / icon buttons
    public static let headerButtonDiameter: CGFloat = 44
    public static let headerIconSize: CGFloat = 18
    public static let headerHorizontalPadding: CGFloat = 16
    public static let headerTopPadding: CGFloat = 8
    public static let headerSpacing: CGFloat = 12

    // MARK: Page title
    public static let pageTitleLeadingPadding: CGFloat = 16
    public static let pageTitleTopPadding: CGFloat = 12

    // MARK: Rows (CursorListRow / CursorThreadRow)
    public static let rowHorizontalPadding: CGFloat = 16
    public static let rowVerticalPadding: CGFloat = 14
    public static let rowIconSize: CGFloat = 24
    public static let rowSpacing: CGFloat = 12
    public static let rowHairlineHeight: CGFloat = 1
    public static let rowHairlineLeadingInsetWithIcon: CGFloat = 52
    public static let threadRowStatusDotSize: CGFloat = 9
    public static let threadRowStatusDotTopPadding: CGFloat = 5
    public static let threadRowHairlineLeadingInset: CGFloat = 37
    public static let threadRowContentSpacing: CGFloat = 4
    public static let threadRowStatusSpacing: CGFloat = 6
    public static let repoTagHorizontalPadding: CGFloat = 8
    public static let repoTagVerticalPadding: CGFloat = 3

    // MARK: Composer
    public static let composerHeight: CGFloat = 54
    public static let composerHorizontalMargin: CGFloat = 16
    public static let composerBottomPadding: CGFloat = 8
    public static let composerInnerHorizontalPadding: CGFloat = 18
    public static let composerSpacing: CGFloat = 10
    public static let composerSendIconSize: CGFloat = 26

    // MARK: Section header
    public static let sectionHeaderHorizontalPadding: CGFloat = 16
    public static let sectionHeaderTopPadding: CGFloat = 16
    public static let sectionHeaderBottomPadding: CGFloat = 6

    // MARK: Bottom sheet container
    public static let sheetTopCornerRadius: CGFloat = 24
    public static let sheetDragHandleWidth: CGFloat = 36
    public static let sheetDragHandleHeight: CGFloat = 5
    public static let sheetDragHandleTopPadding: CGFloat = 8
    public static let sheetDragHandleBottomPadding: CGFloat = 12
    public static let sheetHeaderHorizontalPadding: CGFloat = 16
    public static let sheetHeaderBottomPadding: CGFloat = 12
    public static let sheetLeadingButtonDiameter: CGFloat = 32
    public static let sheetContentBottomPadding: CGFloat = 24

    // MARK: Composer sheet (expanded, CursorComposerSheet)
    public static let composerSheetPickerSpacing: CGFloat = 16
    public static let composerSheetPickerBottomPadding: CGFloat = 16
    public static let composerSheetTextMinHeight: CGFloat = 96
    public static let composerSheetTextBottomPadding: CGFloat = 12
    public static let composerSheetBottomRowSpacing: CGFloat = 12
    public static let composerSheetBottomRowBottomPadding: CGFloat = 16

    // MARK: Picker sheet rows (CursorRunOnSheet / CursorModelSheet)
    public static let modelRowEllipsisDiameter: CGFloat = 32

    // MARK: Search field
    public static let searchFieldHeight: CGFloat = 40
    public static let searchFieldHorizontalPadding: CGFloat = 12
    public static let searchFieldIconSpacing: CGFloat = 8
    public static let searchFieldMargin: CGFloat = 16

    // MARK: Pill button / action rail
    public static let pillButtonHeight: CGFloat = 40
    public static let pillButtonHorizontalPadding: CGFloat = 16
    public static let pillButtonSpacing: CGFloat = 6
    public static let pillButtonBorderWidth: CGFloat = 1
    public static let actionRailSpacing: CGFloat = 8
    public static let actionRailHorizontalPadding: CGFloat = 16
    public static let actionRailVerticalPadding: CGFloat = 10

    // MARK: Artifact card
    public static let cardCornerRadius: CGFloat = 16
    public static let cardPadding: CGFloat = 16
    public static let cardHairlineHeight: CGFloat = 1

    // MARK: Check dot
    public static let checkDotDiameter: CGFloat = 22
    public static let checkDotBorderWidth: CGFloat = 1.5

    // MARK: Status badge
    public static let statusBadgeIconSize: CGFloat = 15
    public static let statusBadgeSpacing: CGFloat = 6
    public static let statusBadgeHorizontalPadding: CGFloat = 10
    public static let statusBadgeVerticalPadding: CGFloat = 5

    // MARK: Diff view
    public static let diffLineNumberWidth: CGFloat = 34
    public static let diffLeftEdgeBarWidth: CGFloat = 3
    public static let diffLineVerticalPadding: CGFloat = 2
    public static let diffLineHorizontalPadding: CGFloat = 8
    public static let diffContextBarVerticalPadding: CGFloat = 8
    public static let diffContextBarCornerRadius: CGFloat = 8
}
#endif
