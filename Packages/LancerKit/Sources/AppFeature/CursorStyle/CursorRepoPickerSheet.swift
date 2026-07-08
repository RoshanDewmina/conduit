#if os(iOS)
import SwiftUI
import DesignSystem

/// One selectable repo row: an org/repo pair, plus the checked-out branch
/// name for the currently active repo (used to render the trailing
/// branch-picker affordance on the "Active" row only).
public struct CursorRepoPickerOption: Identifiable, Sendable {
    public let id: String
    public let orgName: String
    public let repoName: String
    public let branchName: String?

    public init(id: String, orgName: String, repoName: String, branchName: String? = nil) {
        self.id = id
        self.orgName = orgName
        self.repoName = repoName
        self.branchName = branchName
    }
}

/// Cursor-style "Repo" picker sheet: a search field below the title, an
/// "Active" section showing the currently checked-out repo (with a trailing
/// branch name + up/down chevron hinting at a branch picker), a "Recents"
/// section, and a "More" section listing other known repos. Each row splits
/// its title into a muted org segment and a bold repo-name segment.
public struct CursorRepoPickerSheet: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @State private var searchText: String = ""

    private let active: CursorRepoPickerOption
    private let recents: [CursorRepoPickerOption]
    private let more: [CursorRepoPickerOption]
    private let onClose: () -> Void
    private let onSelect: (CursorRepoPickerOption) -> Void

    public init(
        active: CursorRepoPickerOption? = nil,
        recents: [CursorRepoPickerOption]? = nil,
        more: [CursorRepoPickerOption]? = nil,
        onClose: @escaping () -> Void = {},
        onSelect: @escaping (CursorRepoPickerOption) -> Void = { _ in }
    ) {
        self.active = active ?? CursorRepoPickerOption(
            id: "active-home",
            orgName: "Local",
            repoName: "Home",
            branchName: nil
        )
        self.recents = recents ?? []
        self.more = more ?? []
        self.onClose = onClose
        self.onSelect = onSelect
    }

    private var filteredRecents: [CursorRepoPickerOption] {
        guard !searchText.isEmpty else { return recents }
        return recents.filter { $0.repoName.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredMore: [CursorRepoPickerOption] {
        guard !searchText.isEmpty else { return more }
        return more.filter { $0.repoName.localizedCaseInsensitiveContains(searchText) }
    }

    public var body: some View {
        CursorBottomSheetContainer(
            title: "Repo",
            leadingButton: (systemImageName: "xmark", action: onClose)
        ) {
            VStack(spacing: 0) {
                CursorSearchField(text: $searchText)
                    .padding(.bottom, CursorMetrics.sectionHeaderTopPadding)

                CursorSectionHeader("Active")
                CursorRepoPickerRow(option: active, showBranch: true) {
                    onSelect(active)
                }

                if !filteredRecents.isEmpty {
                    CursorSectionHeader("Recents")
                    ForEach(filteredRecents) { option in
                        CursorRepoPickerRow(option: option, showBranch: false) {
                            onSelect(option)
                        }
                    }
                }

                if !filteredMore.isEmpty {
                    CursorSectionHeader("More")
                    ForEach(filteredMore) { option in
                        CursorRepoPickerRow(option: option, showBranch: false) {
                            onSelect(option)
                        }
                    }
                }
            }
            .padding(.bottom, CursorMetrics.sheetContentBottomPadding)
        }
    }
}

/// A single repo row: leading folder icon, org/repo split-styled title (muted
/// org segment + bold repo-name segment), and — for the active row only — a
/// trailing muted branch name with a chevron-up/down suggesting a branch
/// picker. Follows `CursorListRow`'s padding/hairline-divider conventions.
private struct CursorRepoPickerRow: View {
    @Environment(\.cursorScheme) private var cursorScheme

    let option: CursorRepoPickerOption
    let showBranch: Bool
    let action: () -> Void

    var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        return Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: CursorMetrics.rowSpacing) {
                    Image(systemName: "folder")
                        .font(.system(size: CursorMetrics.rowIconSize - 6, weight: .regular))
                        .foregroundColor(colors.secondaryText)
                        .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)

                    HStack(spacing: 0) {
                        Text("\(option.orgName)/")
                            .font(CursorType.rowTitle)
                            .foregroundColor(colors.secondaryText)
                        Text(option.repoName)
                            .font(CursorType.rowTitle.weight(.semibold))
                            .foregroundColor(colors.primaryText)
                    }
                    .lineLimit(1)

                    Spacer()

                    if showBranch, let branchName = option.branchName {
                        Text(branchName)
                            .font(CursorType.rowSecondary)
                            .foregroundColor(colors.secondaryText)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
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
            // this, a tap in the `Spacer()` gap between the repo name and the
            // trailing branch chevron doesn't register as hitting the Button.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
