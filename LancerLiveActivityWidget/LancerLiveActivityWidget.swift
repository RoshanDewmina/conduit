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

// MARK: - Palette
//
// Mirrors DesignSystem/Tokens.swift's `LancerTokens.dark` semantic colors —
// sage-green `ok`, amber `warn`, dusty-red `danger`, warm-orange `accent` — so
// the widget matches the app's actual (post-rebrand) Editorial system instead
// of the pre-rebrand bright green/amber/red plus an ad-hoc blue that had
// never been part of any token set. Hardcoded here (not imported from
// DesignSystem) because this extension target only depends on SessionFeature;
// pulling in the whole component library would bloat the extension binary for
// four color constants. Keep these literals in sync with Tokens.swift's dark
// palette if that palette is ever retuned.
private enum LAPalette {
    static let ok         = Color(.sRGB, red: 0.212, green: 0.761, blue: 0.420, opacity: 1) // #36c26b
    static let warn       = Color(.sRGB, red: 0.941, green: 0.663, blue: 0.231, opacity: 1) // #f0a93b
    static let warnSoft   = Color(.sRGB, red: 0.165, green: 0.125, blue: 0.031, opacity: 1) // #2a2008
    static let danger     = Color(.sRGB, red: 0.878, green: 0.325, blue: 0.247, opacity: 1) // #e0533f
    static let dangerSoft = Color(.sRGB, red: 0.165, green: 0.078, blue: 0.063, opacity: 1) // #2a1410
    static let accent     = Color(.sRGB, red: 0.894, green: 0.482, blue: 0.341, opacity: 1) // #e47b57
    static let idle       = Color(.sRGB, red: 0.494, green: 0.478, blue: 0.431, opacity: 1) // #7e7a6e (text3)
}

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
                        Label("\(context.state.pendingApprovals)", systemImage: approvalBadgeSymbol(for: context.state))
                            .foregroundStyle(approvalBadgeColor(for: context.state))
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
                                    .foregroundStyle(LAPalette.ok)
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
        let presentation = LiveActivityPresentation.resolve(context.state, budget: nil)
        let needsApproval: Bool = { if case .needsYou = presentation.primary { return true } else { return false } }()
        let isElevated = needsApproval && presentation.riskTier?.isElevated == true

        // Escalation for a high/critical pending approval shifts the WHOLE card's
        // tone and swaps the headline to the urgent copy, rather than stacking a
        // second banner row above the existing one. Real Live Activities that
        // escalate urgency (Duolingo's streak-loss card, BeReal's reminder,
        // Rivian's alarm) all do a single-surface tone/copy swap, not a two-tier
        // banner — checked against comparable apps via Mobbin before building
        // this. A stacked band would add height to an already tiny surface and
        // duplicate what the trailing risk badge already signals.
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor(for: context.state))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                if isElevated {
                    Text("High-risk action")
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text(context.state.agentName ?? context.attributes.hostName)
                        .font(.headline)
                        .lineLimit(1)
                }

                // Status + cost (elevated: lead with the agent/host name here
                // instead, since the headline above already spent on urgency)
                HStack(spacing: 6) {
                    if isElevated {
                        Text(context.state.agentName ?? context.attributes.hostName)
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                    }

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
                Label("\(context.state.pendingApprovals)", systemImage: approvalBadgeSymbol(for: context.state))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(approvalBadgeColor(for: context.state))
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(isElevated ? LAPalette.dangerSoft.opacity(0.92) : Color.black.opacity(0.75))
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
        // `isDynamicIslandLimitedInWidth` doesn't exist in the iOS 26 SDK at
        // all (not just runtime-unavailable) — `if #available` alone can't
        // gate this because Swift still type-checks the branch under any
        // SDK. `#if swift(>=6.4)` additionally excludes it from compilation
        // entirely when building with a toolchain/SDK that predates iOS 27.
        #if swift(>=6.4)
        if #available(iOS 27.0, *) {
            DynamicIslandWidthReader { isLimitedWidth in
                if isLimitedWidth {
                    // Landscape Dynamic Island has no spare width for the
                    // numeric/text badge — drop it and rely on the leading
                    // dot's color alone (see compactLeadingView).
                    EmptyView()
                } else {
                    compactTrailingBadge(context: context)
                }
            }
        } else {
            compactTrailingBadge(context: context)
        }
        #else
        compactTrailingBadge(context: context)
        #endif
    }

    @ViewBuilder
    private func compactTrailingBadge(context: ActivityViewContext<LancerSessionAttributes>) -> some View {
        if context.state.pendingApprovals > 0 {
            Text("\(context.state.pendingApprovals)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(approvalBadgeColor(for: context.state))
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
            .tint(LAPalette.danger)

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
            .tint(LAPalette.accent)
        }
        .font(.caption)
    }

    // MARK: - Risk-tiered approval badge (Gap #2: a high/critical approval must
    // not render identically to a routine one — see LiveActivityPresentation.riskTier)

    private func approvalBadgeSymbol(for state: LancerSessionAttributes.ContentState) -> String {
        LiveActivityPresentation.resolve(state, budget: nil).riskTier?.isElevated == true
            ? "exclamationmark.triangle.fill"
            : "bell.badge.fill"
    }

    private func approvalBadgeColor(for state: LancerSessionAttributes.ContentState) -> Color {
        LiveActivityPresentation.resolve(state, budget: nil).riskTier?.isElevated == true
            ? LAPalette.danger // high/critical
            : LAPalette.warn   // routine
    }

    // MARK: - Status Colors
    //
    // sage-green (ok) for running/connected/approved/online, amber (warn) for
    // "needs you" / reconnecting, dusty-red (danger) for rejected/error/blocked
    // high-risk — no blue anywhere. Matches the app's actual Editorial · Sand
    // status trio (see LAPalette above); previously `.running` rendered an
    // ad-hoc blue that was never part of any token set.

    private func statusColor(for state: LancerSessionAttributes.ContentState) -> Color {
        let p = LiveActivityPresentation.resolve(state, budget: nil)
        switch p.primary {
        case .needsYou:
            return p.riskTier?.isElevated == true ? LAPalette.danger : LAPalette.warn
        case .decisionLanded(let approved):
            return approved ? LAPalette.ok : LAPalette.danger
        case .running:
            return LAPalette.ok
        case .idle:
            switch state.status {
            case "reconnecting": return LAPalette.warn
            case "error":        return LAPalette.danger
            case "suspended":    return LAPalette.idle
            default:             return LAPalette.ok
            }
        }
    }

    private func statusLabel(for state: LancerSessionAttributes.ContentState) -> String {
        let p = LiveActivityPresentation.resolve(state, budget: nil)
        switch p.primary {
        case .needsYou(let count):
            let base = count == 1 ? "1 pending" : "\(count) pending"
            switch p.riskTier {
            case .critical: return base + " · critical"
            case .high:     return base + " · high risk"
            default:        return base
            }
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
        case .over:    return LAPalette.danger
        case .warning: return LAPalette.warn
        default:       return .secondary
        }
    }

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }
}

