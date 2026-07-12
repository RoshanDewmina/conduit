#if os(iOS)
import SwiftUI
import LancerCore

/// Compact one-line tool chip (Claude-mobile style). Collapsed by default;
/// consecutive chips group under one summary row. Title/grouping rules from
/// `TurnTranscriptAssembler` (Orca tool-fold/summary patterns, MIT — stablyai/orca).
/// Workspaces-shell chrome (system fills), not the retired DesignSystem tokens.
struct ToolCallChipView: View {
    let chips: [ToolChipItem]

    @State private var isExpanded = false

    init(chips: [ToolChipItem]) {
        self.chips = chips
    }

    init(chip: ToolChipItem) {
        self.chips = [chip]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                collapsedRow
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accessibilityCollapsedLabel))
            .accessibilityHint(Text(isExpanded ? "Collapse tool details" : "Expand tool details"))

            if isExpanded {
                ForEach(chips) { chip in
                    expandedRow(chip)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedRow: some View {
        HStack(spacing: 6) {
            if chips.contains(where: { $0.status == .running }) {
                ProgressView()
                    .controlSize(.mini)
            } else if chips.contains(where: { $0.isError || $0.status == .failed }) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Text(collapsedTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let diff = TurnTranscriptAssembler.aggregatedDiff(chips: chips) {
                diffLabels(added: diff.added, removed: diff.removed)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func expandedRow(_ chip: ToolChipItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(TurnTranscriptAssembler.chipTitle(name: chip.name, inputJSON: chip.inputJSON))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let added = chip.added, let removed = chip.removed {
                    diffLabels(added: added, removed: removed)
                } else if let added = chip.added {
                    diffLabels(added: added, removed: chip.removed ?? 0)
                } else if let removed = chip.removed {
                    diffLabels(added: chip.added ?? 0, removed: removed)
                }
                Spacer(minLength: 0)
                statusBadge(chip)
            }

            if let detail = detailText(for: chip), !detail.isEmpty {
                Text(TurnTranscriptAssembler.cappedDetail(detail))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
            }
        }
        .padding(.leading, 2)
    }

    private var collapsedTitle: String {
        TurnTranscriptAssembler.groupedChipTitle(chips)
    }

    private var accessibilityCollapsedLabel: String {
        var parts = [collapsedTitle]
        if let diff = TurnTranscriptAssembler.aggregatedDiff(chips: chips) {
            parts.append("+\(diff.added) −\(diff.removed)")
        }
        return parts.joined(separator: " ")
    }

    private func detailText(for chip: ToolChipItem) -> String? {
        if let result = chip.resultText, !result.isEmpty {
            return result
        }
        return chip.inputJSON
    }

    @ViewBuilder
    private func diffLabels(added: Int, removed: Int) -> some View {
        let format = DiffCountFormat(added: added, removed: removed)
        HStack(spacing: 4) {
            Text(format.addedLabel)
                .foregroundStyle(Color.green)
            Text(format.removedLabel.replacingOccurrences(of: "-", with: "−"))
                .foregroundStyle(Color.red)
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
    }

    @ViewBuilder
    private func statusBadge(_ chip: ToolChipItem) -> some View {
        switch chip.status {
        case .running:
            Text("Running")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        case .failed:
            Text("Error")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
        case .done:
            EmptyView()
        }
    }
}

/// Renders a turn's ordered transcript items (prose between tool chips / thinking).
struct TurnTranscriptItemsView: View {
    let items: [TurnTranscriptItem]
    var emptyFallback: String? = "(no reply text)"

    var body: some View {
        let grouped = TurnTranscriptAssembler.groupedForDisplay(items)
        if grouped.isEmpty {
            if let emptyFallback {
                ChatMarkdownBody(markdown: emptyFallback)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(grouped) { item in
                    switch item {
                    case .prose(let prose):
                        ChatMarkdownBody(markdown: prose.text)
                    case .thinking(let thinking):
                        ThinkingRow(text: thinking.text)
                    case .toolChips(let chips):
                        ToolCallChipView(chips: chips)
                    }
                }
            }
        }
    }
}

/// Floating circular jump-to-latest control (Orca near-bottom policy, MIT).
struct ChatScrollToBottomButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Scroll to bottom"))
    }
}
#endif
