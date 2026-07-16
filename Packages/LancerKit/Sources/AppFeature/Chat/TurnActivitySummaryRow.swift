#if os(iOS)
import SwiftUI

/// Compact secondary row after a completed turn: "Worked 59s · Edited 2 files · …".
struct TurnActivitySummaryRow: View {
    let summary: TurnActivitySummary

    var body: some View {
        Text(summary.label)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(Text(summary.label))
    }
}
#endif
