import WidgetKit
import SwiftUI
import LancerCore

// Home Screen widget #2: pending-approval count + newest one-liner, read from
// the App Group `WidgetSnapshot` keys the app writes in
// `PersistenceKit/ApprovalRepository+WidgetSnapshot.swift`. That writer is
// invoked from both `ApprovalIngest` (new approval arrives) and
// `ApprovalRelay.enqueue` (a decision resolves one), and calls
// `WidgetCenter.shared.reloadTimelines(ofKind: "PendingApprovalsWidget")` —
// the `kind` string below MUST stay in sync with that literal.

struct PendingApprovalsEntry: TimelineEntry {
    let date: Date
    let count: Int
    let newestSummary: String?
}

struct PendingApprovalsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PendingApprovalsEntry {
        PendingApprovalsEntry(date: .now, count: 1, newestSummary: "rm -rf build/ · High risk")
    }

    func getSnapshot(in context: Context, completion: @escaping (PendingApprovalsEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PendingApprovalsEntry>) -> Void) {
        let e = entry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: e.date)!
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func entry() -> PendingApprovalsEntry {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID)
        let lastUpdated = defaults?.double(forKey: WidgetSnapshot.lastUpdatedKey) ?? 0
        // App-Group snapshot can outlive the phone-local rows it was written
        // from (app killed before a TTL sweep). If the snapshot itself is
        // older than the pending TTL, treat the count as zero — same corpse
        // window `ApprovalRepository.expireStalePending` uses.
        if lastUpdated > 0 {
            let age = Date().timeIntervalSince1970 - lastUpdated
            if age > WidgetSnapshot.pendingApprovalTTL {
                return PendingApprovalsEntry(date: .now, count: 0, newestSummary: nil)
            }
        }
        let count = defaults?.integer(forKey: WidgetSnapshot.pendingApprovalsKey) ?? 0
        let summary = defaults?.string(forKey: WidgetSnapshot.pendingApprovalSummaryKey)
        return PendingApprovalsEntry(date: .now, count: count, newestSummary: count > 0 ? summary : nil)
    }
}

struct PendingApprovalsWidgetView: View {
    let entry: PendingApprovalsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entry.count > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(entry.count > 0 ? Color.orange : Color.green.opacity(0.8))
            Spacer(minLength: 0)
            Text("\(entry.count)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(entry.count == 1 ? "approval waiting" : "approvals waiting")
                .font(.caption2)
                .foregroundStyle(Color(white: 0.65))
            if let summary = entry.newestSummary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .containerBackground(.black, for: .widget)
        .widgetURL(URL(string: "lancer://open"))
        .accessibilityElement(children: .combine)
    }
}

struct PendingApprovalsWidget: Widget {
    let kind = "PendingApprovalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PendingApprovalsProvider()) { entry in
            PendingApprovalsWidgetView(entry: entry)
        }
        .configurationDisplayName("Pending Approvals")
        .description("Shows how many approvals are waiting for you.")
        .supportedFamilies([.systemSmall])
    }
}
