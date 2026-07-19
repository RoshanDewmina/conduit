#if os(iOS)
import SwiftUI

/// Red/green sheet for a single Edit / Write / MultiEdit tool chip.
/// Renders `old_string` / `new_string` already present in the chip's input JSON —
/// no git RPC required (git-backed review remains `ReviewSheetView`).
struct EditToolDiffSheet: View {
    let presentation: EditToolDiffPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    ForEach(presentation.segments) { segment in
                        segmentBlock(segment)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(presentation.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("edit-tool-diff-sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.fileName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            if let path = presentation.filePath, path != presentation.fileName {
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(presentation.countsLabel)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func segmentBlock(_ segment: EditToolDiffPresentation.Segment) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = segment.title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            if !segment.deletions.isEmpty {
                ForEach(segment.deletions) { row in
                    DiffLineRow(row: row)
                }
            }
            if !segment.additions.isEmpty {
                ForEach(segment.additions) { row in
                    DiffLineRow(row: row)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
#endif
