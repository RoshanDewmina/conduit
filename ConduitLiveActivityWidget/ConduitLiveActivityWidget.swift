// Tier 1.5.1 — iOS Widget Extension that renders the Conduit session
// Live Activity on the lock screen and Dynamic Island.
//
// The activity is started by `ConduitLiveActivityManager` in the main app
// target. This extension only reacts to its `ContentState` updates — it
// neither owns nor mutates state.

import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import SessionFeature
import NotificationsKit

@main
struct ConduitLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.2, *) {
            ConduitSessionLiveActivity()
        }
    }
}

@available(iOS 16.2, *)
struct ConduitSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ConduitSessionAttributes.self) { context in
            // Lock-screen + banner appearance.
            HStack(spacing: 12) {
                LiveActivityPixelGlyph(
                    color: statusColor(context.state.status,
                                       pendingApprovals: context.state.pendingApprovals,
                                       isStreaming: context.state.isStreaming),
                    cell: 7, gap: 2
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.hostName)
                        .font(.headline)
                    HStack(spacing: 4) {
                        if let agent = context.state.agentName {
                            Text(agent).foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                        }
                        Text(context.state.status)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.monospaced())
                    Spacer()
                    if context.state.pendingApprovals > 0 {
                        Label("\(context.state.pendingApprovals)", systemImage: "bell.badge.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                            .font(.caption.weight(.semibold))
                    }
                }

                if let approvalID = context.state.pendingApprovalID, !approvalID.isEmpty {
                    HStack(spacing: 8) {
                        Button(
                            intent: ApprovalActionIntent(
                                approvalID: approvalID,
                                hostID: context.attributes.hostID,
                                decision: .reject
                            )
                        ) {
                            Label("Reject", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)

                        Button(
                            intent: ApprovalActionIntent(
                                approvalID: approvalID,
                                hostID: context.attributes.hostID,
                                decision: .approve
                            )
                        ) {
                            Label("Approve", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black.opacity(0.75))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityPixelGlyph(
                        color: statusColor(context.state.status,
                                           pendingApprovals: context.state.pendingApprovals),
                        cell: 6, gap: 2
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.pendingApprovals > 0 {
                        Label("\(context.state.pendingApprovals)", systemImage: "bell.badge.fill")
                            .foregroundStyle(.orange)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .center, spacing: 1) {
                        Text(context.attributes.hostName).font(.headline)
                        if let agent = context.state.agentName {
                            Text(agent).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let approvalID = context.state.pendingApprovalID, !approvalID.isEmpty {
                        HStack(spacing: 10) {
                            Button(
                                intent: ApprovalActionIntent(
                                    approvalID: approvalID,
                                    hostID: context.attributes.hostID,
                                    decision: .reject
                                )
                            ) {
                                Label("Reject", systemImage: "xmark")
                            }
                            .buttonStyle(.bordered)
                            Button(
                                intent: ApprovalActionIntent(
                                    approvalID: approvalID,
                                    hostID: context.attributes.hostID,
                                    decision: .approve
                                )
                            ) {
                                Label("Approve", systemImage: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } compactLeading: {
                LiveActivityPixelGlyph(
                    color: statusColor(context.state.status,
                                       pendingApprovals: context.state.pendingApprovals,
                                       isStreaming: context.state.isStreaming),
                    cell: 4, gap: 1.4
                )
            } compactTrailing: {
                if context.state.pendingApprovals > 0 {
                    Text("\(context.state.pendingApprovals)")
                        .foregroundStyle(.orange)
                }
            } minimal: {
                LiveActivityPixelGlyph(
                    color: statusColor(context.state.status,
                                       pendingApprovals: context.state.pendingApprovals,
                                       isStreaming: context.state.isStreaming),
                    cell: 3.4, gap: 1.1
                )
            }
        }
    }

    /// State tint for the pixel glyph — mirrors `PixelBox.stateColor`. A pending
    /// approval is the most important signal, so it wins (amber) over connection
    /// status, matching how the in-app island goes amber on approval.
    private func statusColor(_ status: String, pendingApprovals: Int, isStreaming: Bool = false) -> Color {
        if pendingApprovals > 0 {
            return Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1) // amber
        }
        if isStreaming {
            return Color(.sRGB, red: 0.318, green: 0.573, blue: 0.929, opacity: 1) // blue (streaming)
        }
        switch status {
        case "connected":    return Color(.sRGB, red: 0.173, green: 0.608, blue: 0.349, opacity: 1) // green
        case "reconnecting": return Color(.sRGB, red: 0.820, green: 0.439, blue: 0.184, opacity: 1) // orange
        case "suspended":    return Color(.sRGB, red: 0.373, green: 0.357, blue: 0.329, opacity: 1) // dim
        default:             return Color(.sRGB, red: 0.173, green: 0.608, blue: 0.349, opacity: 1) // green
        }
    }
}

/// A static 3×3 "pixel block" that mirrors the in-app `PixelBox` motif for the
/// Live Activity. Widget extensions render static snapshots — no `TimelineView`
/// animation — so this is a still grid tinted by session state, with a fixed
/// per-cell opacity pattern so it reads as pixels rather than a solid square.
private struct LiveActivityPixelGlyph: View {
    let color: Color
    var cell: CGFloat = 4
    var gap: CGFloat = 1.4

    private static let opacities: [Double] = [
        0.55, 0.95, 0.70,
        0.90, 0.65, 0.95,
        0.70, 0.92, 0.55,
    ]

    var body: some View {
        VStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { col in
                        RoundedRectangle(cornerRadius: max(0.5, cell * 0.18), style: .continuous)
                            .fill(color.opacity(Self.opacities[row * 3 + col]))
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
