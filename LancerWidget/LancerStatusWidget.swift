import WidgetKit
import SwiftUI
import AppIntents
import LancerCore

struct LancerStatusEntry: TimelineEntry {
    let date: Date
    let hostName: String
    let status: String
    let pendingApprovals: Int
}

struct LancerWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Lancer Status"
    static let description = IntentDescription("Shows session status and pending approvals.")
}

struct LancerStatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LancerStatusEntry {
        LancerStatusEntry(date: .now, hostName: "Lancer", status: "disconnected", pendingApprovals: 0)
    }

    func snapshot(for configuration: LancerWidgetIntent, in context: Context) async -> LancerStatusEntry {
        entry()
    }

    func timeline(for configuration: LancerWidgetIntent, in context: Context) async -> Timeline<LancerStatusEntry> {
        let current = entry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: current.date) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [current], policy: .after(next))
    }

    private func entry() -> LancerStatusEntry {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
        let hostName = defaults?.string(forKey: WidgetSnapshot.hostNameKey) ?? "Lancer"
        let status = defaults?.string(forKey: WidgetSnapshot.sessionStatusKey) ?? "disconnected"
        let pending = defaults?.integer(forKey: WidgetSnapshot.pendingApprovalsKey) ?? 0
        return LancerStatusEntry(
            date: .now,
            hostName: hostName,
            status: status,
            pendingApprovals: max(0, pending)
        )
    }
}

struct LancerStatusWidget: Widget {
    let kind = "LancerStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: LancerWidgetIntent.self, provider: LancerStatusProvider()) { entry in
            LancerStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Lancer")
        .description("Pending approvals and session status.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct LancerStatusWidgetView: View {
    let entry: LancerStatusEntry

    @Environment(\.widgetFamily) private var family

    private enum C {
        static let bg      = Color(.sRGB, red: 0.039, green: 0.043, blue: 0.051, opacity: 1) // #0a0b0d
        static let surface = Color(.sRGB, red: 0.055, green: 0.059, blue: 0.071, opacity: 1) // #0e0f12
        static let dim     = Color(.sRGB, red: 0.541, green: 0.553, blue: 0.588, opacity: 1) // #8a8d96
        static let fg      = Color(.sRGB, red: 0.914, green: 0.914, blue: 0.886, opacity: 1) // #e9e9e2
        static let accent  = Color(.sRGB, red: 0.184, green: 0.263, blue: 1.000, opacity: 1) // #2f43ff
        static let ok      = Color(.sRGB, red: 0.212, green: 0.761, blue: 0.420, opacity: 1) // #36c26b
        static let warn    = Color(.sRGB, red: 0.941, green: 0.663, blue: 0.231, opacity: 1) // #f0a93b
        static let danger  = Color(.sRGB, red: 0.878, green: 0.325, blue: 0.247, opacity: 1) // #e0533f
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallBody
        case .accessoryCircular:
            circularBody
        case .accessoryRectangular:
            rectangularBody
        case .accessoryInline:
            inlineBody
        default:
            Text("Lancer")
        }
    }

    // MARK: - systemSmall

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(entry.status.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(C.dim)
            }
            .padding(.bottom, 6)

            Text(entry.hostName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(C.fg)
                .lineLimit(2)

            Spacer(minLength: 0)

            if entry.pendingApprovals > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(entry.pendingApprovals)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(C.warn)
            } else {
                Text("All clear")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(C.ok)
            }
        }
        .padding(12)
        .background(C.bg, ignoresSafeAreaEdges: .all)
    }

    // MARK: - accessoryCircular

    private var circularBody: some View {
        ZStack {
            Circle()
                .fill(entry.pendingApprovals > 0
                    ? C.warn.opacity(0.2)
                    : C.ok.opacity(0.15))
            VStack(spacing: 1) {
                Image(systemName: entry.pendingApprovals > 0 ? "bell.fill" : "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                if entry.pendingApprovals > 0 {
                    Text("\(entry.pendingApprovals)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(entry.pendingApprovals > 0 ? C.warn : C.ok)
        }
    }

    // MARK: - accessoryRectangular

    private var rectangularBody: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.hostName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(statusLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(C.dim)
            }
            Spacer(minLength: 0)
            if entry.pendingApprovals > 0 {
                Text("\(entry.pendingApprovals)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(C.warn)
            }
        }
    }

    // MARK: - accessoryInline

    private var inlineBody: some View {
        Text(inlineLabel)
            .font(.system(size: 11, weight: .medium))
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch entry.status {
        case "connected":    C.ok
        case "reconnecting": C.warn
        case "suspended":    C.danger
        default:             C.dim
        }
    }

    private var statusLabel: String {
        switch entry.status {
        case "connected":    "Connected"
        case "reconnecting": "Reconnecting"
        case "suspended":    "Suspended"
        default:             "Disconnected"
        }
    }

    private var inlineLabel: String {
        let status = statusLabel
        if entry.pendingApprovals > 0 {
            return "\(entry.hostName) · \(entry.pendingApprovals) pending · \(status)"
        }
        return "\(entry.hostName) · \(status)"
    }
}
