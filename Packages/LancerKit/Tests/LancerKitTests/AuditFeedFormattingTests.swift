import Testing
import Foundation
@testable import AppFeature
import LancerCore

@Suite("AuditFeedFormatting")
struct AuditFeedFormattingTests {
    private let fixedNow = ISO8601DateFormatter().date(from: "2026-07-16T20:00:00Z")!

    @Test("parses a real JSON audit line")
    func parsesRealJSONLine() {
        let line = """
        {"timestamp":"2026-07-16T19:50:00Z","action":"approve","agent":"claudeCode","kind":"command","command":"ls -la","effect":"allow","rule":"human","hash":"abc","prevHash":"def"}
        """
        let entry = AuditFeedFormatting.parseLine(line)
        #expect(entry != nil)
        #expect(entry?.action == "approve")
        #expect(entry?.command == "ls -la")
        #expect(entry?.effect == "allow")
        #expect(entry?.agent == "claudeCode")

        let rows = AuditFeedFormatting.rows(fromLines: [line], now: fixedNow)
        #expect(rows.count == 1)
        #expect(rows[0].isParsed)
        #expect(rows[0].primaryLine == "Approved · ls -la")
        #expect(rows[0].effectTint == .allow)
        #expect(rows[0].secondaryLine.contains("claudeCode"))
        #expect(rows[0].secondaryLine.contains("allow"))
        #expect(rows[0].rawLine == line.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("unparseable line falls back to raw row")
    func unparseableFallsBackRaw() {
        let garbage = "not-json-at-all {{{"
        let rows = AuditFeedFormatting.rows(fromLines: [garbage], now: fixedNow)
        #expect(rows.count == 1)
        #expect(rows[0].isParsed == false)
        #expect(rows[0].primaryLine == garbage)
        #expect(rows[0].rawLine == garbage)
        #expect(rows[0].secondaryLine.isEmpty)
        #expect(AuditFeedFormatting.parseLine(garbage) == nil)
    }

    @Test("orders newest-first")
    func ordersNewestFirst() {
        let older = """
        {"timestamp":"2026-07-12T10:00:00Z","action":"escalate","agent":"codex","kind":"command","command":"git status","effect":"ask"}
        """
        let newer = """
        {"timestamp":"2026-07-16T19:50:00Z","action":"dispatch-launched","agent":"claudeCode","kind":"dispatch","command":"Hi","effect":"allow"}
        """
        let rows = AuditFeedFormatting.rows(fromLines: [older, newer], now: fixedNow)
        #expect(rows.count == 2)
        #expect(rows[0].primaryLine == "Launched · Hi")
        #expect(rows[1].primaryLine == "Escalated · git status")

        let fromEntries = AuditFeedFormatting.rows(
            fromEntries: [
                AuditLogEntryFixture(timestamp: "2026-07-12T10:00:00Z", action: "escalate", command: "git status", effect: "ask"),
                AuditLogEntryFixture(timestamp: "2026-07-16T19:50:00Z", action: "dispatch-launched", command: "Hi", effect: "allow"),
            ].map(\.entry),
            now: fixedNow
        )
        #expect(fromEntries[0].primaryLine == "Launched · Hi")
        #expect(fromEntries[1].primaryLine == "Escalated · git status")
    }

    @Test("relative-time formatting is stable with fixed now")
    func relativeTimeStable() {
        let twoMinutesAgo = ISO8601DateFormatter().date(from: "2026-07-16T19:58:00Z")!
        #expect(AuditFeedFormatting.relativeTime(from: twoMinutesAgo, now: fixedNow) == "2m ago")

        let june30 = ISO8601DateFormatter().date(from: "2026-06-30T10:00:00Z")!
        #expect(AuditFeedFormatting.relativeTime(from: june30, now: fixedNow) == "Jun 30")

        let line = """
        {"timestamp":"2026-07-16T19:58:00Z","action":"approve","command":"ls -la","effect":"allow"}
        """
        let rows = AuditFeedFormatting.rows(fromLines: [line], now: fixedNow)
        #expect(rows[0].secondaryLine.hasPrefix("2m ago"))
    }

    @Test("keeps unparseable lines when mixed with parsed ones")
    func neverDropsUnparseableAmongParsed() {
        let good = """
        {"timestamp":"2026-07-16T19:50:00Z","action":"deny","command":"rm -rf /","effect":"deny"}
        """
        let bad = "BROKEN"
        let rows = AuditFeedFormatting.rows(fromLines: [good, bad], now: fixedNow)
        #expect(rows.count == 2)
        #expect(rows.contains(where: { $0.primaryLine == "Denied · rm -rf /" }))
        #expect(rows.contains(where: { !$0.isParsed && $0.rawLine == bad }))
    }
}

/// Tiny Codable fixture helper — `AuditLogEntry` has no public memberwise init.
private struct AuditLogEntryFixture: Encodable {
    var timestamp: String
    var action: String
    var agent: String? = nil
    var kind: String? = nil
    var command: String? = nil
    var effect: String? = nil
    var rule: String? = nil

    var entry: AuditLogEntry {
        let data = try! JSONEncoder().encode(self)
        return try! JSONDecoder().decode(AuditLogEntry.self, from: data)
    }
}
