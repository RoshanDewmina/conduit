// Tier 1.5.1 — iOS Widget Extension that renders the Conduit session
// Live Activity on the lock screen and Dynamic Island.
//
// The activity is started by `ConduitLiveActivityManager` in the main app
// target. This extension only reacts to its `ContentState` updates — it
// neither owns nor mutates state.

import WidgetKit
import SwiftUI
import ActivityKit
import SessionFeature

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
                Image(systemName: statusIcon(context.state.status))
                    .font(.title2)
                    .foregroundStyle(.tint)
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
                }
                Spacer()
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
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: statusIcon(context.state.status))
                        .foregroundStyle(.tint)
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
                DynamicIslandExpandedRegion(.bottom) { EmptyView() }
            } compactLeading: {
                Image(systemName: statusIcon(context.state.status))
                    .foregroundStyle(.tint)
            } compactTrailing: {
                if context.state.pendingApprovals > 0 {
                    Text("\(context.state.pendingApprovals)")
                        .foregroundStyle(.orange)
                }
            } minimal: {
                Image(systemName: statusIcon(context.state.status))
                    .foregroundStyle(.tint)
            }
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "connected":    "circle.fill"
        case "reconnecting": "arrow.triangle.2.circlepath"
        case "suspended":    "pause.circle"
        default:             "circle"
        }
    }
}
