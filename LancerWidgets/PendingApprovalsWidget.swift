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
//
// Palette mirrors `LancerLiveActivityWidget` / `AgentStatusWidget`: orange for
// waiting, green for clear — same meanings as the island approval glyph.

private enum PendingApprovalsPalette {
    static let background = Color.black
    static let accent = Color.orange
    static let clear = Color.green.opacity(0.85)
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.65)
}

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
        // Prefer the approvals-specific timestamp; fall back to the shared
        // lastUpdatedKey for snapshots written before this key existed.
        let updated = defaults?.double(forKey: WidgetSnapshot.pendingApprovalsUpdatedKey)
            ?? defaults?.double(forKey: WidgetSnapshot.lastUpdatedKey)
            ?? 0
        // App-Group snapshot can outlive the phone-local rows it was written
        // from (app killed before a TTL sweep). If the snapshot itself is
        // older than the pending TTL, treat the count as zero — same corpse
        // window `ApprovalRepository.expireStalePending` uses.
        if updated > 0 {
            let age = Date().timeIntervalSince1970 - updated
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

    private var isWaiting: Bool { entry.count > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: isWaiting ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(isWaiting ? PendingApprovalsPalette.accent : PendingApprovalsPalette.clear)
            Spacer(minLength: 0)
            Text("\(entry.count)")
                .font(.system(.title, design: .rounded).weight(.bold))
                .foregroundStyle(PendingApprovalsPalette.primaryText)
            Text(entry.count == 1 ? "approval waiting" : "approvals waiting")
                .font(.caption2)
                .foregroundStyle(PendingApprovalsPalette.secondaryText)
            if let summary = entry.newestSummary {
                Text(summary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(PendingApprovalsPalette.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .containerBackground(PendingApprovalsPalette.background, for: .widget)
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
