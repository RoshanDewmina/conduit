import Foundation
import Observation
import LancerCore

/// Pure helpers for thread-list row metadata (diff totals, preview, unread, relative time).
public enum ThreadListMetadata {
    public static let previewMaxCharacters = 120

    /// Same totals SessionDiffPill reads from `RepoDiffSummary`.
    public static func diffTotals(from summary: RepoDiffSummary) -> (added: Int, removed: Int)? {
        guard summary.hasChanges else { return nil }
        return (summary.totalAdded, summary.totalRemoved)
    }

    /// Aggregate +/− from tool artifacts (same `added`/`removed` chips use).
    public static func diffTotals(fromToolArtifacts artifacts: [ChatArtifact]) -> (added: Int, removed: Int)? {
        let chips = artifacts.filter { $0.kind == .tool }.map(ToolChipItem.init(artifact:))
        return TurnTranscriptAssembler.aggregatedDiff(chips: chips)
    }

    /// Prefer a persisted `.diff` payload shaped like `RepoDiffSummary`; else tool chips.
    public static func diffTotals(fromArtifacts artifacts: [ChatArtifact]) -> (added: Int, removed: Int)? {
        for artifact in artifacts.reversed() where artifact.kind == .diff {
            guard let data = artifact.payloadJSON.data(using: .utf8),
                  let summary = try? JSONDecoder().decode(RepoDiffSummary.self, from: data),
                  let totals = diffTotals(from: summary)
            else { continue }
            return totals
        }
        return diffTotals(fromToolArtifacts: artifacts)
    }

    /// One-line preview from the latest turn — local fields only (no RPC).
    public static func previewSnippet(lastTurn: ChatTurn?) -> String? {
        guard let lastTurn else { return nil }
        if let snippet = collapsedPreview(lastTurn.assistantText) { return snippet }
        return collapsedPreview(lastTurn.prompt)
    }

    public static func isUnread(lastActivityAt: Date, lastOpenedAt: Date?) -> Bool {
        guard let lastOpenedAt else { return true }
        return lastActivityAt > lastOpenedAt
    }

    public static func relativeActivity(
        _ date: Date,
        relativeTo now: Date = .now
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func collapsedPreview(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let singleLine = trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if singleLine.count <= previewMaxCharacters { return singleLine }
        let end = singleLine.index(singleLine.startIndex, offsetBy: previewMaxCharacters)
        return String(singleLine[..<end]) + "…"
    }
}

/// Local last-opened timestamps per conversation — cheap unread receipts for the thread list.
@MainActor
@Observable
public final class ConversationReadReceiptStore {
    private static let defaultsKey = "dev.lancer.conversationReadReceipts"

    private let userDefaults: UserDefaults
    private var openedAtByID: [String: Date]

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.openedAtByID = Self.load(from: userDefaults)
    }

    public func lastOpenedAt(conversationID: String) -> Date? {
        openedAtByID[conversationID]
    }

    public func markOpened(_ conversationID: String, at date: Date = .now) {
        let trimmed = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = openedAtByID[trimmed], existing >= date { return }
        openedAtByID[trimmed] = date
        persist()
    }

    private func persist() {
        let payload = openedAtByID.mapValues { $0.timeIntervalSince1970 }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> [String: Date] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return [:] }
        return decoded.mapValues { Date(timeIntervalSince1970: $0) }
    }
}
