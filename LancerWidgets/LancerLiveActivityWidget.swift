import ActivityKit
import WidgetKit
import SwiftUI
import SessionFeature

// Renders `LancerSessionAttributes` / its `ContentState`
// (Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift:47) —
// the type this extension exists to satisfy per that file's header comment.
// Build UI for the fields that actually exist on ContentState: status,
// pendingApprovals, agentName, pendingApprovalID, pendingApprovalRisk,
// isStreaming, cost, lastDecision, lastUpdate. Nothing invented beyond those.

private enum LiveActivityPalette {
    static let background = Color.black
    static let accent = Color.orange
    static let secondaryText = Color(white: 0.65)
    static let primaryText = Color.white
}

@available(iOS 16.2, *)
struct LancerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LancerSessionAttributes.self) { context in
            LancerLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(LiveActivityPalette.background)
                .activitySystemActionForegroundColor(LiveActivityPalette.primaryText)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        statusGlyph(context.state, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.agentName ?? "Lancer")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(LiveActivityPalette.primaryText)
                            Text(context.attributes.hostName)
                                .font(.caption2)
                                .foregroundStyle(LiveActivityPalette.secondaryText)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(statusLabel(context.state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(context.state.pendingApprovalID != nil ? LiveActivityPalette.accent : LiveActivityPalette.secondaryText)
                        if let cost = context.state.cost {
                            Text(formattedCost(cost))
                                .font(.caption2)
                                .foregroundStyle(LiveActivityPalette.secondaryText)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.pendingApprovalID != nil {
                        ApprovalActionRow(attributes: context.attributes, state: context.state)
                    } else if let decision = context.state.lastDecision {
                        Text(decisionLabel(decision))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(LiveActivityPalette.secondaryText)
                    }
                }
            } compactLeading: {
                statusGlyph(context.state, size: 14)
            } compactTrailing: {
                if context.state.pendingApprovalID != nil {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(LiveActivityPalette.accent)
                } else {
                    Text(context.state.agentName?.prefix(3).uppercased() ?? "···")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(LiveActivityPalette.primaryText)
                }
            } minimal: {
                statusGlyph(context.state, size: 12)
            }
            .widgetURL(URL(string: "lancer://open"))
            .keylineTint(context.state.pendingApprovalID != nil ? LiveActivityPalette.accent : LiveActivityPalette.secondaryText)
        }
    }
}

@available(iOS 16.2, *)
private func statusGlyph(_ state: LancerSessionAttributes.ContentState, size: CGFloat) -> some View {
    Group {
        if state.pendingApprovalID != nil {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(LiveActivityPalette.accent)
        } else if state.isStreaming {
            Image(systemName: "bolt.fill")
                .foregroundStyle(Color.blue)
        } else if state.status == "connected" {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
        } else {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(LiveActivityPalette.secondaryText)
        }
    }
    .font(.system(size: size, weight: .semibold))
}

@available(iOS 16.2, *)
private func statusLabel(_ state: LancerSessionAttributes.ContentState) -> String {
    if state.pendingApprovalID != nil { return "Needs approval" }
    switch state.status {
    case "connected": return state.isStreaming ? "Running" : "Connected"
    case "reconnecting": return "Reconnecting…"
    case "suspended": return "Suspended"
    default: return state.status.capitalized
    }
}

private func decisionLabel(_ decision: String) -> String {
    switch decision {
    case "approved": return "✓ Approved"
    case "rejected": return "✕ Denied"
    default: return decision.capitalized
    }
}

private func formattedCost(_ cost: Double) -> String {
    String(format: "$%.2f", cost)
}

private func riskLabel(_ risk: Int?) -> String {
    switch risk {
    case 0: return "Low risk"
    case 1: return "Medium risk"
    case 2: return "High risk"
    case 3: return "Critical risk"
    default: return "Review needed"
    }
}

