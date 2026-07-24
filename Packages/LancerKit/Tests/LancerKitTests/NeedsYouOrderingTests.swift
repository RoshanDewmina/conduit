import Foundation
import Testing
@testable import AppFeature

@Suite("NeedsYouOrdering")
struct NeedsYouOrderingTests {
    private func item(
        id: String,
        cwd: String,
        at: Date
    ) -> ThreadListItem {
        ThreadListItem(
            id: id,
            title: id,
            statusKind: .completed,
            statusLabel: "Completed",
            repoName: nil,
            cwd: cwd,
            lastActivityAt: at
        )
    }

    @Test("cwdNeedsAttention matches exact and under-path; ignores empty pending cwd")
    func cwdMatchingIsHonest() {
        #expect(
            NeedsYouOrdering.cwdNeedsAttention(
                rowCwd: "/Users/dev/conduit",
                pendingApprovalCwds: ["/Users/dev/conduit"]
            )
        )
        #expect(
            NeedsYouOrdering.cwdNeedsAttention(
                rowCwd: "/Users/dev/conduit/.claude/worktrees/a",
                pendingApprovalCwds: ["/Users/dev/conduit"]
            )
        )
        #expect(
            NeedsYouOrdering.cwdNeedsAttention(
                rowCwd: "/Users/dev/conduit",
                pendingApprovalCwds: ["/Users/dev/conduit/.claude/worktrees/a"]
            )
        )
        #expect(
            !NeedsYouOrdering.cwdNeedsAttention(
                rowCwd: "/Users/dev/other",
                pendingApprovalCwds: ["/Users/dev/conduit"]
            )
        )
        #expect(
            !NeedsYouOrdering.cwdNeedsAttention(
                rowCwd: "/Users/dev/conduit",
                pendingApprovalCwds: ["", "   "]
            )
        )
        #expect(
            !NeedsYouOrdering.cwdNeedsAttention(
                rowCwd: "/Users/dev/conduit",
                pendingApprovalCwds: []
            )
        )
    }

    @Test("sortedNeedsYouFirst promotes attention rows ahead of newer peers")
    func sortPromotesNeedsYou() {
        let newerQuiet = Date(timeIntervalSince1970: 2_000)
        let olderNeeds = Date(timeIntervalSince1970: 1_000)
        let items = [
            item(id: "quiet-new", cwd: "/quiet", at: newerQuiet),
            item(id: "needs-old", cwd: "/needs", at: olderNeeds),
        ]
        let sorted = NeedsYouOrdering.sortedNeedsYouFirst(
            items,
            needsYou: { $0.cwd == "/needs" },
            sortDate: { $0.lastActivityAt }
        )
        #expect(sorted.map(\.id) == ["needs-old", "quiet-new"])
    }

    @Test("groupNeedsYouFirstThenRecency puts Needs you ahead of Today")
    func groupNeedsYouSection() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00 UTC
        let startOfToday = calendar.startOfDay(for: now)
        let todayMorning = calendar.date(byAdding: .hour, value: 1, to: startOfToday)!
        let yesterday = calendar.date(byAdding: .hour, value: -12, to: startOfToday)!

        let items = [
            item(id: "today-quiet", cwd: "/a", at: todayMorning),
            item(id: "needs", cwd: "/needs", at: yesterday),
            item(id: "yesterday-quiet", cwd: "/b", at: yesterday),
        ]

        let groups = NeedsYouOrdering.groupNeedsYouFirstThenRecency(
            items,
            needsYou: { $0.cwd == "/needs" },
            date: \.lastActivityAt,
            now: now,
            calendar: calendar
        )
        #expect(groups.map(\.title) == ["Needs you", "Today", "Yesterday"])
        #expect(groups[0].items.map(\.id) == ["needs"])
        #expect(groups[1].items.map(\.id) == ["today-quiet"])
        #expect(groups[2].items.map(\.id) == ["yesterday-quiet"])
    }

    @Test("empty attention set yields ordinary recency groups")
    func emptyAttentionFallsBack() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            item(id: "a", cwd: "/a", at: now),
        ]
        let groups = NeedsYouOrdering.groupNeedsYouFirstThenRecency(
            items,
            needsYou: { _ in false },
            date: \.lastActivityAt,
            now: now
        )
        #expect(groups.map(\.title) == ["Today"])
        #expect(!groups.map(\.title).contains("Needs you"))
    }
}
