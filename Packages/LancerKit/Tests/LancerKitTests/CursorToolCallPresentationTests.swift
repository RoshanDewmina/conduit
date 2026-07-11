import Foundation
import Testing
@testable import AppFeature
@testable import LancerCore

@Suite("CursorToolCallPresentation")
struct CursorToolCallPresentationTests {
    @Test("summarizeToolInput collapses whitespace and caps at 80 chars")
    func summarizeInput() {
        let long = String(repeating: "abcdef ", count: 20)
        let summary = CursorToolCallPresentation.summarizeToolInput(long)
        #expect(summary.count <= 80)
        #expect(summary.hasSuffix("…"))
    }

    @Test("briefToolArg prefers file basename from JSON input")
    func briefArgBasename() {
        let brief = CursorToolCallPresentation.briefToolArg(#"{"file_path":"/Users/ada/app/Main.swift"}"#)
        #expect(brief == "Main.swift")
    }

    @Test("briefToolArg falls back to command preview")
    func briefArgCommand() {
        let brief = CursorToolCallPresentation.briefToolArg(#"{"command":"git status"}"#)
        #expect(brief.contains("git status"))
    }

    @Test("summarizeToolRun joins call names with middots")
    func summarizeRun() {
        let cards = [
            CursorToolCallCard(id: "1", name: "Bash", state: .completed, inputJSON: #"{"command":"ls"}"#),
            CursorToolCallCard(id: "2", name: "Edit", state: .completed, inputJSON: #"{"path":"a.swift"}"#),
        ]
        let summary = CursorToolCallPresentation.summarizeToolRun(cards)
        #expect(summary.contains("Bash"))
        #expect(summary.contains("Edit"))
        #expect(summary.contains("·"))
    }

    @Test("capResult truncates at 4000 UTF-8 bytes with ellipsis")
    func capResult() {
        let raw = String(repeating: "あ", count: 3000) // multi-byte
        let capped = CursorToolCallPresentation.capResult(raw)
        #expect(capped.utf8.count <= CursorToolCallPresentation.maxResultUTF8Count + 3)
        #expect(capped.hasSuffix("…"))
    }

    @Test("auto-expand only for small groups above collapsed preview")
    func autoExpandPolicy() {
        // Happier pattern: auto-expand only when count is in (preview, max(preview*2, 6)]
        #expect(
            CursorToolCallPresentation.shouldAutoExpandGroup(
                toolCount: 3,
                collapsedPreviewCount: 3
            ) == false
        )
        #expect(
            CursorToolCallPresentation.shouldAutoExpandGroup(
                toolCount: 5,
                collapsedPreviewCount: 3
            ) == true
        )
        #expect(
            CursorToolCallPresentation.shouldAutoExpandGroup(
                toolCount: 29,
                collapsedPreviewCount: 3
            ) == false
        )
    }

    @Test("makeGroup builds foldable presentation from cards")
    func makeGroup() {
        let cards = (1...4).map {
            CursorToolCallCard(id: "t\($0)", name: "Tool\($0)", state: .completed, inputJSON: "{}")
        }
        let group = CursorToolCallPresentation.makeGroup(
            cards: cards,
            collapsedPreviewCount: 2
        )
        #expect(group.cards.count == 4)
        #expect(group.shouldAutoExpand == true)
        #expect(!group.summaryLine.isEmpty)
    }

    @Test("cardsFromArtifacts maps ChatArtifact tool status to card state")
    func fromArtifacts() {
        let artifacts = [
            ChatArtifact(
                id: "tool-1",
                conversationID: "c",
                turnID: "turn-1",
                runID: "r1",
                kind: .tool,
                title: "Bash",
                summary: "Ran ls",
                payloadJSON: #"{"command":"ls"}"#,
                status: .done
            ),
            ChatArtifact(
                id: "tool-2",
                conversationID: "c",
                turnID: "turn-1",
                runID: "r1",
                kind: .tool,
                title: "Read",
                payloadJSON: #"{"path":"a.swift"}"#,
                status: .running
            ),
            ChatArtifact(
                id: "receipt-1",
                conversationID: "c",
                turnID: "turn-1",
                runID: "r1",
                kind: .receipt,
                title: "Proof",
                payloadJSON: "{}"
            ),
        ]
        let cards = CursorToolCallPresentation.cardsFromArtifacts(artifacts)
        #expect(cards.count == 2)
        #expect(cards[0].state == .completed)
        #expect(cards[1].state == .running)
        #expect(cards[0].name == "Bash")
    }
}

@Suite("CursorWorkingIndicator")
struct CursorWorkingIndicatorTests {
    @Test("nil when visible assistant text is present — mutual exclusivity")
    func mutualExclusivity() {
        let indicator = CursorWorkingIndicator.resolve(
            isWorking: true,
            hasVisibleText: true,
            runningToolName: "Bash",
            streamConnected: true
        )
        #expect(indicator == nil)
    }

    @Test("toolRunning wins over thinking/streaming when a tool is in flight")
    func toolRunningPrecedence() {
        let indicator = CursorWorkingIndicator.resolve(
            isWorking: true,
            hasVisibleText: false,
            runningToolName: "Bash",
            streamConnected: false
        )
        #expect(indicator == .toolRunning(name: "Bash"))
    }

    @Test("streaming when working with stream connected and no tool")
    func streaming() {
        let indicator = CursorWorkingIndicator.resolve(
            isWorking: true,
            hasVisibleText: false,
            runningToolName: nil,
            streamConnected: true
        )
        #expect(indicator == .streaming)
    }

    @Test("thinking when working without stream or tool")
    func thinking() {
        let indicator = CursorWorkingIndicator.resolve(
            isWorking: true,
            hasVisibleText: false,
            runningToolName: nil,
            streamConnected: false
        )
        #expect(indicator == .thinking)
    }

    @Test("starting when not yet working")
    func starting() {
        let indicator = CursorWorkingIndicator.resolve(
            isWorking: false,
            hasVisibleText: false,
            runningToolName: nil,
            streamConnected: false
        )
        #expect(indicator == .starting)
    }

    @Test("displayLabel matches asked-of-agent copy")
    func labels() {
        #expect(CursorWorkingIndicator.starting.displayLabel == "Starting…")
        #expect(CursorWorkingIndicator.thinking.displayLabel == "Thinking…")
        #expect(CursorWorkingIndicator.streaming.displayLabel == "Streaming…")
        #expect(CursorWorkingIndicator.toolRunning(name: "Bash").displayLabel == "Running Bash…")
    }
}
