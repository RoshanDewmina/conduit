import Foundation
import Testing
@testable import AppFeature
@testable import LancerCore

@Suite("CursorTranscriptMapper")
struct CursorTranscriptMapperTests {
    private let conversationID = "conv-test"

    private func turn(
        id: String,
        ordinal: Int,
        prompt: String,
        assistantText: String = "",
        status: ChatTurn.Status = .completed,
        errorMessage: String? = nil,
        runID: String? = nil
    ) -> ChatTurn {
        ChatTurn(
            id: id,
            conversationID: conversationID,
            ordinal: ordinal,
            prompt: prompt,
            runID: runID ?? "run-\(id)",
            status: status,
            assistantText: assistantText,
            errorMessage: errorMessage
        )
    }

    @Test("maps turns oldest to newest with prompt and assistant text")
    func turnMapping() {
        let turns = [
            turn(id: "t1", ordinal: 0, prompt: "Hi", assistantText: "Hello"),
            turn(id: "t2", ordinal: 1, prompt: "Thanks", assistantText: "You're welcome"),
        ]
        let rows = CursorTranscriptMapper.makeRows(
            turns: turns,
            artifacts: [],
            liveOverlay: nil,
            bridgeError: nil
        )
        #expect(rows.count == 2)
        guard case .turnSection(let first) = rows[0] else {
            Issue.record("Expected turn section")
            return
        }
        #expect(first.prompt == "Hi")
        #expect(first.assistantText == "Hello")
        guard case .turnSection(let second) = rows[1] else {
            Issue.record("Expected turn section")
            return
        }
        #expect(second.prompt == "Thanks")
    }

    @Test("failed turn keeps prior turns and surfaces turn error")
    func errorRowPreservesHistory() {
        let turns = [
            turn(id: "t1", ordinal: 0, prompt: "Create file", assistantText: "Done."),
            turn(id: "t2", ordinal: 1, prompt: "Thank you", status: .failed, errorMessage: "Conversation changed."),
        ]
        let rows = CursorTranscriptMapper.makeRows(
            turns: turns,
            artifacts: [],
            liveOverlay: nil,
            bridgeError: nil
        )
        #expect(rows.count == 2)
        guard case .turnSection(let first) = rows[0] else {
            Issue.record("Expected first turn")
            return
        }
        #expect(first.assistantText == "Done.")
        guard case .turnSection(let second) = rows[1] else {
            Issue.record("Expected second turn")
            return
        }
        #expect(second.turnError == "Conversation changed.")
    }

    @Test("bridge error appends banner without removing prior turns")
    func bridgeErrorBannerPreservesHistory() {
        let turns = [
            turn(id: "t1", ordinal: 0, prompt: "Hi", assistantText: "Hello"),
        ]
        let rows = CursorTranscriptMapper.makeRows(
            turns: turns,
            artifacts: [],
            liveOverlay: nil,
            bridgeError: "Run failed with exit code 1"
        )
        #expect(rows.count == 2)
        guard case .turnSection = rows[0] else {
            Issue.record("Expected turn section first")
            return
        }
        guard case .bridgeErrorBanner(let message) = rows[1] else {
            Issue.record("Expected bridge error banner")
            return
        }
        #expect(message == "Run failed with exit code 1")
    }

    @Test("live overlay attaches only to the last turn when active")
    func liveOverlayOnLastTurn() {
        let turns = [
            turn(id: "t1", ordinal: 0, prompt: "First", assistantText: "Frozen"),
            turn(id: "t2", ordinal: 1, prompt: "Second", assistantText: ""),
        ]
        let overlay = CursorTranscriptMapper.LiveOverlayInput(
            isActive: true,
            prompt: "Second",
            response: "Streaming…",
            isWorking: true
        )
        let rows = CursorTranscriptMapper.makeRows(
            turns: turns,
            artifacts: [],
            liveOverlay: overlay,
            bridgeError: nil
        )
        guard case .turnSection(let first) = rows[0] else {
            Issue.record("Expected first turn")
            return
        }
        #expect(first.liveOverlay == nil)
        guard case .turnSection(let last) = rows[1] else {
            Issue.record("Expected last turn")
            return
        }
        #expect(last.liveOverlay?.response == "Streaming…")
        #expect(last.liveOverlay?.isWorking == true)
    }

    @Test("artifacts interleave on matching turnID")
    func artifactInterleave() {
        let turns = [turn(id: "t1", ordinal: 0, prompt: "Run", assistantText: "ok", runID: "r1")]
        let artifact = ChatArtifact(
            conversationID: conversationID,
            turnID: "t1",
            runID: "r1",
            kind: .receipt,
            title: "Receipt",
            payloadJSON: "{}"
        )
        let rows = CursorTranscriptMapper.makeRows(
            turns: turns,
            artifacts: [artifact],
            liveOverlay: nil,
            bridgeError: nil
        )
        guard case .turnSection(let section) = rows[0] else {
            Issue.record("Expected turn section")
            return
        }
        #expect(section.artifacts.count == 1)
        #expect(section.artifacts[0].id == artifact.id)
    }

    @Test("live overlay input nil when thread is not active")
    func liveOverlayInactive() {
        let overlay = CursorTranscriptMapper.liveOverlayInput(
            isRoutedThreadActive: false,
            prompt: "Hi",
            response: "text",
            isWorking: true
        )
        #expect(overlay == nil)
    }

    @Test("mirrored failed turn with vendor errorMessage renders error row")
    func mirroredFailedTurnVendorError() {
        let turns = [
            turn(
                id: "t1",
                ordinal: 0,
                prompt: "Run agent",
                status: .failed,
                errorMessage: "Credit balance is too low"
            ),
        ]
        let rows = CursorTranscriptMapper.makeRows(
            turns: turns,
            artifacts: [],
            liveOverlay: nil,
            bridgeError: nil
        )
        guard case .turnSection(let section) = rows[0] else {
            Issue.record("Expected turn section")
            return
        }
        #expect(section.turnError == "Credit balance is too low")
    }

    @Test("completed turn stops working overlay on last row")
    func completedTurnStopsWorkingOverlay() {
        let turns = [
            turn(id: "t1", ordinal: 0, prompt: "Hi", assistantText: "Done.", status: .completed),
        ]
        let overlay = CursorTranscriptMapper.LiveOverlayInput(
            isActive: true,
            prompt: "Hi",
            response: "Done.",
            isWorking: false
        )
        let rows = CursorTranscriptMapper.makeRows(
            turns: turns,
            artifacts: [],
            liveOverlay: overlay,
            bridgeError: nil
        )
        guard case .turnSection(let section) = rows[0] else {
            Issue.record("Expected turn section")
            return
        }
        #expect(section.liveOverlay?.isWorking == false)
        #expect(section.liveOverlay?.response == "Done.")
    }
}
