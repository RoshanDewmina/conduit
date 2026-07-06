#if os(iOS)
import SwiftUI

/// Status line under a thread row title: either a green "Checks Passed" with a
/// colored diffstat, or a plain gray "No Changes".
public enum CursorThreadStatus: Sendable {
    case checksPassed(diffAdded: Int, diffRemoved: Int)
    case noChanges
}

public struct CursorThreadRowModel: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let repoName: String
    public let isActive: Bool
    public let statusLine: CursorThreadStatus

    public init(
        id: UUID = UUID(),
        title: String,
        repoName: String,
        isActive: Bool,
        statusLine: CursorThreadStatus
    ) {
        self.id = id
        self.title = title
        self.repoName = repoName
        self.isActive = isActive
        self.statusLine = statusLine
    }
}

/// One thread row: leading status dot, title, secondary status line, optional
/// repo-name pill (used on Home, which spans repos), hairline divider.
public struct CursorThreadRow: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let model: CursorThreadRowModel
    private let showRepoTag: Bool

    public init(model: CursorThreadRowModel, showRepoTag: Bool = false) {
        self.model = model
        self.showRepoTag = showRepoTag
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: CursorMetrics.rowSpacing) {
                Circle()
                    .fill(model.isActive ? colors.statusDotActive : colors.statusDotIdle)
                    .frame(width: CursorMetrics.threadRowStatusDotSize, height: CursorMetrics.threadRowStatusDotSize)
                    .padding(.top, CursorMetrics.threadRowStatusDotTopPadding)

                VStack(alignment: .leading, spacing: CursorMetrics.threadRowContentSpacing) {
                    Text(model.title)
                        .font(CursorType.rowTitle)
                        .foregroundColor(colors.primaryText)

                    HStack(spacing: CursorMetrics.threadRowStatusSpacing) {
                        statusLineView(colors: colors)
                        if showRepoTag {
                            repoTag(colors: colors)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, CursorMetrics.rowVerticalPadding)

            Rectangle()
                .fill(colors.hairline)
                .frame(height: CursorMetrics.rowHairlineHeight)
                .padding(.leading, CursorMetrics.threadRowHairlineLeadingInset)
        }
    }

    @ViewBuilder
    private func statusLineView(colors: CursorColors) -> some View {
        switch model.statusLine {
        case .checksPassed(let diffAdded, let diffRemoved):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colors.successGreen)
                Text("Checks Passed")
                    .font(CursorType.rowSecondary)
                    .foregroundColor(colors.secondaryText)
                CursorDiffStatText(added: diffAdded, removed: diffRemoved, font: CursorType.rowSecondary)
            }
        case .noChanges:
            Text("No Changes")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.mutedText)
        }
    }

    private func repoTag(colors: CursorColors) -> some View {
        Text(model.repoName)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(colors.secondaryText)
            .padding(.horizontal, CursorMetrics.repoTagHorizontalPadding)
            .padding(.vertical, CursorMetrics.repoTagVerticalPadding)
            .background(
                Capsule().fill(colors.composerBackground)
            )
    }
}
#endif
