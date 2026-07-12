import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("FlightRecorderTimeline")
struct FlightRecorderTimelineTests {
    private let conv = "conv-1"
    private let turn = "turn-1"
    private let run = "run-1"
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func event(
        seq: Int,
        kind: String,
        text: String? = nil,
        stream: String? = nil,
        payloadJSON: String? = nil,
        at offset: TimeInterval,
        turnID: String? = "turn-1",
        runID: String? = "run-1"
    ) -> ChatEvent {
        ChatEvent(
            conversationID: conv,
            seq: seq,
            turnID: turnID,
            runID: runID,
            kind: kind,
            stream: stream,
            text: text,
            payloadJSON: payloadJSON,
            createdAt: t0.addingTimeInterval(offset)
        )
    }

    @Test("full happy path: dispatch → output burst → approval → receipt → exit")
    func happyPathGroupsSteps() {
        let events = [
            event(seq: 1, kind: "turn_started", at: 0),
            event(seq: 2, kind: "output", text: "hello ", stream: "stdout", at: 1),
            event(seq: 3, kind: "output", text: "world", stream: "stdout", at: 2),
            event(
                seq: 4,
                kind: "approval",
                payloadJSON: #"{"risk":2,"decision":"approved","decidedAtOffset":5}"#,
                at: 3
            ),
            event(seq: 5, kind: "receipt", payloadJSON: #"{"schema":"lancer.proof/v0"}"#, at: 8),
            event(seq: 6, kind: "status", payloadJSON: #"{"status":"exited","exitCode":0}"#, at: 9),
        ]

        let timeline = FlightRecorderAssembler.assemble(events: events, turnID: turn)

        #expect(timeline.isIncomplete == false)
        #expect(timeline.steps.map(\.kind) == [
            .dispatch, .output, .approval, .receipt, .exit,
        ])
        #expect(timeline.steps[0].offsetFromStart == 0)
        #expect(timeline.steps[1].offsetFromStart == 1)
        #expect(timeline.steps[1].previewText == "hello world")
        #expect(timeline.steps[1].isPreviewTruncated == false)
        #expect(timeline.steps[2].risk == "2")
        #expect(timeline.steps[2].decision == "approved")
        #expect(timeline.steps[2].latency == 5)
        #expect(timeline.steps[4].title.contains("exited") || timeline.steps[4].detail?.contains("0") == true)
    }

