#if os(iOS)
import SwiftUI

/// Monospaced-friendly GFM table with horizontal scroll when wider than the viewport.
struct ChatMarkdownTableView: View {
    let table: ChatMarkdownTable
    var bodyFontSize: CGFloat = 13

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                        cellText(header, bold: true, alignment: alignment(at: index))
                    }
                }
                Divider()
                    .gridCellColumns(max(table.columnCount, 1))

                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, value in
                            cellText(value, bold: false, alignment: alignment(at: index))
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Table"))
    }

    private func alignment(at index: Int) -> ChatMarkdownTable.Alignment {
        guard index < table.alignments.count else { return .left }
        return table.alignments[index]
    }

    private func cellText(_ text: String, bold: Bool, alignment: ChatMarkdownTable.Alignment) -> some View {
        Text(text)
            .font(.system(size: bodyFontSize, weight: bold ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(.primary)
            .multilineTextAlignment(textAlignment(alignment))
            .frame(minWidth: 72, alignment: frameAlignment(alignment))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .textSelection(.enabled)
    }

    private func textAlignment(_ alignment: ChatMarkdownTable.Alignment) -> TextAlignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private func frameAlignment(_ alignment: ChatMarkdownTable.Alignment) -> Alignment {
        switch alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
#endif
