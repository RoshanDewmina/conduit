import WidgetKit
import SwiftUI
import LancerCore

// Home Screen widget #1: running-agent snapshot, read from the App Group
// `WidgetSnapshot` keys the app writes in
// `SessionFeature/SessionViewModel.swift:writeWidgetSnapshot`.
//
// KNOWN V1 LIMITATION (matches the existing fleet-wide caveat documented on
// `LancerLiveActivityManager.updatePendingApprovals`): the snapshot is a
// single global slot, not one row per active session, so `lines` below is at
// most a single one-liner today even though the widget is designed to show
// several. Attributing snapshot state to a specific session/host is a
// separate, bigger change — not solved here.

struct AgentStatusEntry: TimelineEntry {
    let date: Date
    let runningCount: Int
    let lines: [String]
}

struct AgentStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgentStatusEntry {
        AgentStatusEntry(date: .now, runningCount: 1, lines: ["Claude Code · connected"])
    }

    func getSnapshot(in context: Context, completion: @escaping (AgentStatusEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentStatusEntry>) -> Void) {
        let e = entry()
        // Fallback refresh; `WidgetCenter.reloadAllTimelines()` from the app
        // (SessionViewModel.writeWidgetSnapshot) is the primary trigger.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: e.date)!
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func entry() -> AgentStatusEntry {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
        let status = defaults?.string(forKey: WidgetSnapshot.sessionStatusKey)
        let hostName = defaults?.string(forKey: WidgetSnapshot.hostNameKey)
        let agentName = defaults?.string(forKey: WidgetSnapshot.agentNameKey)

        let isActive = (status == "connected" || status == "reconnecting")
        guard isActive else {
            return AgentStatusEntry(date: .now, runningCount: 0, lines: [])
        }
        let name = agentName ?? "Agent"
        let line = hostName.map { "\(name) on \($0)" } ?? name
        return AgentStatusEntry(date: .now, runningCount: 1, lines: [line])
    }
}

struct AgentStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgentStatusEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entry.runningCount > 0 ? "bolt.fill" : "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(entry.runningCount > 0 ? Color.orange : Color(white: 0.5))
            Spacer(minLength: 0)
            Text("\(entry.runningCount)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(entry.runningCount == 1 ? "agent running" : "agents running")
                .font(.caption2)
                .foregroundStyle(Color(white: 0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .containerBackground(.black, for: .widget)
        .accessibilityElement(children: .combine)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lancer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(entry.runningCount) running")
                    .font(.caption2)
                    .foregroundStyle(entry.runningCount > 0 ? Color.orange : Color(white: 0.5))
            }
            if entry.lines.isEmpty {
                Text("No agents running")
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.55))
            } else {
                ForEach(entry.lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(.black, for: .widget)
    }
}

struct AgentStatusWidget: Widget {
    let kind = "AgentStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentStatusProvider()) { entry in
            AgentStatusWidgetView(entry: entry)
                .widgetURL(URL(string: "lancer://open"))
        }
        .configurationDisplayName("Agent Status")
        .description("Shows how many agents are running and where.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
