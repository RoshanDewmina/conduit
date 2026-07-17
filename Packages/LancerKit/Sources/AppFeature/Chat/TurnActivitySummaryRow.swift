#if os(iOS)
import SwiftUI
import LancerCore

/// Compact secondary row after a completed turn: "Worked 59s · Edited 2 files · …".
/// Tappable — expands to per-tool detail (same chip expansion pattern). When a proof
/// receipt exists, a trailing overflow menu opens details on demand.
struct TurnActivitySummaryRow: View {
    let summary: TurnActivitySummary
    var chips: [ToolChipItem] = []
    var receipt: ProofReceipt? = nil

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(summary.label)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityHint(Text(isExpanded ? "Collapse activity details" : "Expand activity details"))

                if let receipt {
                    ProofTurnMenu(receipt: receipt)
                }
            }

            if isExpanded {
                if chips.isEmpty {
                    Text(summary.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(chips) { chip in
                        HStack(spacing: 6) {
                            Image(systemName: TurnTranscriptAssembler.chipIcon(name: chip.name))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(TurnTranscriptAssembler.chipTitle(name: chip.name, inputJSON: chip.inputJSON))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var accessibilityLabel: String {
        guard receipt != nil else { return summary.label }
        return "\(summary.label). Proof available in menu."
    }
}
#endif
