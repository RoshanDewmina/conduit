#if os(iOS)
import SwiftUI

/// Inline turn-diff card (Codex mobile): "N files changed +A −D", expandable file rows.
public struct TurnDiffCard: View {
    private static let visibleFileCap = 3

    let summary: RepoDiffSummary
    var onOpenReview: () -> Void

    @State private var isExpanded = false
    @State private var showAllFiles = false

    public init(summary: RepoDiffSummary, onOpenReview: @escaping () -> Void) {
        self.summary = summary
        self.onOpenReview = onOpenReview
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onOpenReview) {
                    HStack(spacing: 8) {
                        Text(summary.titleLabel)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(summary.countsLabel)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open review, \(summary.cardSummaryLabel)"))

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                        if !isExpanded { showAllFiles = false }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isExpanded ? "Collapse files" : "Expand files"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .accessibilityIdentifier("turn-diff-card-header")

            if isExpanded {
                Divider()
                ForEach(Array(visibleFiles.enumerated()), id: \.element.id) { index, file in
                    fileRow(file: file, index: index)
                    if index < visibleFiles.count - 1 || showsMoreExpander {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
                if showsMoreExpander {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showAllFiles = true
                        }
                    } label: {
                        Text("\(hiddenFileCount) more")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("turn-diff-more-files")
                    .accessibilityLabel(Text("Show \(hiddenFileCount) more files"))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("turn-diff-card")
    }

    private var visibleFiles: [RepoDiffFile] {
        if showAllFiles || summary.files.count <= Self.visibleFileCap {
            return summary.files
        }
        return Array(summary.files.prefix(Self.visibleFileCap))
    }

    private var hiddenFileCount: Int {
        max(0, summary.files.count - Self.visibleFileCap)
    }

    private var showsMoreExpander: Bool {
        !showAllFiles && hiddenFileCount > 0
    }

    private func fileRow(file: RepoDiffFile, index: Int) -> some View {
        Button {
            onOpenReview()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(file.path)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(file.countsLabel)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("turn-diff-file-\(index)")
    }
}
#endif
