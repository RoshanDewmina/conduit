import Foundation
import Testing
@testable import LancerCore
@testable import SessionFeature

// MARK: - Fixtures

private let singleOptionEvent = QuestionPendingParams(
    id: "q-voice-001",
    agent: "claudeCode",
    runId: "r-test",
    questions: [
        QuestionItemWire(
            question: "Which approach should we take?",
            options: [
                QuestionOptionWire(label: "Refactor"),
                QuestionOptionWire(label: "Rewrite", description: "Full rewrite from scratch"),
                QuestionOptionWire(label: "Patch"),
            ]
        )
    ],
    allowFreeText: true,
    confidence: "complete"
)

private let strictOptionsEvent = QuestionPendingParams(
    id: "q-voice-002",
    agent: "claudeCode",
    runId: "r-test",
    questions: [
        QuestionItemWire(
            question: "Pick one.",
            options: [
                QuestionOptionWire(label: "Yes"),
                QuestionOptionWire(label: "No"),
            ]
        )
    ],
    allowFreeText: false,
    confidence: "complete"
)

private let bestEffortEvent = QuestionPendingParams(
    id: "q-voice-003",
    agent: "openai",
    runId: "r-test",
    questions: [QuestionItemWire(question: "What do you need?", options: [])],
    allowFreeText: true,
    confidence: "bestEffort"
)

private let multiItemEvent = QuestionPendingParams(
    id: "q-voice-004",
    agent: "claudeCode",
    runId: "r-test",
    questions: [
        QuestionItemWire(
            header: "Step 1",
            question: "Which files to modify?",
            options: [
                QuestionOptionWire(label: "main.swift"),
                QuestionOptionWire(label: "AppRoot.swift"),
            ]
        ),
        QuestionItemWire(question: "Any notes?", options: []),
    ],
    allowFreeText: true,
    confidence: "bestEffort"
)

private func makeState(event: QuestionPendingParams) -> QuestionCardModel.PresentationState {
    let payload = QuestionArtifactPayload(event: event)
    let data = try! JSONEncoder().encode(payload)
    let artifact = ChatArtifact(
        id: "question:\(event.id)",
        conversationID: "c-test",
        turnID: "t-test",
        runID: event.runId ?? "r-test",
        kind: .question,
        title: "Question",
        payloadJSON: String(data: data, encoding: .utf8)!,
        status: .running
    )
    return QuestionCardModel.decode(from: artifact)!
}

// MARK: - Tests

@Suite struct AnswerQuestionResolverTests {

    @Test("resolve matches spoken text to an option and builds the answer")
    func resolvesToMatchedOption() throws {
        let state = makeState(event: singleOptionEvent)
        let resolution = try #require(AnswerQuestionResolver.resolve(state: state, spokenText: "let's refactor"))
        #expect(resolution.answer.questionId == "q-voice-001")
        #expect(resolution.answer.items[0].selectedLabels == ["Refactor"])
        #expect(resolution.answer.items[0].freeText == nil)
        #expect(resolution.summary == "Refactor")
    }

    @Test("resolve falls back to free text when nothing matches and allowFreeText is true")
    func fallsBackToFreeText() throws {
        let state = makeState(event: singleOptionEvent)
        let resolution = try #require(AnswerQuestionResolver.resolve(state: state, spokenText: "Let's do something custom"))
        #expect(resolution.answer.items[0].selectedLabels == nil)
        #expect(resolution.answer.items[0].freeText == "Let's do something custom")
        #expect(resolution.summary == "Let's do something custom")
    }

    @Test("resolve returns nil when nothing matches and free text isn't allowed")
    func rejectsUnmatchedWhenFreeTextDisallowed() {
        let state = makeState(event: strictOptionsEvent)
        #expect(AnswerQuestionResolver.resolve(state: state, spokenText: "maybe, not sure") == nil)
    }

    @Test("resolve still matches an allowed option even when allowFreeText is false")
    func matchesOptionWhenFreeTextDisallowed() throws {
        let state = makeState(event: strictOptionsEvent)
        let resolution = try #require(AnswerQuestionResolver.resolve(state: state, spokenText: "yes"))
        #expect(resolution.answer.items[0].selectedLabels == ["Yes"])
    }

    @Test("resolve uses free text for an options-less (bestEffort) item")
    func bestEffortUsesFreeText() throws {
        let state = makeState(event: bestEffortEvent)
        let resolution = try #require(AnswerQuestionResolver.resolve(state: state, spokenText: "I need the API key"))
        #expect(resolution.answer.items[0].freeText == "I need the API key")
        #expect(resolution.answer.items[0].selectedLabels == nil)
    }

    @Test("resolve applies the same spoken text across every item in a multi-item question")
    func multiItemAppliesToEachItem() throws {
        let state = makeState(event: multiItemEvent)
        let resolution = try #require(AnswerQuestionResolver.resolve(state: state, spokenText: "main.swift"))
        // item 0 has a matching option; item 1 has no options, so the same
        // spoken text becomes its free text.
        #expect(resolution.answer.items[0].selectedLabels == ["main.swift"])
        #expect(resolution.answer.items[1].freeText == "main.swift")
    }

    @Test("resolve returns nil for blank spoken text")
    func rejectsBlankInput() {
        let state = makeState(event: singleOptionEvent)
        #expect(AnswerQuestionResolver.resolve(state: state, spokenText: "   ") == nil)
    }

    @Test("resolve returns nil once the question is already answered")
    func rejectsAlreadyAnswered() {
        let answer = QuestionAnswerParams(
            questionId: "q-voice-001",
            items: [QuestionItemAnswerWire(selectedLabels: ["Patch"])]
        )
        let payload = QuestionArtifactPayload(event: singleOptionEvent, answer: answer)
        let data = try! JSONEncoder().encode(payload)
        let artifact = ChatArtifact(
            id: "question:q-voice-001", conversationID: "c-test", turnID: "t-test", runID: "r-test",
            kind: .question, title: "Question", payloadJSON: String(data: data, encoding: .utf8)!, status: .done
        )
        let state = QuestionCardModel.decode(from: artifact)!
        #expect(state.isAnswered)
        #expect(AnswerQuestionResolver.resolve(state: state, spokenText: "Refactor") == nil)
    }
}
