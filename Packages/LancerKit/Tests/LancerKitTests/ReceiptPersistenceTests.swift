import Foundation
import Testing
@testable import LancerCore
@testable import PersistenceKit

@Suite struct ReceiptPersistenceTests {
    @Test("upsertReceipt stores a done receipt artifact linked to runID")
    func upsertReceiptPersists() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "Receipt lane",
            agentID: "claude",
            hostName: "h",
            hostID: nil,
            cwd: "/tmp/project"
        )
        _ = try await repo.appendTurn(conversationID: conv.id, prompt: "ship receipt", runID: "r-receipt-1")

        let payload = """
        {"schema":"lancer.proof/v0","runId":"r-receipt-1","conversationId":"\(conv.id)","agent":"claude","status":"completed","exitCode":0}
        """
        let conversationID = try await repo.upsertReceipt(runID: "r-receipt-1", payloadJSON: payload)

        #expect(conversationID == conv.id)
        let artifacts = try await repo.artifacts(runID: "r-receipt-1")
        #expect(artifacts.count == 1)
        #expect(artifacts.first?.kind == .receipt)
        #expect(artifacts.first?.status == .done)
        #expect(artifacts.first?.id == "receipt:r-receipt-1")
        #expect(artifacts.first?.payloadJSON.contains("lancer.proof/v0") == true)
        #expect(artifacts.first?.payloadJSON.contains("r-receipt-1") == true)
    }

    @Test("upsertReceipt is idempotent per runID")
    func upsertReceiptIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "Receipt lane",
            agentID: "claude",
            hostName: "h",
            hostID: nil,
            cwd: "/tmp/project"
        )
        _ = try await repo.appendTurn(conversationID: conv.id, prompt: "ship receipt", runID: "r-receipt-2")

        let payload = """
        {"schema":"lancer.proof/v0","runId":"r-receipt-2","conversationId":"\(conv.id)","agent":"claude","status":"completed","exitCode":0}
        """
        _ = try await repo.upsertReceipt(runID: "r-receipt-2", payloadJSON: payload)
        let updatedPayload = """
        {"schema":"lancer.proof/v0","runId":"r-receipt-2","conversationId":"\(conv.id)","agent":"claude","status":"failed","exitCode":1}
        """
        _ = try await repo.upsertReceipt(runID: "r-receipt-2", payloadJSON: updatedPayload)

        let artifacts = try await repo.artifacts(runID: "r-receipt-2")
        #expect(artifacts.count == 1)
        #expect(artifacts.first?.status == .done)
        #expect(artifacts.first?.payloadJSON.contains("\"exitCode\":1") == true)
    }

    @Test("upsertReceipt no-ops when runID is unknown")
    func upsertReceiptUnknownRun() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conversationID = try await repo.upsertReceipt(
            runID: "missing-run",
            payloadJSON: #"{"schema":"lancer.proof/v0","runId":"missing-run","conversationId":"c-1","agent":"claude","status":"completed"}"#
        )
        #expect(conversationID == nil)
        let artifacts = try await repo.artifacts(runID: "missing-run")
        #expect(artifacts.isEmpty)
    }

    @Test("receipt artifacts round-trip through decodeArtifact")
    func receiptArtifactDecode() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let conv = try await repo.createConversation(
            title: "Receipt lane",
            agentID: "claude",
            hostName: "h",
            hostID: nil,
            cwd: "/tmp/project"
        )
        _ = try await repo.appendTurn(conversationID: conv.id, prompt: "ship receipt", runID: "r-receipt-3")
        _ = try await repo.upsertReceipt(
            runID: "r-receipt-3",
            payloadJSON: #"{"schema":"lancer.proof/v0","runId":"r-receipt-3","conversationId":"c-1","agent":"claude","status":"completed"}"#
        )

        let byConversation = try await repo.artifacts(conversationID: conv.id)
        #expect(byConversation.contains(where: { $0.kind == .receipt }))
    }
}
