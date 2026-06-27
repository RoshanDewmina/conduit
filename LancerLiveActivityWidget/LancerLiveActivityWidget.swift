// Tier 1.5.1 — iOS Widget Extension that renders the Lancer session
// Live Activity on the lock screen and Dynamic Island.
//
// Simplified design: clean minimal UI with agent name, status, progress,
// cost, and approve/reject buttons for pending approvals.

import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import SessionFeature
import NotificationsKit

@main
struct LancerLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            LancerSessionLiveActivity()
        }
    }
}

@available(iOS 16.2, *)
struct LancerSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LancerSessionAttributes.self) { context in
            // Lock-screen + banner appearance
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Dynamic Island Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Circle()
                        .fill(statusColor(for: context.state))
                        .frame(width: 8, height: 8)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.pendingApprovals > 0 {
                        Label("\(context.state.pendingApprovals)", systemImage: "bell.badge.fill")
                            .foregroundStyle(.orange)
                    } else if let cost = context.state.cost, cost > 0 {
                        Text(formatCost(cost))
                            .font(.caption.monospaced())
                            .foregroundStyle(costColor(for: context.state))
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .center, spacing: 2) {
                        Text(context.state.agentName ?? context.attributes.hostName)
                            .font(.headline)
                            .lineLimit(1)

                        Text(statusLabel(for: context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let approvalID = context.state.pendingApprovalID, !approvalID.isEmpty {
                        approvalButtons(
                            approvalID: approvalID,
                            hostID: context.attributes.hostID
                        )
                    } else {
                        HStack(spacing: 8) {
                            if context.state.isStreaming {
                                Image(systemName: "waveform")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }

                            if let cost = context.state.cost, cost > 0 {
                                Text(formatCost(cost))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(costColor(for: context.state))
                            }
                        }
                    }
                }
            } compactLeading: {
                compactLeadingView(context: context)
            } compactTrailing: {
                compactTrailingView(context: context)
            } minimal: {
                minimalView(context: context)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<LancerSessionAttributes>) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor(for: context.state))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                // Agent name or host name
                Text(context.state.agentName ?? context.attributes.hostName)
                    .font(.headline)
                    .lineLimit(1)

                // Status + cost
                HStack(spacing: 6) {
                    Text(statusLabel(for: context.state))
                        .foregroundStyle(.secondary)

                    if let cost = context.state.cost, cost > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(formatCost(cost))
                            .foregroundStyle(costColor(for: context.state))
                    }
                }
                .font(.caption.monospaced())
            }

            Spacer()

            // Pending approval badge
            if context.state.pendingApprovals > 0 {
                Label("\(context.state.pendingApprovals)", systemImage: "bell.badge.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    }

    // MARK: - Dynamic Island Compact

    @ViewBuilder
    private func compactLeadingView(context: ActivityViewContext<LancerSessionAttributes>) -> some View {
        Circle()
            .fill(statusColor(for: context.state))
            .frame(width: 6, height: 6)
    }

    @ViewBuilder
    private func compactTrailingView(context: ActivityViewContext<LancerSessionAttributes>) -> some View {
        if context.state.pendingApprovals > 0 {
            Text("\(context.state.pendingApprovals)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        } else {
            Text(shortStatus(for: context.state))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Dynamic Island Minimal

    @ViewBuilder
    private func minimalView(context: ActivityViewContext<LancerSessionAttributes>) -> some View {
        Circle()
            .fill(statusColor(for: context.state))
            .frame(width: 5, height: 5)
    }

    // MARK: - Approval Buttons

    @ViewBuilder
    private func approvalButtons(approvalID: String, hostID: String) -> some View {
        HStack(spacing: 10) {
            Button(
                intent: ApprovalActionIntent(
                    approvalID: approvalID,
                    hostID: hostID,
                    decision: .reject
                )
            ) {
                Label("Reject", systemImage: "xmark")
            }
            .buttonStyle(.bordered)

            Button(
                intent: ApprovalActionIntent(
                    approvalID: approvalID,
                    hostID: hostID,
                    decision: .approve
                )
            ) {
                Label("Approve", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.caption)
    }

    // MARK: - Status Colors (ok=green, warn=amber, danger=red)

    private func statusColor(for state: LancerSessionAttributes.ContentState) -> Color {
        let p = LiveActivityPresentation.resolve(state, budget: nil)
        switch p.primary {
        case .needsYou:
            return Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1) // amber (warn)
        case .decisionLanded(let approved):
            return approved
                ? Color(.sRGB, red: 0.173, green: 0.608, blue: 0.349, opacity: 1)  // green (approved)
                : Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1)  // red (rejected)
        case .running:
            return Color(.sRGB, red: 0.318, green: 0.573, blue: 0.929, opacity: 1) // blue (streaming)
        case .idle:
            switch state.status {
            case "reconnecting": return Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1)
            case "error":        return Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1)
            case "suspended":    return Color(.sRGB, red: 0.373, green: 0.357, blue: 0.329, opacity: 1)
            default:             return Color(.sRGB, red: 0.173, green: 0.608, blue: 0.349, opacity: 1)
            }
        }
    }

    private func statusLabel(for state: LancerSessionAttributes.ContentState) -> String {
        let p = LiveActivityPresentation.resolve(state, budget: nil)
        switch p.primary {
        case .needsYou(let count): return count == 1 ? "1 pending" : "\(count) pending"
        case .decisionLanded(let approved): return approved ? "Approved ✓" : "Rejected ✓"
        case .running: return "streaming"
        case .idle:
            switch state.status {
            case "connected":    return "connected"
            case "reconnecting": return "reconnecting"
            case "error":        return "error"
            case "suspended":    return "suspended"
            default:             return state.status
            }
        }
    }

    private func shortStatus(for state: LancerSessionAttributes.ContentState) -> String {
        let p = LiveActivityPresentation.resolve(state, budget: nil)
        switch p.primary {
        case .needsYou(let count): return "\(count)"
        case .decisionLanded:      return "✓"
        case .running:             return "..."
        case .idle:                return String(state.status.prefix(3)).lowercased() + "..."
        }
    }

    private func costColor(for state: LancerSessionAttributes.ContentState) -> Color {
        switch LiveActivityPresentation.resolve(state, budget: nil).costLevel {
        case .over:    return Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1) // red
        case .warning: return Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1) // amber
        default:       return .secondary
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }
}
