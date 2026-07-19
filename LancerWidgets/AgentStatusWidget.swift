import WidgetKit
import SwiftUI
import LancerCore

// Home Screen widget #1: running-agent snapshot, read from the App Group
// `WidgetSnapshot` keys written by:
//   1. `LiveActivityRunningAgentsWidget` — same Live Activity truth as the
//      Dynamic Island (ShellLiveBridge start/update/end + push-to-start
//      Activities reconciled on foreground / app launch)
//   2. `RunningAgentsMapping.writeRunningAgentsWidgetSnapshot` when the
//      Workspaces Agents daemon poll reports running sessions (richer cwd lines)
//
// Do NOT key off `sessionStatusKey` alone — that is phone↔daemon session
// liveness. Prefer Live Activity / daemon running agents.

struct AgentStatusEntry: TimelineEntry {
    let date: Date
    let runningCount: Int
    let lines: [String]
}

struct AgentStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgentStatusEntry {
        AgentStatusEntry(date: .now, runningCount: 1, lines: ["Claude Code · lancer"])
    }

    func getSnapshot(in context: Context, completion: @escaping (AgentStatusEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentStatusEntry>) -> Void) {
        let e = entry()
        // Fallback refresh; `WidgetCenter.reloadTimelines(ofKind:)` from
        // `writeRunningAgentsWidgetSnapshot` is the primary trigger.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: e.date)!
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func entry() -> AgentStatusEntry {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
        let count = defaults?.integer(forKey: WidgetSnapshot.runningAgentsCountKey) ?? 0
        let lines = defaults?.stringArray(forKey: WidgetSnapshot.runningAgentsLinesKey) ?? []
        // If count > 0 but lines were cleared, still show the numeric count.
        return AgentStatusEntry(date: .now, runningCount: count, lines: lines)
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
            if entry.runningCount == 0 || entry.lines.isEmpty {
                Text(entry.runningCount == 0 ? "No agents running" : "\(entry.runningCount) agents running")
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
