import Foundation
import Testing
@testable import AppFeature
@testable import LancerCore
@testable import SessionFeature

@Suite("CursorQuestionCardModel")
struct CursorQuestionCardModelTests {

    // MARK: - Wire decode (30a28e26 QuestionData → QuestionPendingParams)

    @Test("pendingParams maps questionID → id (relay wire fix)")
    func pendingParamsMapsQuestionID() {
        let wire = E2ERelayMessage.QuestionData(
            questionID: "q-wire-1",
            agent: "claudeCode",
            runId: "run-42",
            cwd: "/tmp/repo",
            questions: [
                QuestionItemWire(
                    header: "Approach",
                    question: "How should we proceed?",
                    options: [
                        QuestionOptionWire(label: "Refactor", description: "Touch up"),
                        QuestionOptionWire(label: "Rewrite", description: nil),
                    ],
                    multiSelect: false
                ),
            ],
            allowFreeText: true,
            confidence: "bestEffort"
        )

        let params = CursorQuestionCardModel.pendingParams(from: wire)
        #expect(params.id == "q-wire-1")
        #expect(params.agent == "claudeCode")
        #expect(params.runId == "run-42")
        #expect(params.cwd == "/tmp/repo")
        #expect(params.allowFreeText == true)
        #expect(params.confidence == "bestEffort")
        #expect(params.questions.count == 1)
        #expect(params.questions[0].question == "How should we proceed?")
        #expect(params.questions[0].options?.count == 2)
    }

    @Test("presentation(from:) decodes options and free-text flag")
    func presentationFromWire() throws {
        let wire = E2ERelayMessage.QuestionData(
            questionID: "q-2",
            agent: "codex",
            questions: [
                QuestionItemWire(
                    question: "Pick a model",
                    options: [
                        QuestionOptionWire(label: "Haiku"),
                        QuestionOptionWire(label: "Sonnet"),
                    ],
                    multiSelect: false
                ),
            ],
            allowFreeText: false,
            confidence: "complete"
        )

        let state = try #require(CursorQuestionCardModel.presentation(from: wire))
        #expect(state.questionID == "q-2")
        #expect(state.agent == "codex")
        #expect(state.allowFreeText == false)
        #expect(state.confidence == "complete")
        #expect(state.isAnswered == false)
        #expect(state.items.count == 1)
        #expect(state.items[0].options.map(\.label) == ["Haiku", "Sonnet"])
        #expect(CursorQuestionCardModel.shouldShowCard(state))
    }

    @Test("presentation free-text-only item is ready after setFreeText")
    func freeTextReadiness() throws {
        let wire = E2ERelayMessage.QuestionData(
            questionID: "q-ft",
            agent: "claudeCode",
            questions: [
                QuestionItemWire(question: "What else do you need?", options: nil, multiSelect: nil),
            ],
            allowFreeText: true,
            confidence: "bestEffort"
        )
        var state = try #require(CursorQuestionCardModel.presentation(from: wire))
        #expect(QuestionCardModel.isReadyToAnswer(state) == false)

        QuestionCardModel.setFreeText(in: &state, itemIndex: 0, text: "Need the logs")
        #expect(QuestionCardModel.isReadyToAnswer(state))

        let answer = QuestionCardModel.buildAnswer(from: state)
        #expect(answer.questionId == "q-ft")
        #expect(answer.items.first?.freeText == "Need the logs")
    }

    @Test("option toggle then buildAnswer resumes same question id")
    func optionToggleBuildAnswer() throws {
        let wire = E2ERelayMessage.QuestionData(
            questionID: "q-opt",
            agent: "claudeCode",
            questions: [
                QuestionItemWire(
                    question: "Ship it?",
                    options: [
                        QuestionOptionWire(label: "Yes"),
                        QuestionOptionWire(label: "No"),
                    ]
                ),
            ],
            allowFreeText: false,
            confidence: "complete"
        )
        var state = try #require(CursorQuestionCardModel.presentation(from: wire))
        QuestionCardModel.toggleOption(in: &state, itemIndex: 0, label: "Yes")
        #expect(QuestionCardModel.isReadyToAnswer(state))

        let answer = QuestionCardModel.buildAnswer(from: state)
        #expect(answer.questionId == "q-opt")
        #expect(answer.items.first?.selectedLabels == ["Yes"])
    }

    // MARK: - Card / attention view-model

    @Test("shouldShowCard is false for nil and answered states")
    func shouldShowCardGates() {
        #expect(CursorQuestionCardModel.shouldShowCard(nil) == false)

        let answered = QuestionCardModel.PresentationState(
            questionID: "q",
            agent: "a",
            confidence: "complete",
            allowFreeText: false,
            items: [],
            isAnswered: true
        )
        #expect(CursorQuestionCardModel.shouldShowCard(answered) == false)

        let pending = QuestionCardModel.PresentationState(
            questionID: "q",
            agent: "a",
            confidence: "complete",
            allowFreeText: false,
            items: [
                QuestionCardModel.ItemState(question: "Q?", options: [
                    QuestionCardModel.OptionRow(label: "A"),
                ]),
            ],
            isAnswered: false
        )
        #expect(CursorQuestionCardModel.shouldShowCard(pending))
    }

