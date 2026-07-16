import Foundation
import Testing
@testable import AppFeature

@Suite("ChatMarkdownTableParser")
struct ChatMarkdownTableParserTests {
    @Test("parses header, separator, and body rows with alignments")
    func parsesBasicTable() {
        let md = """
        Before

        | Name | Count |
        |:----:|------:|
        | a | 1 |
        | b | 2 |

        After
        """
        let blocks = ChatMarkdownBlockParser.parse(md)
        #expect(blocks.count == 3)
        guard case .prose(let before) = blocks[0] else {
            Issue.record("expected leading prose"); return
        }
        #expect(before.contains("Before"))
        guard case .table(let table) = blocks[1] else {
            Issue.record("expected table block"); return
        }
        #expect(table.headers == ["Name", "Count"])
        #expect(table.alignments == [.center, .right])
        #expect(table.rows.count == 2)
        #expect(table.rows[0] == ["a", "1"])
        #expect(table.rows[1] == ["b", "2"])
        guard case .prose(let after) = blocks[2] else {
            Issue.record("expected trailing prose"); return
        }
        #expect(after.contains("After"))
    }

    @Test("rejects lines that look like pipes but lack a separator")
    func rejectsNonTablePipes() {
        let blocks = ChatMarkdownBlockParser.parse("Use | as a pipe character in prose")
        #expect(blocks.count == 1)
        guard case .prose = blocks[0] else {
            Issue.record("expected prose only"); return
        }
    }

    @Test("splitCells trims cells and outer pipes")
    func splitCells() {
        #expect(ChatMarkdownTableParser.splitCells("| a | b |") == ["a", "b"])
        #expect(ChatMarkdownTableParser.isSeparatorRow("| --- | :---: |"))
        #expect(!ChatMarkdownTableParser.isSeparatorRow("| a | b |"))
    }
}

@Suite("TodoPayloadParser")
struct TodoPayloadParserTests {
    @Test("parses Cursor-style TodoWrite todos array")
    func parsesTodoWritePayload() {
        let json = """
        {"todos":[{"id":"1","content":"Ship cards","status":"completed"},{"id":"2","content":"Add tests","status":"pending"}],"merge":true}
        """
        let state = TodoPayloadParser.parse(json)
        #expect(state?.totalCount == 2)
        #expect(state?.completedCount == 1)
        #expect(state?.title == "To-dos 1/2")
        #expect(state?.items[0].content == "Ship cards")
        #expect(state?.items[0].status == .completed)
        #expect(state?.items[1].status == .pending)
    }

    @Test("normalizes in_progress / cancelled aliases")
    func statusAliases() {
        let json = #"{"todos":[{"content":"A","status":"in_progress"},{"content":"B","status":"cancelled"}]}"#
        let state = TodoPayloadParser.parse(json)
        #expect(state?.items[0].status == .inProgress)
        #expect(state?.items[1].status == .cancelled)
        #expect(state?.completedCount == 1)
    }

    @Test("latestChecklist uses the last TodoWrite chip")
    func latestWins() {
        let items: [TurnTranscriptItem] = [
            .toolChip(ToolChipItem(
                id: "t1", toolUseId: "a", name: "TodoWrite",
                inputJSON: #"{"todos":[{"content":"Old","status":"pending"}]}"#
            )),
            .prose(TurnProseItem(id: "p", text: "working")),
            .toolChip(ToolChipItem(
                id: "t2", toolUseId: "b", name: "todo_write",
                inputJSON: #"{"todos":[{"content":"New","status":"completed"}]}"#
            )),
        ]
        let state = TodoPayloadParser.latestChecklist(from: items)
        #expect(state?.items.count == 1)
        #expect(state?.items[0].content == "New")
        #expect(state?.items[0].status == .completed)
        #expect(TodoPayloadParser.isTodoTool(name: "TodoWrite"))
        #expect(!TodoPayloadParser.isTodoTool(name: "Edit"))
    }

    @Test("returns nil for non-todo JSON")
    func nilOnGarbage() {
        #expect(TodoPayloadParser.parse(#"{"file_path":"/a.swift"}"#) == nil)
        #expect(TodoPayloadParser.parse(nil) == nil)
        #expect(TodoPayloadParser.parse("") == nil)
    }
}

@Suite("TurnActivitySummary")
struct TurnActivitySummaryTests {
    @Test("label aggregates edit / explore / search and diff stats")
    func labelFromAssembler() {
        let started = Date(timeIntervalSince1970: 1_000)
        let completed = started.addingTimeInterval(59)
        let items: [TurnTranscriptItem] = [
            .toolChip(ToolChipItem(
                id: "1", toolUseId: "a", name: "Edit",
                inputJSON: #"{"file_path":"/a.swift"}"#, added: 10, removed: 4
            )),
            .toolChip(ToolChipItem(
                id: "2", toolUseId: "b", name: "Write",
                inputJSON: #"{"path":"/b.swift"}"#, added: 28, removed: 34
            )),
            .toolChip(ToolChipItem(
                id: "3", toolUseId: "c", name: "Read",
                inputJSON: #"{"file_path":"/c.swift"}"#
            )),
            .toolChip(ToolChipItem(
                id: "4", toolUseId: "d", name: "Grep",
                inputJSON: #"{"pattern":"foo"}"#
            )),
            .toolChip(ToolChipItem(
                id: "5", toolUseId: "e", name: "Glob",
                inputJSON: #"{"pattern":"**/*.swift"}"#
            )),
            .toolChip(ToolChipItem(
                id: "6", toolUseId: "f", name: "Search",
                inputJSON: #"{"query":"bar"}"#
            )),
        ]
        let summary = TurnTranscriptAssembler.activitySummary(
            from: items,
            startedAt: started,
            completedAt: completed
        )
        #expect(summary.durationSeconds == 59)
        #expect(summary.editedFileCount == 2)
        #expect(summary.exploredCount == 1)
        #expect(summary.searchCount == 3)
        #expect(summary.added == 38)
        #expect(summary.removed == 38)
        #expect(summary.label == "Worked 59s · Edited 2 files · Explored 1 · 3 searches · +38 −38")
    }
}
