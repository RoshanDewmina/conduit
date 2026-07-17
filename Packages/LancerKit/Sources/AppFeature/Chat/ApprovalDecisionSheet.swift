#if os(iOS)
import SwiftUI
import LancerCore

/// CC-6: 1:1 restyle of the pending-approval surface to match the official
/// Claude Code app's bottom sheet (lock icon + "<Tool> wants to run:" +
/// monospace command box + stacked "Allow once" / "Always allow this
/// session" / "Deny" buttons), replacing the old inline
/// `LiveThreadView.approvalCard`.
///
/// This is a pure restyle — it does NOT touch the decision plumbing. Every
/// button calls `onDecide` with the exact same `Approval.Decision` cases the
/// old card used (`.approved`, `.approvedAlways`, `.rejected`), and
/// `LiveThreadView` wires `onDecide` straight to the existing
/// `RelayApprovalIngest.decide(_:decision:machineID:)` — the same call the
/// old Approve/Deny pills made. `.approvedAlways` is safe to surface here
/// because it is an existing wire-protocol case (see
/// `LancerCore/Approval.swift` `Decision.approvedAlways`, mapped to the
/// daemon's `"approveAlways"` string in `SSHTransport/DaemonChannel.swift`
/// `decisionWireValue(for:)` — no new decision type is invented.
struct ApprovalDecisionSheet: View {
    let approval: Approval
    let onDecide: (Approval.Decision) -> Void

    @Environment(\.dismiss) private var dismiss

    private var toolTitle: String {
        let name = approval.toolName?.isEmpty == false ? approval.toolName! : approval.kind.rawValue.capitalized
        return "\(name) wants to run:"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(toolTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                riskLabel
            }

            ScrollView {
                Text(approval.command ?? approval.patch ?? "(no detail)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(maxHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            VStack(spacing: 10) {
                Button {
                    onDecide(.approved)
                    dismiss()
                } label: {
                    Text("Allow once")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("cursor.approval.approve")

                Button {
                    onDecide(.approvedAlways)
                    dismiss()
                } label: {
                    Text("Always allow this session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("cursor.approval.approveAlways")

                Button(role: .destructive) {
                    onDecide(.rejected)
                    dismiss()
                } label: {
                    Text("Deny")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("cursor.approval.deny")
            }
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("approval-decision-sheet")
    }

    private var riskLabel: some View {
        let (text, color): (String, Color) = {
            switch approval.risk {
            case .low: return ("Low", .secondary)
            case .medium: return ("Medium", .secondary)
            case .high: return ("High", .orange)
            case .critical: return ("Critical", .red)
            }
        }()
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }
}
#endif
