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
}
