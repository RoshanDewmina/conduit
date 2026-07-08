#if os(iOS)
import SwiftUI
import DesignSystem

/// One line of a unified diff: a context line present on both sides, an added
/// line (new-file only), or a removed line (old-file only).
public struct CursorDiffLine: Identifiable, Sendable {
    public enum Kind: Sendable {
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

#endif
