import Foundation
import Testing
@testable import LancerCore
@testable import SessionFeature

// MARK: - Fixtures

private let singleOptionEvent = QuestionPendingParams(
    id: "q-001",
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

private let multiItemEvent = QuestionPendingParams(
    id: "q-002",
    agent: "claudeCode",
    runId: "r-test",
    questions: [
        QuestionItemWire(
            header: "Step 1",
            question: "Which files to modify?",
            options: [
                QuestionOptionWire(label: "main.swift"),
                QuestionOptionWire(label: "AppRoot.swift"),
            ],
            multiSelect: true
        ),
        QuestionItemWire(
            question: "Any notes?",
            options: []
        ),
    ],
    allowFreeText: true,
    confidence: "bestEffort"
)

private func makeArtifact(event: QuestionPendingParams, answer: QuestionAnswerParams? = nil) -> ChatArtifact {
    let payload = QuestionArtifactPayload(event: event, answer: answer)
    let data = try! JSONEncoder().encode(payload)
    return ChatArtifact(
        id: "question:\(event.id)",
        conversationID: "c-test",
        turnID: "t-test",
        runID: event.runId ?? "r-test",
        kind: .question,
        title: "Question",
        payloadJSON: String(data: data, encoding: .utf8)!,
        status: .running
    )
}

// MARK: - Tests

@Suite struct QuestionCardModelTests {

    // MARK: Decode – pending

    @Test("decode returns PresentationState for valid question artifact")
    func decodePending() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        let state = try #require(QuestionCardModel.decode(from: artifact))
        #expect(state.questionID == "q-001")
        #expect(state.agent == "claudeCode")
        #expect(state.confidence == "complete")
        #expect(state.allowFreeText == true)
        #expect(state.isAnswered == false)
        #expect(state.items.count == 1)
        #expect(state.items[0].options.count == 3)
        #expect(state.items[0].question == "Which approach should we take?")
    }

    @Test("decode returns nil for non-question artifact kind")
    func decodeWrongKind() {
        let artifact = ChatArtifact(
            conversationID: "c", turnID: "t", runID: "r",
            kind: .receipt, title: "Proof", payloadJSON: "{}", status: .done
        )
        #expect(QuestionCardModel.decode(from: artifact) == nil)
    }

    @Test("decode returns nil for malformed payloadJSON")
    func decodeMalformed() {
        let artifact = ChatArtifact(
            conversationID: "c", turnID: "t", runID: "r",
            kind: .question, title: "Question", payloadJSON: "not json", status: .running
        )
        #expect(QuestionCardModel.decode(from: artifact) == nil)
    }

    // MARK: Decode – answered

    @Test("decode reflects answered state when answer is present")
    func decodeAnswered() throws {
        let answer = QuestionAnswerParams(
            questionId: "q-001",
            items: [QuestionItemAnswerWire(selectedLabels: ["Refactor"])]
        )
        let artifact = makeArtifact(event: singleOptionEvent, answer: answer)
        let state = try #require(QuestionCardModel.decode(from: artifact))
        #expect(state.isAnswered == true)
        #expect(state.submittedAnswer?.questionId == "q-001")
        #expect(state.items[0].selectedLabels == ["Refactor"])
    }

    @Test("decode restores free text from answered state")
    func decodeAnsweredFreeText() throws {
        let answer = QuestionAnswerParams(
            questionId: "q-001",
            items: [QuestionItemAnswerWire(selectedLabels: nil, freeText: "Custom answer")]
        )
        let artifact = makeArtifact(event: singleOptionEvent, answer: answer)
        let state = try #require(QuestionCardModel.decode(from: artifact))
        #expect(state.isAnswered == true)
        #expect(state.items[0].freeText == "Custom answer")
    }

    // MARK: toggleOption – single select

    @Test("toggleOption single-select replaces current selection")
    func toggleOptionSingleSelect() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))

        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "Refactor")
        #expect(state.items[0].selectedLabels == ["Refactor"])

        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "Rewrite")
        #expect(state.items[0].selectedLabels == ["Rewrite"])
    }

    @Test("toggleOption single-select deselects when tapping the same option")
    func toggleOptionSingleSelectDeselects() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))

        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "Patch")
        #expect(state.items[0].selectedLabels == ["Patch"])

        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "Patch")
        #expect(state.items[0].selectedLabels == [])
    }

    // MARK: toggleOption – multi select

    @Test("toggleOption multi-select adds multiple labels")
    func toggleOptionMultiSelect() throws {
        let artifact = makeArtifact(event: multiItemEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))

        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "main.swift")
        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "AppRoot.swift")
        #expect(state.items[0].selectedLabels.contains("main.swift"))
        #expect(state.items[0].selectedLabels.contains("AppRoot.swift"))
        #expect(state.items[0].selectedLabels.count == 2)
    }

    @Test("toggleOption multi-select removes an already-selected label")
    func toggleOptionMultiSelectRemoves() throws {
        let artifact = makeArtifact(event: multiItemEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))

        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "main.swift")
        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "AppRoot.swift")
        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "main.swift")
        #expect(state.items[0].selectedLabels == ["AppRoot.swift"])
    }

    // MARK: setFreeText

    @Test("setFreeText updates the item's freeText field")
    func setFreeText() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))

        QuestionCardModel.setFreeText(in: &state, itemIndex: 0, text: "My custom answer")
        #expect(state.items[0].freeText == "My custom answer")
    }

    // MARK: isReadyToAnswer

    @Test("isReadyToAnswer is false when nothing is selected")
    func notReadyEmpty() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        let state = try #require(QuestionCardModel.decode(from: artifact))
        #expect(QuestionCardModel.isReadyToAnswer(state) == false)
    }

    @Test("isReadyToAnswer is true once an option is selected")
    func readyAfterOptionSelected() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))
        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "Refactor")
        #expect(QuestionCardModel.isReadyToAnswer(state))
    }

    @Test("isReadyToAnswer is true when allowFreeText and text is non-empty")
    func readyViaFreeTextWithOptions() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))
        QuestionCardModel.setFreeText(in: &state, itemIndex: 0, text: "My custom")
        #expect(QuestionCardModel.isReadyToAnswer(state))
    }

    @Test("isReadyToAnswer is false for blank free text")
    func notReadyBlankFreeText() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))
        QuestionCardModel.setFreeText(in: &state, itemIndex: 0, text: "   ")
        #expect(QuestionCardModel.isReadyToAnswer(state) == false)
    }

    @Test("isReadyToAnswer for options-less (bestEffort) item requires free text")
    func bestEffortFreeTextRequired() throws {
        let bestEffortEvent = QuestionPendingParams(
            id: "q-be",
            agent: "openai",
            questions: [QuestionItemWire(question: "What do you need?", options: [])],
            allowFreeText: true,
            confidence: "bestEffort"
        )
        let artifact = makeArtifact(event: bestEffortEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))
        #expect(QuestionCardModel.isReadyToAnswer(state) == false)

        QuestionCardModel.setFreeText(in: &state, itemIndex: 0, text: "I need X")
        #expect(QuestionCardModel.isReadyToAnswer(state))
    }

    @Test("isReadyToAnswer requires all items answered")
    func allItemsRequired() throws {
        let artifact = makeArtifact(event: multiItemEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))

        // item[0] is multi-select with options, item[1] is free-text only
        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "main.swift")
        #expect(QuestionCardModel.isReadyToAnswer(state) == false, "Item 1 free text still empty")

        QuestionCardModel.setFreeText(in: &state, itemIndex: 1, text: "Some notes")
        #expect(QuestionCardModel.isReadyToAnswer(state))
    }

    @Test("isReadyToAnswer returns false once already answered")
    func notReadyWhenAlreadyAnswered() throws {
        let answer = QuestionAnswerParams(
            questionId: "q-001",
            items: [QuestionItemAnswerWire(selectedLabels: ["Refactor"])]
        )
        let artifact = makeArtifact(event: singleOptionEvent, answer: answer)
        let state = try #require(QuestionCardModel.decode(from: artifact))
        #expect(state.isAnswered)
        #expect(QuestionCardModel.isReadyToAnswer(state) == false)
    }

    // MARK: buildAnswer

    @Test("buildAnswer builds QuestionAnswerParams from selected options")
    func buildAnswerOptions() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))
        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "Refactor")

        let answer = QuestionCardModel.buildAnswer(from: state)
        #expect(answer.questionId == "q-001")
        #expect(answer.items.count == 1)
        #expect(answer.items[0].selectedLabels == ["Refactor"])
        #expect(answer.items[0].freeText == nil)
    }

    @Test("buildAnswer builds QuestionAnswerParams from free text")
    func buildAnswerFreeText() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        var state = try #require(QuestionCardModel.decode(from: artifact))
        QuestionCardModel.setFreeText(in: &state, itemIndex: 0, text: "  Custom answer  ")

        let answer = QuestionCardModel.buildAnswer(from: state)
        #expect(answer.items[0].freeText == "Custom answer")
        #expect(answer.items[0].selectedLabels == nil)
    }

    // MARK: mergeAnswer / isAnswered / persistence round-trip

    @Test("mergeAnswer stamps answer into payloadJSON")
    func mergeAnswer() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        let answer = QuestionAnswerParams(
            questionId: "q-001",
            items: [QuestionItemAnswerWire(selectedLabels: ["Rewrite"])]
        )
        let merged = try #require(QuestionCardModel.mergeAnswer(into: artifact.payloadJSON, answer: answer))
        #expect(QuestionCardModel.isAnswered(payloadJSON: merged))
        #expect(QuestionCardModel.isAnswered(payloadJSON: artifact.payloadJSON) == false)
    }

    @Test("mergeAnswer payload round-trips through QuestionCardModel.decode")
    func mergeAnswerRoundTrip() throws {
        let artifact = makeArtifact(event: singleOptionEvent)
        let answer = QuestionAnswerParams(
            questionId: "q-001",
            items: [QuestionItemAnswerWire(selectedLabels: ["Patch"], freeText: nil)]
        )
        let mergedJSON = try #require(QuestionCardModel.mergeAnswer(into: artifact.payloadJSON, answer: answer))
        let updated = ChatArtifact(
            id: artifact.id,
            conversationID: artifact.conversationID,
            turnID: artifact.turnID,
            runID: artifact.runID,
            kind: .question,
            title: artifact.title,
            payloadJSON: mergedJSON,
            status: .done
        )
        let state = try #require(QuestionCardModel.decode(from: updated))
        #expect(state.isAnswered)
        #expect(state.submittedAnswer?.questionId == "q-001")
        #expect(state.items[0].selectedLabels == ["Patch"])
    }

    // MARK: Confidence caption

    @Test("confidenceCaption maps complete and bestEffort correctly")
    func confidenceCaption() {
        #expect(QuestionCardModel.confidenceCaption("complete") == "Complete")
        #expect(QuestionCardModel.confidenceCaption("bestEffort") == "Best effort")
        #expect(QuestionCardModel.confidenceCaption(nil) == nil)
        #expect(QuestionCardModel.confidenceCaption("unknown") == nil)
    }

    // MARK: DaemonEvent decoding

    @Test("DaemonEvent decodes agent.question.pending from wire JSON")
    func daemonEventDecode() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "method": "agent.question.pending",
            "params": {
                "id": "q-wire-001",
                "agent": "claudeCode",
                "runId": "r-wire",
                "timestamp": "2026-07-08T00:00:00Z",
                "questions": [
                    {
                        "question": "Which strategy?",
                        "options": [{"label": "A"}, {"label": "B"}],
                        "multiSelect": false
                    }
                ],
                "allowFreeText": true,
                "confidence": "complete"
            }
        }
        """.data(using: .utf8)!

        let event = try #require(DaemonEvent.decode(from: json))
        guard case .questionPending(let params) = event else {
            Issue.record("Expected .questionPending, got \(event)")
            return
        }
        #expect(params.id == "q-wire-001")
        #expect(params.agent == "claudeCode")
        #expect(params.questions.count == 1)
        #expect(params.questions[0].options?.first?.label == "A")
        #expect(params.allowFreeText == true)
        #expect(params.confidence == "complete")
    }

    // MARK: answeredSummary

    @Test("answeredSummary shows selected labels joined by comma")
    func answeredSummaryLabels() {
        let item = QuestionCardModel.ItemState(
            question: "Q?",
            options: [.init(label: "A"), .init(label: "B")],
            selectedLabels: ["A", "B"]
        )
        #expect(QuestionCardModel.answeredSummary(for: item) == "A, B")
    }

    @Test("answeredSummary shows free text when no labels selected")
    func answeredSummaryFreeText() {
        let item = QuestionCardModel.ItemState(
            question: "Q?",
            options: [],
            freeText: "My answer"
        )
        #expect(QuestionCardModel.answeredSummary(for: item) == "My answer")
    }
}