// MARK: - Dynamic Island landscape width detection
//
// `isDynamicIslandLimitedInWidth` (WidgetKit, iOS 27+) reports whether the
// Dynamic Island's compact/minimal presentation is currently constrained by
// landscape width. It's an `EnvironmentValues` key, so it must be read from
// inside a `View`'s `body` — this small reader lets call sites consume it
// without promoting every helper into its own `View` type.
//
// Guarded by `#if swift(>=6.4)`, not just `@available(iOS 27.0, *)`: the key
// doesn't exist in the iOS 26 SDK at all, so a toolchain/SDK that predates
// iOS 27 can't type-check this struct regardless of runtime availability
// checks at the call site — see `compactTrailingView` above.
#if swift(>=6.4)
@available(iOS 27.0, *)
private struct DynamicIslandWidthReader<Content: View>: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var isDynamicIslandLimitedInWidth
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(isDynamicIslandLimitedInWidth)
    }
}
#endif

// MARK: - Previews
//
// Renders Lock Screen and every Dynamic Island presentation (expanded,
// compact, minimal) directly in Xcode's canvas via `#Preview(as:)` — no
// simulator navigation (home screen, lock screen, notification center)
// needed to see how a real state looks. Use `mcp__xcode__RenderPreview`
// with `previewCanvasControlOverrides.timelineIndex` to step through the
// `contentStates` below, and `.dynamicIsland(...)`/`.content` for the
// `as:` parameter to pick which presentation renders.

