#if os(iOS)
import SwiftUI
import LancerCore
import PersistenceKit

/// Workspaces home Needs-You affordance (Away Mode P1.5).
/// Hidden entirely when count is 0. Tap opens the relevant live thread via
/// the caller's existing presentation — no new Settings cathedral.
struct PendingApprovalsBanner: View {
    @Environment(RelayApprovalIngest.self) private var approvalIngest
    @Environment(RelayFleetStore.self) private var relayFleetStore

    /// Invoked with the machine + approval to open. Caller focuses the bridge
    /// machine and presents `LiveThreadView` through existing seams.
    var onOpen: (RelayMachineID, Approval) -> Void

    private var pending: [(machineID: RelayMachineID, approval: Approval)] {
        approvalIngest.allPendingApprovals
    }

    var body: some View {
        Group {
            if !pending.isEmpty {
                Button {
                    guard let first = pending.first else { return }
                    onOpen(first.machineID, first.approval)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workspaces-pending-approvals-banner")
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text("Opens the live thread for the most recent pending approval"))

                Divider()
                    .padding(.leading, 58)
            }
        }
        #if DEBUG
        .task {
            await approvalIngest.hydratePendingForUITestIfRequested(
                preferredMachineID: relayFleetStore.firstConnectedMachine?.id
            )
        }
        #endif
    }

    private var title: String {
        let count = pending.count
        return count == 1 ? "1 needs you" : "\(count) need you"
    }

    private var subtitle: String {
        guard let first = pending.first else { return "" }
        let detail = first.approval.command
            ?? first.approval.patch
            ?? first.approval.question
            ?? first.approval.kind.rawValue
        let risk = first.approval.risk.displayLabel
        if detail.isEmpty {
            return "Approval · \(risk) · Tap to review"
        }
        return "Approval · \(detail) · Tap to review"
    }
}

private extension Approval.Risk {
    var displayLabel: String {
        switch self {
        case .low: return "low risk"
        case .medium: return "medium risk"
        case .high: return "high risk"
        case .critical: return "critical risk"
        }
    }
}
#endif
