import Testing
import Foundation
import LancerCore
@testable import AppFeature
import SessionFeature

@Suite("LiveStatusPresentation")
struct LiveStatusPresentationTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("labels match starting/thinking/streaming/tool captions")
    func labels() {
        #expect(LiveStatusPresentation.statusLabel(state: "starting", toolName: nil, target: nil) == "Starting…")
        #expect(LiveStatusPresentation.statusLabel(state: "thinking", toolName: nil, target: nil) == "Thinking…")
        #expect(LiveStatusPresentation.statusLabel(state: "streaming", toolName: nil, target: nil) == "Writing…")
        #expect(
            LiveStatusPresentation.statusLabel(
                state: "tool",
                toolName: "XcodeBuildMCP",
                target: nil
            ) == "Calling XcodeBuildMCP…"
        )
        #expect(
            LiveStatusPresentation.statusLabel(
                state: "tool",
                toolName: "Edit",
                target: "/Users/me/src/ChatUI.swift"
            ) == "Editing ChatUI.swift…"
        )
        #expect(
            LiveStatusPresentation.statusLabel(
                state: "tool",
                toolName: "Write",
                target: "Foo.swift"
            ) == "Editing Foo.swift…"
        )
    }

    @Test("elapsed suffix formats minutes and seconds")
    func elapsed() {
        #expect(LiveStatusPresentation.formatElapsed(14) == "14s")
        #expect(LiveStatusPresentation.formatElapsed(134) == "2m 14s")
        #expect(LiveStatusPresentation.formatElapsed(3661) == "1h 1m 1s")
        let labeled = LiveStatusPresentation.withElapsed(
            "Thinking…",
            from: start,
            now: start.addingTimeInterval(134)
        )
        #expect(labeled == "Thinking… · 2m 14s")
        #expect(LiveStatusPresentation.withElapsed("Thinking…", from: start, now: start) == "Thinking…")
    }

    @Test("hidden when reply text visible or terminal — mutual exclusion")
    func mutualExclusion() {
        let event = LiveRunStatusParams(runId: "r1", state: "thinking", at: "2026-07-12T00:00:00Z")
        #expect(
            LiveStatusPresentation.displayText(
                event: event,
                firstEventAt: start,
                lastEventAt: start,
                now: start.addingTimeInterval(5),
                hasVisibleReplyText: true,
                isTerminalOrIdle: false
            ) == nil
        )
        #expect(
            LiveStatusPresentation.displayText(
                event: event,
                firstEventAt: start,
                lastEventAt: start,
                now: start.addingTimeInterval(5),
                hasVisibleReplyText: false,
                isTerminalOrIdle: true
            ) == nil
        )
        #expect(
            LiveStatusPresentation.displayText(
                event: nil,
                firstEventAt: nil,
                lastEventAt: nil,
                now: start,
                hasVisibleReplyText: false,
                isTerminalOrIdle: false
            ) == nil
        )
    }

    @Test("stall after 30s without events shows Still working…")
    func stallHint() {
        let event = LiveRunStatusParams(runId: "r1", state: "tool", toolName: "Bash", target: "ls")
        let text = LiveStatusPresentation.displayText(
            event: event,
            firstEventAt: start,
            lastEventAt: start,
            now: start.addingTimeInterval(31),
            hasVisibleReplyText: false,
            isTerminalOrIdle: false
        )
        #expect(text == "Still working… · 31s")
    }

    @Test("fresh event under 30s shows state label with elapsed")
    func freshEvent() {
        let event = LiveRunStatusParams(runId: "r1", state: "starting")
        let text = LiveStatusPresentation.displayText(
            event: event,
            firstEventAt: start,
            lastEventAt: start.addingTimeInterval(10),
            now: start.addingTimeInterval(12),
            hasVisibleReplyText: false,
            isTerminalOrIdle: false
        )
        #expect(text == "Starting… · 12s")
    }
}

@Suite("LiveRunStatusParams wire")
struct LiveRunStatusParamsWireTests {
    @Test("runStatus envelope decodes daemon shape")
    func decodesDaemonShape() throws {
        let wireJSON = #"{"type":"runStatus","payload":{"runId":"run-1","state":"tool","toolName":"Edit","target":"ChatUI.swift","at":"2026-07-12T19:00:00Z"}}"#
        let env = try JSONDecoder().decode(
            E2ERelayMessage.RelayInnerEnvelope<LiveRunStatusParams>.self,
            from: Data(wireJSON.utf8)
        )
        #expect(env.type == "runStatus")
        #expect(env.payload.runId == "run-1")
        #expect(env.payload.state == "tool")
        #expect(env.payload.toolName == "Edit")
        #expect(env.payload.target == "ChatUI.swift")
        #expect(env.payload.at == "2026-07-12T19:00:00Z")
    }

    @Test("missing optional fields decode defensively")
    func missingOptionals() throws {
        let wireJSON = #"{"type":"runStatus","payload":{"runId":"r","state":"thinking"}}"#
        let env = try JSONDecoder().decode(
            E2ERelayMessage.RelayInnerEnvelope<LiveRunStatusParams>.self,
            from: Data(wireJSON.utf8)
        )
        #expect(env.payload.toolName == nil)
        #expect(env.payload.target == nil)
        #expect(env.payload.at == nil)
    }
}
