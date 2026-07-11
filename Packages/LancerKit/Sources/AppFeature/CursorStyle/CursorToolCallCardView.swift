#if os(iOS)
import SwiftUI

/// Foldable tool-call cards for the CursorStyle work thread.
/// Presentation state comes from `CursorToolCallGroup` (pure); this view only renders.
struct CursorToolCallGroupView: View {
    let group: CursorToolCallGroup
    @State private var isExpanded: Bool

    init(group: CursorToolCallGroup) {
        self.group = group
        _isExpanded = State(initialValue: group.shouldAutoExpand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(group.cards.count)×")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(group.summaryLine)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("work-thread-tool-call-group")

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.cards) { card in
                        CursorToolCallCardView(card: card)
                    }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 2)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct CursorToolCallCardView: View {
    let card: CursorToolCallCard
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(card.name)
                        .font(.caption.monospaced().weight(.semibold))
                    statusBadge
                    if !card.inputSummary.isEmpty {
                        Text(card.inputSummary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("work-thread-tool-call-card-\(card.id)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !card.inputJSON.isEmpty {
                        Text(card.inputJSON)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let result = card.resultPreview, !result.isEmpty {
                        Text(result)
                            .font(.caption2.monospaced())
                            .foregroundStyle(card.state == .error ? .red : .primary)
                            .textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch card.state {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel("Running")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .accessibilityLabel("Completed")
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .accessibilityLabel("Error")
        }
    }
}
#endif
