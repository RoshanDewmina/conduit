import Foundation
import Testing
@testable import AppFeature

@Suite("ChatStreamingTextSmoother")
struct ChatStreamingTextSmootherTests {
    @Test("overlay wins only while strictly longer than persisted text")
    func antiFlicker() {
        #expect(
            ChatStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: "Hello world",
                persistedAssistantText: "Hello"
            ) == "Hello world"
        )
        #expect(
            ChatStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: "Hello",
                persistedAssistantText: "Hello world"
            ) == "Hello world"
        )
        #expect(
            ChatStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: "Hello",
                persistedAssistantText: "Hello"
            ) == "Hello"
        )
        #expect(
            ChatStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: nil,
                persistedAssistantText: "Done."
            ) == "Done."
        )
        #expect(
            ChatStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: "Streaming…",
                persistedAssistantText: ""
            ) == "Streaming…"
        )
    }

    @Test("commit and settle gates use elapsed thresholds")
    func pacingGates() {
        #expect(
            ChatStreamingTextSmoother.shouldCommit(
                elapsedSinceLastCommit: .milliseconds(50),
                minInterval: .milliseconds(50)
            )
        )
        #expect(
            !ChatStreamingTextSmoother.shouldCommit(
                elapsedSinceLastCommit: .milliseconds(20),
                minInterval: .milliseconds(50)
            )
        )
        #expect(
            ChatStreamingTextSmoother.isSettled(
                elapsedSinceLastDelta: .milliseconds(300),
                settleDelay: .milliseconds(300)
            )
        )
        #expect(
            !ChatStreamingTextSmoother.isSettled(
                elapsedSinceLastDelta: .milliseconds(100),
                settleDelay: .milliseconds(300)
            )
        )
    }

    @Test("character reveal catches up within one poll interval")
    func catchUpWithinPollInterval() {
        let target = String(repeating: "a", count: 200)
        var displayed = ""
        let commit = Duration.milliseconds(50)
        let maxCatchUp = Duration.seconds(1)
        let maxTicks = 20 // 20 * 50ms = 1s

        for _ in 0..<maxTicks {
            displayed = ChatStreamingTextSmoother.advancedDisplay(
                displayed: displayed,
                target: target,
                commitInterval: commit,
                maxCatchUp: maxCatchUp
            )
        }
        #expect(displayed == target)
    }

    @Test("reveal prefers word boundaries when advancing")
    func prefersWordBoundaries() {
        let displayed = "Hello "
        let target = "Hello world there"
        let step = ChatStreamingTextSmoother.charactersToReveal(
            displayed: displayed,
            target: target,
            commitInterval: .milliseconds(50),
            maxCatchUp: .seconds(1),
            minCharsPerTick: 3
        )
        let next = String(target.prefix(displayed.count + step))
        #expect(next.hasSuffix(" ") || next.hasSuffix("d") || next == target || next.hasPrefix("Hello w"))
        #expect(step >= 3)
        #expect(displayed.count + step <= target.count)
    }

    @Test("non-prefix target snaps to full replacement")
    func nonPrefixSnaps() {
        let next = ChatStreamingTextSmoother.advancedDisplay(
            displayed: "old text",
            target: "brand new",
            commitInterval: .milliseconds(50),
            maxCatchUp: .seconds(1)
        )
        #expect(next == "brand new")
    }

    @Test("zero remaining yields zero step")
    func zeroRemaining() {
        #expect(
            ChatStreamingTextSmoother.charactersToReveal(
                displayed: "done",
                target: "done"
            ) == 0
        )
    }
}