    @Test("awaitingInputDetail uses asked-of-the-agent copy")
    func awaitingInputCopy() {
        #expect(CursorQuestionCardModel.awaitingInputDetail.contains("asked of the agent"))
        #expect(CursorQuestionCardModel.awaitingInputDetail.lowercased().contains("guarantee") == false)
    }

    @Test("blockingQuestion attention reuses CursorThreadAttention reason")
    func attentionReusesBlockingQuestion() {
        let state = CursorThreadAttention.ThreadState(
            hasBlockingQuestion: true,
            statusText: CursorQuestionCardModel.awaitingInputDetail
        )
        let (attention, reason, detail) = CursorThreadAttention.derive(state)
        #expect(attention == .awaitingInput)
        #expect(reason == .blockingQuestion)
        #expect(detail == CursorQuestionCardModel.awaitingInputDetail)
    }

    @Test("shouldSuppressTranscriptArtifact only for matching unanswered pending")
    func suppressMatchingArtifact() throws {
        let wire = E2ERelayMessage.QuestionData(
            questionID: "q-same",
            agent: "claudeCode",
            questions: [QuestionItemWire(question: "Continue?")],
            allowFreeText: true,
            confidence: "bestEffort"
        )
        let pending = try #require(CursorQuestionCardModel.presentation(from: wire))
        let params = CursorQuestionCardModel.pendingParams(from: wire)
        let payloadData = try JSONEncoder().encode(QuestionArtifactPayload(event: params))
        let payloadJSON = try #require(String(data: payloadData, encoding: .utf8))
        let artifact = ChatArtifact(
            id: "question:q-same",
            conversationID: "c1",
            turnID: "t1",
            runID: "r1",
            kind: .question,
            title: "Question",
            payloadJSON: payloadJSON,
            status: .running
        )

        #expect(
            CursorQuestionCardModel.shouldSuppressTranscriptArtifact(artifact: artifact, pending: pending)
        )

        let otherWire = E2ERelayMessage.QuestionData(
            questionID: "q-other",
            agent: "claudeCode",
            questions: [QuestionItemWire(question: "Other?")],
            allowFreeText: true,
            confidence: "bestEffort"
        )
        let otherPending = try #require(CursorQuestionCardModel.presentation(from: otherWire))
        #expect(
            CursorQuestionCardModel.shouldSuppressTranscriptArtifact(artifact: artifact, pending: otherPending)
                == false
        )
        #expect(
            CursorQuestionCardModel.shouldSuppressTranscriptArtifact(artifact: artifact, pending: nil)
                == false
        )
    }
}

#if os(iOS)
@Suite("CursorShellLiveBridge pending question")
struct CursorShellLiveBridgePendingQuestionTests {

    @Test("setPendingQuestion sets hasBlockingQuestion on selected thread")
    @MainActor
    func setPendingQuestionUpdatesAttention() throws {
        let bridge = CursorShellLiveBridge()
        bridge.selectedThreadID = "conv-1"

        let wire = E2ERelayMessage.QuestionData(
            questionID: "q-bridge",
            agent: "claudeCode",
            questions: [
                QuestionItemWire(
                    question: "Approve plan?",
                    options: [QuestionOptionWire(label: "Go")]
                ),
            ],
            allowFreeText: false,
            confidence: "complete"
        )
        let state = try #require(CursorQuestionCardModel.presentation(from: wire))

        bridge.setPendingQuestion(state, machineID: UUID().uuidString, conversationID: "conv-1")
        #expect(bridge.pendingQuestion?.questionID == "q-bridge")
        #expect(bridge.threadStates["conv-1"]?.hasBlockingQuestion == true)
        #expect(bridge.threadAttention["conv-1"] == .awaitingInput)

        bridge.setPendingQuestion(nil, machineID: nil, conversationID: "conv-1")
        #expect(bridge.pendingQuestion == nil)
        #expect(bridge.threadStates["conv-1"]?.hasBlockingQuestion == false)
    }

    @Test("toggle and free-text mutate published pendingQuestion")
    @MainActor
    func mutatePendingQuestion() throws {
        let bridge = CursorShellLiveBridge()
        let wire = E2ERelayMessage.QuestionData(
            questionID: "q-mut",
            agent: "claudeCode",
            questions: [
                QuestionItemWire(
                    question: "Pick",
                    options: [
                        QuestionOptionWire(label: "A"),
                        QuestionOptionWire(label: "B"),
                    ],
                    multiSelect: false
                ),
            ],
            allowFreeText: true,
            confidence: "bestEffort"
        )
        let state = try #require(CursorQuestionCardModel.presentation(from: wire))
        bridge.setPendingQuestion(state, machineID: "m1")

        bridge.togglePendingQuestionOption(itemIndex: 0, label: "A")
        #expect(bridge.pendingQuestion?.items[0].selectedLabels == ["A"])

        bridge.setPendingQuestionFreeText(itemIndex: 0, text: "custom")
        #expect(bridge.pendingQuestion?.items[0].freeText == "custom")
    }
}
#endif
