import Testing
import LancerCore
@testable import AppFeature

@Suite("LiveThreadTranscript")
struct LiveThreadTranscriptTests {
    private func turn(
        id: String,
        ordinal: Int,
        prompt: String,
        status: ChatTurn.Status,
        assistantText: String = ""
    ) -> ChatTurn {
        ChatTurn(
            id: id,
            conversationID: "conv-1",
            ordinal: ordinal,
            prompt: prompt,
            runID: "run-\(id)",
            status: status,
            assistantText: assistantText
        )
    }

    @Test("priorTurns keeps completed history when a later turn is live")
    func priorKeepsHistory() {
        let first = turn(id: "t0", ordinal: 0, prompt: "12 facts", status: .completed, assistantText: "one two…")
        let second = turn(id: "t1", ordinal: 1, prompt: "FOLLOWUP-OK", status: .completed, assistantText: "ok")
        let priors = LiveThreadTranscript.priorTurns(turns: [first, second], liveTurnID: "t1")
        #expect(priors.map(\.id) == ["t0"])
        #expect(priors.first?.assistantText == "one two…")
    }

    @Test("priorTurns drops trailing running turn when liveTurnID is nil")
    func priorDropsRunningTail() {
        let first = turn(id: "t0", ordinal: 0, prompt: "hi", status: .completed, assistantText: "hello")
        let running = turn(id: "t1", ordinal: 1, prompt: "more", status: .running)
        let priors = LiveThreadTranscript.priorTurns(turns: [first, running], liveTurnID: nil)
        #expect(priors.map(\.id) == ["t0"])
        #expect(LiveThreadTranscript.liveTurn(turns: [first, running], liveTurnID: nil)?.id == "t1")
    }

    @Test("all completed turns are prior when nothing is live")
    func allPriorWhenIdle() {
        let first = turn(id: "t0", ordinal: 0, prompt: "a", status: .completed, assistantText: "A")
        let second = turn(id: "t1", ordinal: 1, prompt: "b", status: .completed, assistantText: "B")
        let priors = LiveThreadTranscript.priorTurns(turns: [first, second], liveTurnID: nil)
        #expect(priors.map(\.id) == ["t0", "t1"])
        #expect(LiveThreadTranscript.liveTurn(turns: [first, second], liveTurnID: nil) == nil)
    }

    @Test("liveTurn resolves by id")
    func liveByID() {
        let first = turn(id: "t0", ordinal: 0, prompt: "a", status: .completed, assistantText: "A")
        let live = turn(id: "t1", ordinal: 1, prompt: "b", status: .running, assistantText: "partial")
        #expect(LiveThreadTranscript.liveTurn(turns: [first, live], liveTurnID: "t1")?.assistantText == "partial")
        #expect(LiveThreadTranscript.priorTurns(turns: [first, live], liveTurnID: "t1").map(\.id) == ["t0"])
    }
}
