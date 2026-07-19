import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("BackgroundTasksPresentation")
struct BackgroundTasksPresentationTests {
    @Test("running Bash artifact drives pill count and shell row title")
    func runningBashArtifactDrivesPill() {
        let artifact = ChatArtifact(
            id: "toolu_bg",
            conversationID: "conv-1",
            turnID: "turn-1",
            runID: "run-1",
            kind: .tool,
            title: "Bash",
            payloadJSON: #"{"command":"sleep 40 && echo done","run_in_background":true}"#,
            status: .running,
            createdAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let rows = BackgroundTasksPresentation.rows(
            items: [],
            events: [],
            artifacts: [artifact]
        )
        #expect(rows.count == 1)
        #expect(BackgroundTasksPresentation.runningCount(in: rows) == 1)
        #expect(BackgroundTasksPresentation.pillLabel(runningCount: 1) == "1 running task")
        #expect(rows[0].title == "sleep 40 && echo done")
        #expect(rows[0].typeLabel == "Shell")
        #expect(rows[0].status == .running)
    }

    @Test("failed tool artifacts are omitted from background rows")
    func failedArtifactsOmitted() {
        let artifact = ChatArtifact(
            id: "toolu_fail",
            conversationID: "conv-1",
            turnID: "turn-1",
            runID: "run-1",
            kind: .tool,
            title: "Bash",
            payloadJSON: #"{"command":"false"}"#,
            status: .failed
        )
        let rows = BackgroundTasksPresentation.rows(
            items: [],
            events: [],
            artifacts: [artifact]
        )
        #expect(rows.isEmpty)
        #expect(BackgroundTasksPresentation.runningCount(in: rows) == 0)
    }

    /// Live bug (GAP #10 / phone 2026-07-19): FX10 mirrors a `.running` tool
    /// artifact into the pill, then the turn reaches `exited` via host status
    /// with no matching artifact done/failed update — pill stuck at "1 running
    /// task". Must clear from turn-terminal alone.
    @Test("terminal turn clears running count for still-running relay artifact")
    func terminalTurnClearsStaleRunningArtifact() {
        let artifact = ChatArtifact(
            id: "toolu_stale",
            conversationID: "conv-1",
            turnID: "turn-1",
            runID: "run-1",
            kind: .tool,
            title: "Bash",
            payloadJSON: #"{"name":"Bash","toolUseId":"toolu_stale","input":{"command":"sleep 1"}}"#,
            status: .running,
            createdAt: Date(timeIntervalSince1970: 2_000_000)
        )

        let whileRunning = BackgroundTasksPresentation.rows(
            items: [],
            events: [],
            artifacts: [artifact],
            turnIsTerminal: false
        )
        #expect(BackgroundTasksPresentation.runningCount(in: whileRunning) == 1)
        #expect(
            BackgroundTasksPresentation.pillLabel(runningCount: 1) == "1 running task"
        )

        // Turn status flipped to completed/failed (host "exited") — no new
        // artifact status mirrored. Pill must go to zero.
        let afterTerminal = BackgroundTasksPresentation.rows(
            items: [],
            events: [],
            artifacts: [artifact],
            turnIsTerminal: true
        )
        #expect(afterTerminal.count == 1)
        #expect(afterTerminal[0].status == .finished)
        #expect(BackgroundTasksPresentation.runningCount(in: afterTerminal) == 0)
        #expect(
            BackgroundTasksPresentation.pillLabel(
                runningCount: BackgroundTasksPresentation.runningCount(in: afterTerminal)
            ) == "0 running tasks"
        )
    }

    @Test("terminal turn also clears when failed host status is the only signal")
    func failedTerminalClearsRunningArtifact() {
        let artifact = ChatArtifact(
            id: "toolu_fail_turn",
            conversationID: "conv-1",
            turnID: "turn-1",
            runID: "run-1",
            kind: .tool,
            title: "Bash",
            payloadJSON: #"{"command":"true"}"#,
            status: .running
        )
        // Presentation layer only cares about turnIsTerminal (exited OR failed).
        let rows = BackgroundTasksPresentation.rows(
            items: [],
            events: [],
            artifacts: [artifact],
            turnIsTerminal: true
        )
        #expect(BackgroundTasksPresentation.runningCount(in: rows) == 0)
    }
}
