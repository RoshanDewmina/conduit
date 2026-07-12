import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("TurnTranscriptAssembler")
struct TurnTranscriptAssemblerTests {
    private let conv = "conv-z2"
    private let turn = "turn-z2"
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func event(
        seq: Int,
        kind: String,
        text: String? = nil,
        payloadJSON: String? = nil
    ) -> ChatEvent {
        ChatEvent(
            conversationID: conv,
            seq: seq,
            turnID: turn,
            runID: "run-z2",
            kind: kind,
            text: text,
            payloadJSON: payloadJSON,
            createdAt: t0.addingTimeInterval(TimeInterval(seq))
        )
    }

    @Test("Z1 fixture assembles ordered prose / toolChip / thinking; assistantText is prose-only")
    func assemblyFixture() {
        let events = [
            event(seq: 1, kind: "output", text: "I'll edit the file.\n"),
            event(
                seq: 2,
                kind: "tool_call",
                payloadJSON: #"{"name":"Edit","toolUseId":"toolu_1","input":{"file_path":"/Users/me/ChatUI.swift"},"added":1,"removed":5}"#
            ),
            event(
                seq: 3,
                kind: "tool_result",
                text: "ok",
                payloadJSON: #"{"toolUseId":"toolu_1","isError":false}"#
            ),
            event(seq: 4, kind: "thinking", text: "Considering edge cases…"),
            event(seq: 5, kind: "output", text: "Done."),
            event(seq: 6, kind: "status", payloadJSON: #"{"status":"exited"}"#),
            event(seq: 7, kind: "mystery_future_kind", text: "ignore me"),
        ]

        let items = TurnTranscriptAssembler.items(from: events)
        #expect(items.count == 4)

        guard case .prose(let prose1) = items[0] else {
            Issue.record("expected prose at 0"); return
        }
        #expect(prose1.text == "I'll edit the file.\n")

        guard case .toolChip(let chip) = items[1] else {
            Issue.record("expected toolChip at 1"); return
        }
        #expect(chip.name == "Edit")
        #expect(chip.toolUseId == "toolu_1")
        #expect(chip.added == 1)
        #expect(chip.removed == 5)
        #expect(chip.isError == false)
        #expect(chip.status == .done)
        #expect(chip.resultText == "ok")

        guard case .thinking(let thinking) = items[2] else {
            Issue.record("expected thinking at 2"); return
        }
        #expect(thinking.text == "Considering edge cases…")

        guard case .prose(let prose2) = items[3] else {
            Issue.record("expected prose at 3"); return
        }
        #expect(prose2.text == "Done.")

        #expect(TurnTranscriptAssembler.assistantText(from: events) == "I'll edit the file.\nDone.")
    }

    @Test("chip title derivation table — Edit / Write / Bash / Read / unknown")
    func chipTitleTable() {
        #expect(
            TurnTranscriptAssembler.chipTitle(
                name: "Edit",
                inputJSON: #"{"file_path":"/src/ChatUI.swift"}"#
            ) == "Edited ChatUI.swift"
        )
        #expect(
            TurnTranscriptAssembler.chipTitle(
                name: "Write",
                inputJSON: #"{"path":"/src/NewFile.swift"}"#
            ) == "Wrote NewFile.swift"
        )
        #expect(
            TurnTranscriptAssembler.chipTitle(
                name: "Bash",
                inputJSON: #"{"command":"ls -la"}"#
            ) == "Ran a command"
        )
        #expect(
            TurnTranscriptAssembler.chipTitle(
                name: "Read",
                inputJSON: #"{"file_path":"/a/b/Foo.swift"}"#
            ) == "Read Foo.swift"
        )
        #expect(
            TurnTranscriptAssembler.chipTitle(name: "Glob", inputJSON: #"{"pattern":"**/*.swift"}"#)
                == "Glob"
        )
    }

    @Test("consecutive tool chips group; all-Read → Read N files")
    func grouping() {
        let chips = [
            ToolChipItem(
                id: "1", toolUseId: "a", name: "Read",
                inputJSON: #"{"file_path":"/a.swift"}"#, added: 0, removed: 0
            ),
            ToolChipItem(
                id: "2", toolUseId: "b", name: "Edit",
                inputJSON: #"{"file_path":"/b.swift"}"#, added: 0, removed: 6
            ),
        ]
        #expect(
            TurnTranscriptAssembler.groupedChipTitle(chips)
                == "Read a file, edited a file"
        )
        #expect(TurnTranscriptAssembler.aggregatedDiff(chips: chips)?.removed == 6)

        let reads = [
            ToolChipItem(id: "1", toolUseId: "a", name: "Read", inputJSON: #"{"file_path":"/a.swift"}"#),
            ToolChipItem(id: "2", toolUseId: "b", name: "Read", inputJSON: #"{"file_path":"/b.swift"}"#),
            ToolChipItem(id: "3", toolUseId: "c", name: "Read", inputJSON: #"{"file_path":"/c.swift"}"#),
        ]
        #expect(TurnTranscriptAssembler.groupedChipTitle(reads) == "Read 3 files")

        let items: [TurnTranscriptItem] = [
            .prose(TurnProseItem(id: "p", text: "hi")),
            .toolChip(chips[0]),
            .toolChip(chips[1]),
            .thinking(TurnThinkingItem(id: "t", text: "hmm")),
        ]
        let grouped = TurnTranscriptAssembler.groupedForDisplay(items)
        #expect(grouped.count == 3)
        guard case .toolChips(let group) = grouped[1] else {
            Issue.record("expected tool chip group"); return
        }
        #expect(group.count == 2)
    }

    @Test("thinking is collapsed by default")
    func thinkingCollapseDefault() {
        #expect(ThinkingPresentation.isExpandedByDefault == false)
        #expect(ThinkingPresentation.collapsedCaption == "Thinking…")
    }

    @Test("scroll policy matches Orca 48pt near-bottom threshold")
    func scrollPolicy() {
        #expect(ChatScrollPolicy.nearBottomThreshold == 48)
        #expect(ChatScrollPolicy.isNearBottom(distanceFromBottom: 48))
        #expect(ChatScrollPolicy.isNearBottom(distanceFromBottom: 10))
        #expect(!ChatScrollPolicy.isNearBottom(distanceFromBottom: 49))
        #expect(ChatScrollPolicy.shouldShowJumpToLatest(distanceFromBottom: 49))
        #expect(!ChatScrollPolicy.shouldShowJumpToLatest(distanceFromBottom: 0))
    }
}
