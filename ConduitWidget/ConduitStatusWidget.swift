import WidgetKit
import SwiftUI
import AppIntents
import ConduitCore

struct ConduitStatusEntry: TimelineEntry {
    let date: Date
    let hostName: String
    let status: String
    let pendingApprovals: Int
}

struct ConduitWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Conduit Status"
    static let description = IntentDescription("Shows session status and pending approvals.")
}

struct ConduitStatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConduitStatusEntry {
        ConduitStatusEntry(date: .now, hostName: "Conduit", status: "disconnected", pendingApprovals: 0)
    }

    func snapshot(for configuration: ConduitWidgetIntent, in context: Context) async -> ConduitStatusEntry {
        entry()
    }

    func timeline(for configuration: ConduitWidgetIntent, in context: Context) async -> Timeline<ConduitStatusEntry> {
        let current = entry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: current.date) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [current], policy: .after(next))
    }

    private func entry() -> ConduitStatusEntry {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
        let hostName = defaults?.string(forKey: WidgetSnapshot.hostNameKey) ?? "Conduit"
        let status = defaults?.string(forKey: WidgetSnapshot.sessionStatusKey) ?? "disconnected"
        let pending = defaults?.integer(forKey: WidgetSnapshot.pendingApprovalsKey) ?? 0
        return ConduitStatusEntry(
            date: .now,
            hostName: hostName,
            status: status,
            pendingApprovals: max(0, pending)
        )
    }
}

struct ConduitStatusWidget: Widget {
    let kind = "ConduitStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConduitWidgetIntent.self, provider: ConduitStatusProvider()) { entry in
            ConduitStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Conduit")
        .description("Pending approvals and session status.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct ConduitStatusWidgetView: View {
    let entry: ConduitStatusEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(entry.status.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(entry.hostName)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Label("\(entry.pendingApprovals) pending", systemImage: "bell.badge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.pendingApprovals > 0 ? .orange : .green)
            }
            .padding(12)
            .containerBackground(.background, for: .widget)
        case .accessoryCircular:
            ZStack {
                Circle().fill(entry.pendingApprovals > 0 ? Color.orange.opacity(0.25) : Color.green.opacity(0.25))
                VStack(spacing: 2) {
                    Image(systemName: entry.pendingApprovals > 0 ? "bell.badge.fill" : "checkmark")
                        .font(.caption2.weight(.semibold))
                    Text("\(entry.pendingApprovals)")
                        .font(.caption2.monospacedDigit())
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.hostName).lineLimit(1)
                Text("\(entry.pendingApprovals) pending • \(entry.status)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .accessoryInline:
            Text("Conduit \(entry.pendingApprovals) pending (\(entry.status))")
        default:
            Text("Conduit")
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case "connected": .green
        case "reconnecting": .orange
        case "suspended": .yellow
        default: .gray
        }
    }
}
