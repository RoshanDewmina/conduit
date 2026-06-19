import WidgetKit
import SwiftUI

private let appGroup = "group.dev.conduit.mobile"
private let pendingKey = "watchPendingCount"

struct InboxCountEntry: TimelineEntry {
    let date: Date
    let pendingCount: Int
}

struct InboxCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> InboxCountEntry {
        InboxCountEntry(date: .now, pendingCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (InboxCountEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InboxCountEntry>) -> Void) {
        let e = entry()
        // Refresh every 15 min as a fallback; WidgetCenter.reloadAllTimelines() from the app is the primary trigger
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: e.date)!
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func entry() -> InboxCountEntry {
        let count = UserDefaults(suiteName: appGroup)?.integer(forKey: pendingKey) ?? 0
        return InboxCountEntry(date: .now, pendingCount: count)
    }
}

struct InboxCountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: InboxCountEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            if entry.pendingCount > 0 {
                Circle()
                    .fill(Color.orange.gradient)
                Text("\(entry.pendingCount)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            } else {
                Circle()
                    .fill(Color.green.gradient.opacity(0.6))
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .containerBackground(.black, for: .widget)
        .accessibilityLabel(accessibilityLabel)
    }

    private var rectangularView: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.pendingCount > 0 ? "tray.fill" : "checkmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.pendingCount > 0 ? Color.orange : Color.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Conduit")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(entry.pendingCount > 0 ? "\(entry.pendingCount) pending" : "All clear")
                    .font(.caption2)
                    .foregroundStyle(entry.pendingCount > 0 ? Color.orange : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.black, for: .widget)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        entry.pendingCount == 0
            ? "Conduit inbox clear"
            : "Conduit inbox, \(entry.pendingCount) pending approval\(entry.pendingCount == 1 ? "" : "s")"
    }
}

struct InboxCountWidget: Widget {
    let kind = "InboxCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InboxCountProvider()) { entry in
            InboxCountWidgetView(entry: entry)
        }
        .configurationDisplayName("Conduit Inbox")
        .description("Shows pending approval count.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular])
    }
}
