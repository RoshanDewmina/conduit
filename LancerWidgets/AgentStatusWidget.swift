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
//
// Palette mirrors `LancerLiveActivityWidget` (orange accent for active work,
// muted secondary text on black) so Home Screen + island read as one system.

private enum AgentStatusPalette {
    static let background = Color.black
    static let accent = Color.orange
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.65)
    static let mutedText = Color(white: 0.55)
    static let idleGlyph = Color(white: 0.5)
}

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
        let storedCount = defaults?.integer(forKey: WidgetSnapshot.runningAgentsCountKey) ?? 0
        // Dedupe identical lines at the read edge too — older App Group
        // snapshots written before ActivityKit dedupe can still carry clones.
        let rawLines = defaults?.stringArray(forKey: WidgetSnapshot.runningAgentsLinesKey) ?? []
        var lines: [String] = []
        var seen = Set<String>()
        for line in rawLines where seen.insert(line).inserted {
            lines.append(line)
        }
        // Inflated count from duplicate ActivityKit rows → trust unique lines.
        let count: Int
        if !lines.isEmpty, storedCount > lines.count, Set(rawLines).count < rawLines.count {
            count = lines.count
        } else {
            count = storedCount
        }
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

    private var isActive: Bool { entry.runningCount > 0 }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: isActive ? "bolt.fill" : "moon.zzz.fill")
                .font(.title2)
                .foregroundStyle(isActive ? AgentStatusPalette.accent : AgentStatusPalette.idleGlyph)
            Spacer(minLength: 0)
            Text("\(entry.runningCount)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(AgentStatusPalette.primaryText)
            Text(entry.runningCount == 1 ? "agent running" : "agents running")
                .font(.caption2)
                .foregroundStyle(AgentStatusPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .containerBackground(AgentStatusPalette.background, for: .widget)
        .accessibilityElement(children: .combine)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agents")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AgentStatusPalette.primaryText)
                Spacer(minLength: 8)
                Text(isActive ? "\(entry.runningCount) running" : "Idle")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isActive ? AgentStatusPalette.accent : AgentStatusPalette.idleGlyph)
            }
            if !isActive {
                Text("No agents running")
                    .font(.footnote)
                    .foregroundStyle(AgentStatusPalette.mutedText)
            } else if entry.lines.isEmpty {
                Text(entry.runningCount == 1 ? "1 agent running" : "\(entry.runningCount) agents running")
                    .font(.footnote)
                    .foregroundStyle(AgentStatusPalette.mutedText)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AgentStatusPalette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(AgentStatusPalette.background, for: .widget)
        .accessibilityElement(children: .combine)
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