    @Test("out-of-order seqs are sorted before grouping")
    func outOfOrderSeqs() {
        let events = [
            event(seq: 3, kind: "output", text: "b", at: 2),
            event(seq: 1, kind: "turn_started", at: 0),
            event(seq: 2, kind: "output", text: "a", at: 1),
            event(seq: 4, kind: "status", payloadJSON: #"{"status":"exited","exitCode":0}"#, at: 3),
            event(seq: 5, kind: "receipt", payloadJSON: "{}", at: 4),
        ]

        let timeline = FlightRecorderAssembler.assemble(events: events, turnID: turn)
        #expect(timeline.steps.map(\.kind) == [.dispatch, .output, .exit, .receipt])
        #expect(timeline.steps[1].previewText == "ab")
        #expect(timeline.isIncomplete == false)
    }

    @Test("missing receipt on terminal turn marks recording incomplete without fabricating")
    func missingReceiptIsIncomplete() {
        let events = [
            event(seq: 1, kind: "turn_started", at: 0),
            event(seq: 2, kind: "output", text: "partial", at: 1),
            event(seq: 3, kind: "status", payloadJSON: #"{"status":"exited","exitCode":0}"#, at: 2),
        ]

        let timeline = FlightRecorderAssembler.assemble(events: events, turnID: turn)
        #expect(timeline.isIncomplete == true)
        #expect(timeline.incompleteReason != nil)
        #expect(timeline.steps.map(\.kind) == [.dispatch, .output, .exit])
        #expect(!timeline.steps.contains(where: { $0.kind == .receipt }))
    }

    @Test("empty / older runs with no turn_started stay incomplete and invent no steps")
    func emptyAndMissingDispatch() {
        let empty = FlightRecorderAssembler.assemble(events: [], turnID: turn)
        #expect(empty.isIncomplete == true)
        #expect(empty.steps.isEmpty)

        let orphanOutput = [
            event(seq: 10, kind: "output", text: "stale chunk", at: 0, turnID: nil, runID: nil),
        ]
        let orphan = FlightRecorderAssembler.assemble(events: orphanOutput, turnID: turn)
        #expect(orphan.isIncomplete == true)
        #expect(orphan.steps.isEmpty)
    }

    @Test("output preview caps at 4KB tool-fold limit")
    func outputPreviewByteCap() {
        let big = String(repeating: "x", count: 5000)
        let events = [
            event(seq: 1, kind: "turn_started", at: 0),
            event(seq: 2, kind: "output", text: big, at: 1),
            event(seq: 3, kind: "status", payloadJSON: #"{"status":"exited"}"#, at: 2),
            event(seq: 4, kind: "receipt", payloadJSON: "{}", at: 3),
        ]
        let timeline = FlightRecorderAssembler.assemble(events: events, turnID: turn)
        let output = timeline.steps.first { $0.kind == .output }
        #expect(output?.isPreviewTruncated == true)
        #expect((output?.previewText?.utf8.count ?? 0) <= FlightRecorderAssembler.outputPreviewByteCap)
    }

    @Test("question step carries decision + latency when present")
    func questionDecisionLatency() {
        let events = [
            event(seq: 1, kind: "turn_started", at: 0),
            event(
                seq: 2,
                kind: "question",
                payloadJSON: #"{"decision":"answered","latencySeconds":12.5}"#,
                at: 2
            ),
            event(seq: 3, kind: "status", payloadJSON: #"{"status":"exited"}"#, at: 20),
            event(seq: 4, kind: "receipt", payloadJSON: "{}", at: 21),
        ]
        let timeline = FlightRecorderAssembler.assemble(events: events, turnID: turn)
        let question = timeline.steps.first { $0.kind == .question }
        #expect(question?.decision == "answered")
        #expect(question?.latency == 12.5)
    }

    @Test("tool_call / tool_result map to tool steps with tool name as title")
    func toolCallAndResultSteps() {
        let events = [
            event(seq: 1, kind: "turn_started", at: 0),
            event(
                seq: 2,
                kind: "tool_call",
                payloadJSON: #"{"name":"Edit","toolUseId":"toolu_1","input":{"file_path":"A.swift"}}"#,
                at: 1
            ),
            event(
                seq: 3,
                kind: "tool_result",
                text: "patched",
                payloadJSON: #"{"name":"Edit","toolUseId":"toolu_1","isError":false}"#,
                at: 2
            ),
            event(seq: 4, kind: "status", payloadJSON: #"{"status":"exited"}"#, at: 3),
            event(seq: 5, kind: "receipt", payloadJSON: "{}", at: 4),
        ]
        let timeline = FlightRecorderAssembler.assemble(events: events, turnID: turn)
        let toolSteps = timeline.steps.filter { $0.kind == .tool }
        #expect(toolSteps.count == 2)
        #expect(toolSteps[0].title == "Edit")
        #expect(toolSteps[1].title == "Edit result")
    }

    @Test("filters to the requested turn and ignores sibling turn events")
    func filtersByTurnID() {
        let events = [
            event(seq: 1, kind: "turn_started", at: 0, turnID: "turn-1"),
            event(seq: 2, kind: "output", text: "mine", at: 1, turnID: "turn-1"),
            event(seq: 3, kind: "turn_started", at: 2, turnID: "turn-2"),
            event(seq: 4, kind: "output", text: "theirs", at: 3, turnID: "turn-2"),
            event(seq: 5, kind: "status", payloadJSON: #"{"status":"exited"}"#, at: 4, turnID: "turn-1"),
            event(seq: 6, kind: "receipt", payloadJSON: "{}", at: 5, turnID: "turn-1"),
        ]
        let timeline = FlightRecorderAssembler.assemble(events: events, turnID: "turn-1")
        #expect(timeline.steps.map(\.kind) == [.dispatch, .output, .exit, .receipt])
        #expect(timeline.steps[1].previewText == "mine")
    }
}
