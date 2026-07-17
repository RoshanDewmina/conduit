import Foundation
import Testing
@testable import AppFeature

@Suite("ToolChipGrouping")
struct ToolChipGroupingTests {
    private func chip(
        id: String,
        name: String,
        status: ToolChipItem.Status = .done,
        isError: Bool = false
    ) -> ToolChipItem {
        ToolChipItem(
            id: id,
            toolUseId: id,
            name: name,
            inputJSON: name == "Bash" || name == "Shell"
                ? #"{"command":"ls"}"#
                : #"{"file_path":"/a.swift"}"#,
            isError: isError,
            status: status
        )
    }

    @Test("single Bash call → Ran a command")
    func singleCommandTitle() {
        let chips = [chip(id: "1", name: "Bash")]
        #expect(ToolChipGrouping.collapsedTitle(for: chips) == "Ran a command")
    }

    @Test("4 consecutive Bash → Ran 4 commands")
    func fourCommandsTitle() {
        let chips = (1...4).map { chip(id: "\($0)", name: "Bash") }
        #expect(ToolChipGrouping.collapsedTitle(for: chips) == "Ran 4 commands")
    }

    @Test("mixed run (2 bash + 1 edit + 3 other) → Used 6 tools wording")
    func mixedTitle() {
        let chips = [
            chip(id: "1", name: "Bash"),
            chip(id: "2", name: "Bash"),
            chip(id: "3", name: "Edit"),
            chip(id: "4", name: "Glob"),
            chip(id: "5", name: "Grep"),
            chip(id: "6", name: "TodoWrite"),
        ]
        #expect(
            ToolChipGrouping.collapsedTitle(for: chips)
                == "Used 6 tools, ran 2 commands, edited a file"
        )
    }

    @Test("non-consecutive groups do not merge across intervening assistant prose")
    func doesNotMergeAcrossProse() {
        let items: [TurnTranscriptItem] = [
            .toolChip(chip(id: "1", name: "Bash")),
            .toolChip(chip(id: "2", name: "Bash")),
            .prose(TurnProseItem(id: "p", text: "mid-turn text")),
            .toolChip(chip(id: "3", name: "Bash")),
            .toolChip(chip(id: "4", name: "Bash")),
        ]
        let grouped = ToolChipGrouping.groupedForDisplay(items)
        #expect(grouped.count == 3)
        guard case .toolChips(let first) = grouped[0] else {
            Issue.record("expected first tool group"); return
        }
        guard case .prose = grouped[1] else {
            Issue.record("expected prose split"); return
        }
        guard case .toolChips(let second) = grouped[2] else {
            Issue.record("expected second tool group"); return
        }
        #expect(first.count == 2)
        #expect(second.count == 2)
        #expect(ToolChipGrouping.collapsedTitle(for: first) == "Ran 2 commands")
        #expect(ToolChipGrouping.collapsedTitle(for: second) == "Ran 2 commands")
    }

    @Test("WT-B: terminal turn forces running chips to done")
    func terminalTurnForcesTerminalChip() {
        let running = [
            chip(id: "1", name: "Bash", status: .running),
            chip(id: "2", name: "Edit", status: .done),
        ]
        let forced = ToolChipGrouping.withTerminalTurnStatus(running, turnIsTerminal: true)
        #expect(forced[0].status == .done)
        #expect(forced[1].status == .done)
        #expect(!forced.contains(where: { $0.status == .running }))
    }

    @Test("WT-B negative: running turn keeps running chip")
    func runningTurnKeepsRunningChip() {
        let running = [chip(id: "1", name: "Bash", status: .running)]
        let kept = ToolChipGrouping.withTerminalTurnStatus(running, turnIsTerminal: false)
        #expect(kept[0].status == .running)
    }

    @Test("duration never 0 when completedAt is after startedAt")
    func durationWhenDatesDiffer() {
        let started = Date(timeIntervalSince1970: 1_000)
        let completed = started.addingTimeInterval(34.2)
        #expect(
            ToolChipGrouping.durationSeconds(startedAt: started, completedAt: completed) == 35
        )
        let summary = TurnActivitySummary.make(
            from: [.toolChip(chip(id: "1", name: "Edit"))],
            startedAt: started,
            completedAt: completed
        )
        #expect(summary.durationSeconds == 35)
        #expect(summary.label.hasPrefix("Worked 35s"))
    }

    @Test("sub-second span still reports at least 1s")
    func subSecondDuration() {
        let started = Date(timeIntervalSince1970: 1_000)
        let completed = started.addingTimeInterval(0.4)
        #expect(
            ToolChipGrouping.durationSeconds(startedAt: started, completedAt: completed) == 1
        )
    }
}
