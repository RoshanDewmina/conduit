#if os(iOS)
import SwiftUI

/// Inline turn-diff card (Codex mobile): "N files changed +A −D", expandable file rows.
public struct TurnDiffCard: View {
    let summary: RepoDiffSummary
    var onOpenReview: () -> Void

    @State private var isExpanded = false

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

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
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
                ForEach(Array(summary.files.enumerated()), id: \.element.id) { index, file in
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

                    if index < summary.files.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
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
}
#endif
