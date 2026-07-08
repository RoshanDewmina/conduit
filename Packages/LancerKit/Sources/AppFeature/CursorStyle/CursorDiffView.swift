#if os(iOS)
import SwiftUI
import DesignSystem

/// One line of a unified diff: a context line present on both sides, an added
/// line (new-file only), or a removed line (old-file only).
public struct CursorDiffLine: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case unchanged
        case added
        case removed
    }

    public let id = UUID()
    public let oldNumber: Int?
    public let newNumber: Int?
    public let text: String
    public let kind: Kind

    public init(oldNumber: Int?, newNumber: Int?, text: String, kind: Kind) {
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.text = text
        self.kind = kind
    }
}

/// Unified-diff content view for one file (IMG_2365/2367): a collapsed
/// "N unmodified lines" context bar followed by line-numbered, monospace diff
/// rows with a colored left-edge bar and a tinted row background for
/// added/removed lines. No syntax highlighting — plain colored text only.
public struct CursorDiffView: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let collapsedContextLineCount: Int
    private let lines: [CursorDiffLine]

    public init(collapsedContextLineCount: Int, lines: [CursorDiffLine]) {
        self.collapsedContextLineCount = collapsedContextLineCount
        self.lines = lines
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(alignment: .leading, spacing: 0) {
            contextBar(colors: colors)
            ForEach(lines) { line in
                diffRow(line, colors: colors)
            }
        }
    }

    private func contextBar(colors: CursorColors) -> some View {
        Text("\(collapsedContextLineCount) unmodified lines")
            .font(CursorType.diffLineNumber)
            .foregroundColor(colors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CursorMetrics.diffLineHorizontalPadding + 4)
            .padding(.vertical, CursorMetrics.diffContextBarVerticalPadding)
            .background(colors.composerBackground)
            .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.diffContextBarCornerRadius))
            .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
            .padding(.vertical, 8)
    }

    private func diffRow(_ line: CursorDiffLine, colors: CursorColors) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(edgeColor(line.kind, colors: colors))
                .frame(width: CursorMetrics.diffLeftEdgeBarWidth)

            Text(line.oldNumber.map(String.init) ?? "")
                .font(CursorType.diffLineNumber)
                .foregroundColor(colors.mutedText)
                .frame(width: CursorMetrics.diffLineNumberWidth, alignment: .trailing)
                .padding(.leading, CursorMetrics.diffLineHorizontalPadding)

            Text(line.newNumber.map(String.init) ?? "")
                .font(CursorType.diffLineNumber)
                .foregroundColor(colors.mutedText)
                .frame(width: CursorMetrics.diffLineNumberWidth, alignment: .trailing)
                .padding(.trailing, CursorMetrics.diffLineHorizontalPadding)

            Text(line.text.isEmpty ? " " : line.text)
                .font(CursorType.diffCode)
                .foregroundColor(colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, CursorMetrics.diffLineHorizontalPadding)
        }
        .padding(.vertical, CursorMetrics.diffLineVerticalPadding)
        .background(rowBackground(line.kind, colors: colors))
    }

    private func edgeColor(_ kind: CursorDiffLine.Kind, colors: CursorColors) -> Color {
        switch kind {
        case .unchanged: return .clear
        case .added: return colors.successGreen
        case .removed: return colors.dangerRed
        }
    }

    private func rowBackground(_ kind: CursorDiffLine.Kind, colors: CursorColors) -> Color {
        switch kind {
        case .unchanged: return .clear
        case .added: return colors.diffAddedBackground
        case .removed: return colors.diffRemovedBackground
        }
    }
}

/// Full file-viewer screen (row 12, IMG_2427): a pinned header row (back
/// chevron, filename, extension badge, diff counts) above a scrollable
/// `CursorDiffView`, on the very-dark green-tinted `codeBlockBackground` in
/// dark mode per the reference. Pushed from `CursorPRDetailView`'s file list.
public struct CursorFileDiffScreen: View {
    @Environment(\.cursorScheme) private var cursorScheme

    private let fileName: String
    private let fullPath: String
    private let additions: Int
    private let deletions: Int
    private let lines: [CursorDiffLine]
    private let onBack: () -> Void

    public init(
        fileName: String,
        fullPath: String,
        additions: Int,
        deletions: Int,
        lines: [CursorDiffLine],
        onBack: @escaping () -> Void = {}
    ) {
        self.fileName = fileName
        self.fullPath = fullPath
        self.additions = additions
        self.deletions = deletions
        self.lines = lines
        self.onBack = onBack
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        VStack(spacing: 0) {
            fileHeader(colors: colors)
            Rectangle().fill(colors.hairline).frame(height: CursorMetrics.rowHairlineHeight)
            ScrollView([.vertical, .horizontal]) {
                CursorDiffView(collapsedContextLineCount: 0, lines: lines)
            }
            .background(colors.codeBlockBackground)
        }
        .background(colors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .accessibilityIdentifier("file-diff-screen")
    }

    private func fileHeader(colors: CursorColors) -> some View {
        HStack(spacing: CursorMetrics.rowSpacing) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colors.primaryText)
            }
            .buttonStyle(.plain)

            fileExtensionBadge(colors: colors)

            Text(fileName)
                .font(CursorType.rowTitle)
                .foregroundColor(colors.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)
            CursorDiffStatText(added: additions, removed: deletions)
        }
        .padding(.horizontal, CursorMetrics.headerHorizontalPadding)
        .padding(.vertical, 12)
        .background(colors.sheetBackground)
    }

    private func fileExtensionBadge(colors: CursorColors) -> some View {
        let ext = (fullPath as NSString).pathExtension.uppercased()
        let label = ext.isEmpty ? "•" : String(ext.prefix(2))
        return Text(label)
            .font(CursorType.diffLineNumber)
            .foregroundColor(colors.mutedText)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(colors.hairline, lineWidth: 1)
            )
    }
}

#endif
