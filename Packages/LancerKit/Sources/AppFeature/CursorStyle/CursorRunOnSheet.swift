#if os(iOS)
import SwiftUI
import DesignSystem

/// Cursor-style "Run on" picker sheet: choose which host/target a run
/// dispatches to. Two sections — the currently active target and other
/// available targets — each row showing an icon, a title, and a trailing
/// checkmark on the selection (chevron otherwise, inviting a tap to select).
public struct CursorRunOnSheet: View {
    /// One selectable run target row. Seeded with real Lancer hosts (not
    /// Cursor's own "Cursor Cloud" / "Remote Control" naming).
    public struct CursorRunTargetOption: Identifiable, Sendable {
        public let id: String
        public let icon: String
        public let title: String
        public let isSelected: Bool

        public init(id: String, icon: String, title: String, isSelected: Bool) {
            self.id = id
            self.icon = icon
            self.title = title
            self.isSelected = isSelected
        }
    }

    @Environment(\.cursorScheme) private var cursorScheme

    private let activeTargets: [CursorRunTargetOption]
    private let moreTargets: [CursorRunTargetOption]
    private let onClose: () -> Void
    private let onSelect: (CursorRunTargetOption) -> Void

    public init(
        activeTargets: [CursorRunTargetOption]? = nil,
        moreTargets: [CursorRunTargetOption]? = nil,
        onClose: @escaping () -> Void = {},
        onSelect: @escaping (CursorRunTargetOption) -> Void = { _ in }
    ) {
        self.activeTargets = activeTargets ?? []
        self.moreTargets = moreTargets ?? []
        self.onClose = onClose
        self.onSelect = onSelect
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Run on",
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            VStack(spacing: 0) {
                if activeTargets.isEmpty && moreTargets.isEmpty {
                    emptyState
                } else {
                    CursorSectionHeader("Active")
                    ForEach(activeTargets) { target in
                        row(for: target)
                    }

                    CursorSectionHeader("More")
                    ForEach(moreTargets) { target in
                        row(for: target)
                    }
                }
            }
            .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
        }
    }

    private var emptyState: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return VStack(alignment: .leading, spacing: 6) {
            Text("No run target selected")
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
            Text("Pair a machine or open a conversation from a paired host to choose where prompts run.")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for target: CursorRunTargetOption) -> some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Button {
            onSelect(target)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: CursorMetrics.rowSpacing) {
                    Image(systemName: target.icon)
                        .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
                    Text(target.title)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)
                    Spacer()
                    if target.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(colors.primaryText)
                    } else {
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
                    .padding(.leading, CursorMetrics.rowHairlineLeadingInsetWithIcon)
            }
            // Same dead-tap-zone fix as CursorListRow/CursorThreadRow: without
            // this, a tap in the `Spacer()` gap between the title and the
            // trailing checkmark/chevron doesn't register as hitting the Button.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
