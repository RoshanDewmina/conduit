import Foundation
import LancerCore

/// Pure audit-feed presentation helpers (no SwiftUI). Parses JSONL-shaped lines,
/// orders newest-first, and formats relative timestamps with an injectable `now`.
public enum AuditFeedFormatting {
    public enum EffectTint: String, Sendable, Equatable {
        case allow
        case deny
        case ask
        case none
    }

    public struct Row: Identifiable, Sendable, Equatable {
        public let id: String
        /// Structured primary line, or the raw text when unparseable.
        public let primaryLine: String
        /// Relative time + agent + effect pieces (empty for raw rows).
        public let secondaryLine: String
        public let effectTint: EffectTint
        public let effectText: String?
        public let rawLine: String
        public let isParsed: Bool
        /// Sort key; nil when the timestamp could not be parsed.
        public let sortDate: Date?
        public let originalIndex: Int

        public init(
            id: String,
            primaryLine: String,
            secondaryLine: String,
            effectTint: EffectTint,
            effectText: String?,
            rawLine: String,
            isParsed: Bool,
            sortDate: Date?,
            originalIndex: Int
        ) {
            self.id = id
            self.primaryLine = primaryLine
            self.secondaryLine = secondaryLine
            self.effectTint = effectTint
            self.effectText = effectText
            self.rawLine = rawLine
            self.isParsed = isParsed
            self.sortDate = sortDate
            self.originalIndex = originalIndex
        }
    }

    /// Parse a single audit JSONL line. Returns nil when the line is not usable JSON
    /// with at least `timestamp` + `action`.
    public static func parseLine(_ line: String) -> AuditLogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let entry = try? JSONDecoder().decode(AuditLogEntry.self, from: data),
              !entry.timestamp.isEmpty,
              !entry.action.isEmpty
        else {
            return nil
        }
        return entry
    }

    /// Build feed rows from already-decoded relay/SSH entries (newest-first).
    public static func rows(fromEntries entries: [AuditLogEntry], now: Date = Date()) -> [Row] {
        let built = entries.enumerated().map { index, entry in
            row(from: entry, rawLine: encodeRaw(entry), originalIndex: index, now: now)
        }
        return sortedNewestFirst(built)
    }

    /// Build feed rows from raw log lines. Unparseable lines stay as raw text rows (never dropped).
    public static func rows(fromLines lines: [String], now: Date = Date()) -> [Row] {
        let built = lines.enumerated().compactMap { index, line -> Row? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let entry = parseLine(trimmed) {
                return row(from: entry, rawLine: trimmed, originalIndex: index, now: now)
            }
            return Row(
                id: "raw-\(index)",
                primaryLine: trimmed,
                secondaryLine: "",
                effectTint: .none,
                effectText: nil,
                rawLine: trimmed,
                isParsed: false,
                sortDate: nil,
                originalIndex: index
            )
        }
        return sortedNewestFirst(built)
    }

    public static func sortedNewestFirst(_ rows: [Row]) -> [Row] {
        rows.sorted { lhs, rhs in
            switch (lhs.sortDate, rhs.sortDate) {
            case let (l?, r?) where l != r:
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.originalIndex > rhs.originalIndex
            }
        }
    }

    /// Stable relative-time labels for tests and UI. Uses fixed English units.
    public static func relativeTime(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 {
            return absoluteDayMonth(date)
        }
        if seconds < 60 {
            return "\(max(seconds, 0))s ago"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        let days = hours / 24
        if days < 7 {
            return "\(days)d ago"
        }
        return absoluteDayMonth(date)
    }

    public static func displayAction(_ action: String) -> String {
        let lower = action.lowercased()
        if lower == "approve" || lower.hasSuffix("-approve") {
            return "Approved"
        }
        if lower == "deny" || lower.hasSuffix("-deny") || lower.contains("denied") {
            return "Denied"
        }
        if lower.contains("launched") {
            return "Launched"
        }
        if lower == "escalate" || lower.contains("needs-approval") || lower.contains("escalat") {
            return "Escalated"
        }
        if lower.contains("allow") {
            return "Allowed"
        }
        return action
            .split(separator: "-")
            .map { part in
                guard let first = part.first else { return String(part) }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    public static func effectTint(for effect: String?) -> EffectTint {
        switch effect?.lowercased() {
        case "allow": return .allow
        case "deny": return .deny
        case "ask", "escalate": return .ask
        default: return .none
        }
    }

    // MARK: - Private

    private static func row(
        from entry: AuditLogEntry,
        rawLine: String,
        originalIndex: Int,
        now: Date
    ) -> Row {
        let sortDate = parseTimestamp(entry.timestamp)
        let actionLabel = displayAction(entry.action)
        let command = entry.command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primary: String
        if command.isEmpty {
            primary = actionLabel
        } else {
            primary = "\(actionLabel) · \(command)"
        }

        var secondaryParts: [String] = []
        if let sortDate {
            secondaryParts.append(relativeTime(from: sortDate, now: now))
        } else if !entry.timestamp.isEmpty {
            secondaryParts.append(entry.timestamp)
        }
        if let agent = entry.agent, !agent.isEmpty {
            secondaryParts.append(agent)
        }
        let effect = entry.effect?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectText = (effect?.isEmpty == false) ? effect : nil
        if let effectText {
            secondaryParts.append(effectText)
        }

        return Row(
            id: entry.id,
            primaryLine: primary,
            secondaryLine: secondaryParts.joined(separator: " · "),
            effectTint: effectTint(for: effectText),
            effectText: effectText,
            rawLine: rawLine,
            isParsed: true,
            sortDate: sortDate,
            originalIndex: originalIndex
        )
    }

    private static func encodeRaw(_ entry: AuditLogEntry) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(entry),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{\"timestamp\":\"\(entry.timestamp)\",\"action\":\"\(entry.action)\"}"
    }

    private static func parseTimestamp(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func absoluteDayMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
