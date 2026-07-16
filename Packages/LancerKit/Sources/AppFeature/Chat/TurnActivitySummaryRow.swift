#if os(iOS)
import SwiftUI
import LancerCore

/// Compact secondary row after a completed turn: "Worked 59s · Edited 2 files · …".
/// When a proof receipt exists, a trailing overflow menu opens details on demand.
struct TurnActivitySummaryRow: View {
    let summary: TurnActivitySummary
    var receipt: ProofReceipt? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(summary.label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let receipt {
                ProofTurnMenu(receipt: receipt)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        guard receipt != nil else { return summary.label }
        return "\(summary.label). Proof available in menu."
    }
}
#endif
