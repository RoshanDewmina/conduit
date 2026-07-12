#if os(iOS)
import SwiftUI

/// Floating session-total capsule above the composer: "N files +A −D". Hidden when zero.
public struct SessionDiffPill: View {
    let summary: RepoDiffSummary
    var onTap: () -> Void

    public init(summary: RepoDiffSummary, onTap: @escaping () -> Void) {
        self.summary = summary
        self.onTap = onTap
    }

    public var body: some View {
        if summary.hasChanges {
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(fileCountLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(summary.countsLabel)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("session-diff-pill")
            .accessibilityLabel(Text("\(fileCountLabel) \(summary.countsLabel)"))
        }
    }

    private var fileCountLabel: String {
        let n = summary.fileCount
        return n == 1 ? "1 file" : "\(n) files"
    }
}
#endif