@available(iOS 16.2, *)
extension LancerSessionAttributes {
    fileprivate static var preview: LancerSessionAttributes {
        LancerSessionAttributes(hostName: "Roshan's Mac", hostID: "preview-host")
    }
}

@available(iOS 16.2, *)
extension LancerSessionAttributes.ContentState {
    fileprivate static var connected: Self {
        .init(status: "connected", agentName: "Claude Code")
    }
    fileprivate static var streaming: Self {
        .init(status: "connected", agentName: "Claude Code", isStreaming: true, cost: 0.42)
    }
    fileprivate static var needsApproval: Self {
        .init(
            status: "connected", pendingApprovals: 1, agentName: "Claude Code",
            pendingApprovalID: "preview-approval-id", isStreaming: true, cost: 1.18
        )
    }
    fileprivate static var multipleApprovals: Self {
        .init(
            status: "connected", pendingApprovals: 3, agentName: "Codex",
            pendingApprovalID: "preview-approval-id", isStreaming: true, cost: 2.05
        )
    }
    /// Contrast case for Gap #2: same shape as `needsApproval` (routine, amber
    /// bell) but risk 2 (high) — must render with the red warning-triangle badge
    /// and "· high risk" label instead of looking identical.
    fileprivate static var needsApprovalHighRisk: Self {
        .init(
            status: "connected", pendingApprovals: 1, agentName: "Claude Code",
            pendingApprovalID: "preview-approval-id", pendingApprovalRisk: 2,
            isStreaming: true, cost: 1.18
        )
    }
    fileprivate static var needsApprovalCritical: Self {
        .init(
            status: "connected", pendingApprovals: 1, agentName: "Claude Code",
            pendingApprovalID: "preview-approval-id", pendingApprovalRisk: 3,
            isStreaming: false, cost: 3.40
        )
    }
    fileprivate static var approved: Self {
        .init(status: "connected", agentName: "Claude Code", cost: 1.18, lastDecision: "approved")
    }
    fileprivate static var reconnecting: Self {
        .init(status: "reconnecting", agentName: "Claude Code")
    }
    fileprivate static var overBudget: Self {
        .init(status: "connected", agentName: "Claude Code", isStreaming: true, cost: 24.87)
    }
}

@available(iOS 16.2, *)
#Preview("Lock Screen", as: .content, using: LancerSessionAttributes.preview) {
    LancerSessionLiveActivity()
} contentStates: {
    LancerSessionAttributes.ContentState.connected
    LancerSessionAttributes.ContentState.streaming
    LancerSessionAttributes.ContentState.needsApproval
    LancerSessionAttributes.ContentState.needsApprovalHighRisk
    LancerSessionAttributes.ContentState.needsApprovalCritical
    LancerSessionAttributes.ContentState.multipleApprovals
    LancerSessionAttributes.ContentState.approved
    LancerSessionAttributes.ContentState.reconnecting
    LancerSessionAttributes.ContentState.overBudget
}

@available(iOS 16.2, *)
#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: LancerSessionAttributes.preview) {
    LancerSessionLiveActivity()
} contentStates: {
    LancerSessionAttributes.ContentState.connected
    LancerSessionAttributes.ContentState.streaming
    LancerSessionAttributes.ContentState.needsApproval
    LancerSessionAttributes.ContentState.needsApprovalHighRisk
    LancerSessionAttributes.ContentState.needsApprovalCritical
    LancerSessionAttributes.ContentState.multipleApprovals
    LancerSessionAttributes.ContentState.overBudget
}

@available(iOS 16.2, *)
#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: LancerSessionAttributes.preview) {
    LancerSessionLiveActivity()
} contentStates: {
    LancerSessionAttributes.ContentState.connected
    LancerSessionAttributes.ContentState.streaming
    LancerSessionAttributes.ContentState.needsApproval
    LancerSessionAttributes.ContentState.needsApprovalHighRisk
    LancerSessionAttributes.ContentState.multipleApprovals
}

@available(iOS 16.2, *)
#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: LancerSessionAttributes.preview) {
    LancerSessionLiveActivity()
} contentStates: {
    LancerSessionAttributes.ContentState.connected
    LancerSessionAttributes.ContentState.needsApproval
}
