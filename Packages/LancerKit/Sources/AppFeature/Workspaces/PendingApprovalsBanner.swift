#if os(iOS)
import SwiftUI
import LancerCore
import PersistenceKit

/// Workspaces home affordance: "you have N pending approvals."
/// Hidden entirely when count is 0. Tap opens the relevant live thread via
/// the caller's existing `liveThreadPresentation` push — no new nav stack.
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
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 28, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
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
        return count == 1 ? "1 pending approval" : "\(count) pending approvals"
    }

    private var subtitle: String {
        guard let first = pending.first else { return "" }
        let detail = first.approval.command
            ?? first.approval.patch
            ?? first.approval.question
            ?? first.approval.kind.rawValue
        return detail
    }
}
#endif
