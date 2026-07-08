import Foundation
import Testing
@testable import LancerCore
@testable import PersistenceKit
@testable import SessionFeature

/// Verifies that question-answered state survives a full persist→reload cycle
/// through the GRDB-backed chat artifact store, mirroring ReceiptPersistenceTests.
@Suite struct QuestionPersistenceTests {

    private func makeRepo() async throws -> (AppDatabase, ChatConversationRepository, String, String) {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "Q persistence test",
            agentID: "claude",
            hostName: "h",
            hostID: nil,
            cwd: "/tmp/proj"
        )
        let turn = try await repo.appendTurn(
            conversationID: conv.id,
            prompt: "do stuff",
            runID: "r-q-1"
        )
        return (db, repo, conv.id, turn.id)
    }

    private func makePayload(
        id: String,
        answer: QuestionAnswerParams? = nil
    ) throws -> String {
        let event = QuestionPendingParams(
            id: id,
            agent: "claudeCode",
            runId: "r-q-1",
            questions: [
                QuestionItemWire(
                    question: "Pick one",
                    options: [
                        QuestionOptionWire(label: "Alpha"),
                        QuestionOptionWire(label: "Beta"),
                    ]
                )
            ],
            allowFreeText: true,
            confidence: "complete"
        )
        let payload = QuestionArtifactPayload(event: event, answer: answer)
        let data = try JSONEncoder().encode(payload)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Tests

    @Test("upsertArtifact stores a question artifact and it reloads as kind .question")
    func upsertQuestionArtifact() async throws {
        let (_, repo, convID, turnID) = try await makeRepo()
        let payloadJSON = try makePayload(id: "q-persist-1")

        let artifact = ChatArtifact(
            id: "question:q-persist-1",
            conversationID: convID,
            turnID: turnID,
            runID: "r-q-1",
            kind: .question,
            title: "Question",
            payloadJSON: payloadJSON,
            status: .running
        )
        try await repo.upsertArtifact(artifact)

        let artifacts = try await repo.artifacts(runID: "r-q-1")
        #expect(artifacts.count == 1)
        #expect(artifacts.first?.kind == .question)
        #expect(artifacts.first?.id == "question:q-persist-1")
        #expect(QuestionCardModel.isAnswered(payloadJSON: artifacts.first!.payloadJSON) == false)
    }

    @Test("answered state persists after mergeAnswer + upsertArtifact")
    func answeredStatePersists() async throws {
        let (_, repo, convID, turnID) = try await makeRepo()
        let payloadJSON = try makePayload(id: "q-persist-2")

        var artifact = ChatArtifact(
            id: "question:q-persist-2",
            conversationID: convID,
            turnID: turnID,
            runID: "r-q-1",
            kind: .question,
            title: "Question",
            payloadJSON: payloadJSON,
            status: .running
        )
        try await repo.upsertArtifact(artifact)

        // User answers — merge answer and re-persist
        let answer = QuestionAnswerParams(
            questionId: "q-persist-2",
            items: [QuestionItemAnswerWire(selectedLabels: ["Alpha"])]
        )
        let mergedJSON = try #require(QuestionCardModel.mergeAnswer(into: payloadJSON, answer: answer))
        artifact.payloadJSON = mergedJSON
        artifact.status = .done
        try await repo.upsertArtifact(artifact)

        // Reload — answered state must survive
        let reloaded = try await repo.artifacts(runID: "r-q-1")
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.kind == .question)
        #expect(reloaded.first?.status == .done)
        #expect(QuestionCardModel.isAnswered(payloadJSON: reloaded.first!.payloadJSON))

        // Full decode check
        let state = try #require(QuestionCardModel.decode(from: reloaded.first!))
        #expect(state.isAnswered)
        #expect(state.items[0].selectedLabels == ["Alpha"])
        #expect(state.submittedAnswer?.questionId == "q-persist-2")
    }

    @Test("upsertArtifact is idempotent — second write updates payload")
    func upsertIdempotent() async throws {
        let (_, repo, convID, turnID) = try await makeRepo()
        let payloadJSON = try makePayload(id: "q-persist-3")

        let artifact = ChatArtifact(
            id: "question:q-persist-3",
            conversationID: convID,
            turnID: turnID,
            runID: "r-q-1",
            kind: .question,
            title: "Question",
            payloadJSON: payloadJSON,
            status: .running
        )
        try await repo.upsertArtifact(artifact)

        let answer = QuestionAnswerParams(
            questionId: "q-persist-3",
            items: [QuestionItemAnswerWire(freeText: "Custom")]
        )
        let mergedJSON = try #require(QuestionCardModel.mergeAnswer(into: payloadJSON, answer: answer))
        var updated = artifact
        updated = ChatArtifact(
            id: artifact.id,
            conversationID: artifact.conversationID,
            turnID: artifact.turnID,
            runID: artifact.runID,
            kind: .question,
            title: artifact.title,
            payloadJSON: mergedJSON,
            status: .done
        )
        try await repo.upsertArtifact(updated)

        let artifacts = try await repo.artifacts(runID: "r-q-1")
        #expect(artifacts.count == 1)
        #expect(QuestionCardModel.isAnswered(payloadJSON: artifacts.first!.payloadJSON))
    }

    @Test("question artifacts appear in artifacts(conversationID:)")
    func artifactsByConversation() async throws {
        let (_, repo, convID, turnID) = try await makeRepo()
        let payloadJSON = try makePayload(id: "q-persist-4")

        let artifact = ChatArtifact(
            id: "question:q-persist-4",
            conversationID: convID,
            turnID: turnID,
            runID: "r-q-1",
            kind: .question,
            title: "Question",
            payloadJSON: payloadJSON,
            status: .running
        )
        try await repo.upsertArtifact(artifact)

        let byConv = try await repo.artifacts(conversationID: convID)
        #expect(byConv.contains(where: { $0.kind == .question }))
    }
}
