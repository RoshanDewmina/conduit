#if os(iOS)
import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("CursorObservedSessionMapping")
struct CursorObservedSessionMappingTests {
    @Test("providerLabel maps known vendors")
    func providerLabel() {
        #expect(CursorObservedSessionMapping.RowModel.providerLabel("claudeCode") == "Claude Code")
        #expect(CursorObservedSessionMapping.RowModel.providerLabel("codex") == "Codex")
        #expect(CursorObservedSessionMapping.RowModel.providerLabel("kimi") == "Kimi")
        #expect(CursorObservedSessionMapping.RowModel.providerLabel("opencode") == "OpenCode")
    }

    @Test("repoName uses cwd basename")
    func repoNameFromCWD() {
        #expect(CursorObservedSessionMapping.RowModel.repoName(from: "/Users/dev/command-center") == "command-center")
        #expect(CursorObservedSessionMapping.RowModel.repoName(from: "") == "")
    }

    @Test("rows filters to transcriptObserved sessions only")
    func rowsFilterSource() {
        let observed = ObservedSession(
            sessionId: "s1",
            provider: "claudeCode",
            title: "Terminal session",
            cwd: "/tmp/proj",
            state: .working,
            source: .transcriptObserved,
            lastActivity: .now,
            messageCount: 3
        )
        let managed = ObservedSession(
            sessionId: "s2",
            provider: "claudeCode",
            title: "Managed",
            cwd: "/tmp/proj",
            state: .working,
            source: .providerManaged,
            lastActivity: .now,
            messageCount: 1
        )
        let rows = CursorObservedSessionMapping.RowModel.rows(from: [observed, managed])
        #expect(rows.count == 1)
        #expect(rows[0].id == "s1")
    }

    @Test("scoped limits rows to a single workspace unless All Repos")
    func scopedWorkspace() {
        let rows = [
            CursorObservedSessionMapping.RowModel(
                id: "a",
                provider: "codex",
                providerLabel: "Codex",
                title: "A",
                cwd: "/x/lancer-ios",
                repoName: "lancer-ios",
                lastActivity: .now
            ),
            CursorObservedSessionMapping.RowModel(
                id: "b",
                provider: "codex",
                providerLabel: "Codex",
                title: "B",
                cwd: "/x/other",
                repoName: "other",
                lastActivity: .now
            )
        ]
        #expect(CursorObservedSessionMapping.RowModel.scoped(rows, workspaceName: "lancer-ios").count == 1)
        #expect(CursorObservedSessionMapping.RowModel.scoped(rows, workspaceName: "All Repos").count == 2)
    }

    @Test("subtitle includes provider, repo, and relative time")
    func subtitleShape() {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let row = CursorObservedSessionMapping.RowModel(
            id: "s1",
            provider: "claudeCode",
            providerLabel: "Claude Code",
            title: "Fix bug",
            cwd: "/tmp/command-center",
            repoName: "command-center",
            lastActivity: fixedNow.addingTimeInterval(-3_600)
        )
        let subtitle = row.subtitle
        #expect(subtitle.contains("Claude Code"))
        #expect(subtitle.contains("command-center"))
        #expect(!subtitle.isEmpty)
    }
}
#endif