/// Lock Screen banner. Two visual modes: steady-state run status, and an
/// urgent (orange, bordered) approval-pending mode with inline Deny/Approve
/// buttons.
@available(iOS 16.2, *)
struct LancerLiveActivityLockScreenView: View {
    let context: ActivityViewContext<LancerSessionAttributes>

    private var state: LancerSessionAttributes.ContentState { context.state }
    private var isPendingApproval: Bool { state.pendingApprovalID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isPendingApproval {
                approvalBody
            } else {
                runBody
            }
        }
        .padding(16)
        .widgetURL(URL(string: "lancer://open"))
    }

    private var header: some View {
        HStack {
            statusGlyph(state, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.agentName ?? "Lancer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LiveActivityPalette.primaryText)
                Text(context.attributes.hostName)
                    .font(.caption2)
                    .foregroundStyle(LiveActivityPalette.secondaryText)
            }
            Spacer()
            Text(statusLabel(state))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isPendingApproval ? LiveActivityPalette.accent : LiveActivityPalette.secondaryText)
        }
    }

    private var runBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let cost = state.cost {
                Text(formattedCost(cost) + " so far")
                    .font(.caption)
                    .foregroundStyle(LiveActivityPalette.secondaryText)
            }
            if let decision = state.lastDecision {
                Text(decisionLabel(decision))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LiveActivityPalette.secondaryText)
            }
            Text("Updated \(state.lastUpdate.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(LiveActivityPalette.secondaryText.opacity(0.7))
        }
    }

    private var approvalBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(riskLabel(state.pendingApprovalRisk))
                .font(.caption.weight(.semibold))
                .foregroundStyle(LiveActivityPalette.accent)
            ApprovalActionRow(attributes: context.attributes, state: state)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LiveActivityPalette.accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LiveActivityPalette.accent.opacity(0.5), lineWidth: 1)
        )
    }
}

/// Approve / Deny buttons shared by the Dynamic Island expanded region and
/// the Lock Screen banner. Both route through `ApprovalActionIntent`
/// (SessionFeature/ApprovalActionIntent.swift) — the only intent the widget
/// extension can reach for this: `DenyApprovalIntent` lives in the `Lancer`
/// app target (not a linked package product, per its own header comment on
/// why AppIntents that register Siri phrases must stay app-target-only), so
/// it isn't compiled into this extension. `ApprovalActionIntent` already
/// covers both decisions with the *exact* approval this widget is showing
/// (not "most recent pending", which is what `DenyApprovalIntent` without an
/// explicit `ApprovalEntity` would resolve to) and its
/// `authenticationPolicy` is `.requiresAuthentication` for both approve and
/// reject (see `ApprovalActionIntentPolicy`), so Deny stays exactly as safe.
/// Never register this intent's `.approve` case in `LancerAppShortcuts` — it
/// already deliberately excludes `ApprovalActionIntent` from Siri.
@available(iOS 16.2, *)
private struct ApprovalActionRow: View {
    let attributes: LancerSessionAttributes
    let state: LancerSessionAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: denyIntent) {
                Label("Deny", systemImage: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(Color(white: 0.25))

            Button(intent: approveIntent) {
                Label("Approve", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(LiveActivityPalette.accent)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var approvalID: String { state.pendingApprovalID ?? "" }

    private var riskParameter: ApprovalIntentRisk? {
        state.pendingApprovalRisk.flatMap(ApprovalIntentRisk.init(rawValue:))
    }

    private var denyIntent: ApprovalActionIntent {
        ApprovalActionIntent(
            approvalID: approvalID,
            hostID: attributes.hostID,
            decision: .reject,
            riskLevel: riskParameter
        )
    }

    private var approveIntent: ApprovalActionIntent {
        ApprovalActionIntent(
            approvalID: approvalID,
            hostID: attributes.hostID,
            decision: .approve,
            riskLevel: riskParameter
        )
    }
}
