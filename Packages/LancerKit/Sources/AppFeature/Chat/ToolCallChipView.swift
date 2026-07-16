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
        HStack(spacing: 8) {
            statusOrTypeIcon
                .frame(width: 16, height: 16)

            Text(collapsedTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let diff = TurnTranscriptAssembler.aggregatedDiff(chips: chips) {
                diffLabels(added: diff.added, removed: diff.removed)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
    }

    /// Running/error states override the per-tool-type icon — those are more
    /// urgent than "which tool is this" once you already know something's
    /// wrong or in flight.
    @ViewBuilder
    private var statusOrTypeIcon: some View {
        if chips.contains(where: { $0.status == .running }) {
            ProgressView().controlSize(.mini)
        } else if chips.contains(where: { $0.isError || $0.status == .failed }) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.red)
        } else {
            Image(systemName: TurnTranscriptAssembler.groupedChipIcon(chips))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func expandedRow(_ chip: ToolChipItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: TurnTranscriptAssembler.chipIcon(name: chip.name))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
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

            if let input = chip.inputJSON, !input.isEmpty {
                detailSection(label: "Input", text: input)
            }
            if let result = chip.resultText, !result.isEmpty {
                detailSection(label: "Output", text: result)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
        )
    }

    private func detailSection(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)
            Text(TurnTranscriptAssembler.cappedDetail(text))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.quaternarySystemFill))
                )
        }
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

/// Renders a turn's ordered transcript items (prose between tool chips / thinking),
/// plus optional post-turn activity summary and inline todo checklist card.
struct TurnTranscriptItemsView: View {
    let items: [TurnTranscriptItem]
    var emptyFallback: String? = "(no reply text)"
    /// When non-nil (completed/failed turn), appends the compact activity row.
    var activitySummary: TurnActivitySummary? = nil
    /// When non-nil, proof opens from the activity row menu (never inline).
    var receipt: ProofReceipt? = nil

    var body: some View {
        let todoState = TurnTranscriptAssembler.latestTodoChecklist(from: items)
        let displayItems = Self.itemsExcludingTodoChips(items, when: todoState != nil)
        let grouped = TurnTranscriptAssembler.groupedForDisplay(displayItems)
        if grouped.isEmpty && todoState == nil && activitySummary == nil {
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
                if let todoState {
                    TodoChecklistCard(state: todoState)
                }
                if let activitySummary {
                    TurnActivitySummaryRow(summary: activitySummary, receipt: receipt)
                }
            }
        }
    }

    /// Drop TodoWrite chips from the fold list when we render `TodoChecklistCard`.
    private static func itemsExcludingTodoChips(
        _ items: [TurnTranscriptItem],
        when shouldFilter: Bool
    ) -> [TurnTranscriptItem] {
        guard shouldFilter else { return items }
        return items.filter { item in
            if case .toolChip(let chip) = item {
                return !TurnTranscriptAssembler.isTodoToolChip(chip)
            }
            return true
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
