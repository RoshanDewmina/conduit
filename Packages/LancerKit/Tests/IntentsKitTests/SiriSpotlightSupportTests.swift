#if canImport(AppIntents)
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

@Suite("SiriSpotlightSupport")
struct SiriSpotlightSupportTests {
    @Test("plain text is not flagged as forbidden")
    func plainTextIsSafe() {
        #expect(!SiriSpotlightSupport.containsForbiddenIndexMaterial("fix flaky auth tests"))
        #expect(!SiriSpotlightSupport.containsForbiddenIndexMaterial("rm -rf build"))
    }

    @Test("common secret shapes are flagged as forbidden", arguments: [
        "export API_KEY=sk-live-abc123",
        "curl -H \"Authorization: Bearer eyJhbGciOi\"",
        "set the password to hunter2",
        "here is my ssh-rsa AAAAB3NzaC1yc2E...",
        "-----BEGIN PRIVATE KEY-----",
        "rotate the apikey before shipping",
    ])
    func forbiddenShapesAreFlagged(text: String) {
        #expect(SiriSpotlightSupport.containsForbiddenIndexMaterial(text))
    }

    @Test("safeEntities filters only the entities whose indexable text trips the heuristic")
    func safeEntitiesFiltersSelectively() {
        let entities = ["fix flaky tests", "export API_KEY=sk-live-secret", "update README"]
        let filtered = SiriSpotlightSupport.safeEntities(entities, indexableText: { $0 })
        #expect(filtered == ["fix flaky tests", "update README"])
    }

    @Test("a run whose prompt embeds a secret is excluded from the indexable set")
    func runWithSecretPromptIsExcluded() async throws {
        try await IntentsKitTestFixtures.withDatabase { db in
            let repo = ChatConversationRepository(db)
            let conv = try await repo.createConversation(
                title: "Runs", agentID: "claude", hostName: "mac-studio", hostID: nil, cwd: "/repo"
            )
            _ = try await repo.appendTurn(conversationID: conv.id, prompt: "fix flaky tests", runID: "run-safe")
            _ = try await repo.appendTurn(
                conversationID: conv.id,
                prompt: "deploy using API_KEY=sk-live-should-not-be-indexed",
                runID: "run-secret"
            )

            try await IntentsKitTestFixtures.withActiveRuns(["run-safe", "run-secret"]) {
                let all = try await RunEntityQuery().suggestedEntities()
                #expect(all.count == 2)

                let indexable = SiriSpotlightSupport.safeEntities(all, indexableText: \.title)
                #expect(indexable.map(\.id) == ["run-safe"])
                #expect(!indexable.contains { $0.title.contains("API_KEY") })
            }
        }
    }

    @Test("an approval whose command embeds a secret is excluded from the indexable set")
    func approvalWithSecretCommandIsExcluded() async throws {
        try await IntentsKitTestFixtures.withDatabase { db in
            let sessionID = SessionID()
            let safeApproval = Approval(
                sessionID: sessionID, agent: .claudeCode, kind: .command,
                command: "rm -rf build", cwd: "/repo", risk: .high
            )
            let secretApproval = Approval(
                sessionID: SessionID(), agent: .claudeCode, kind: .command,
                command: "export password=hunter2", cwd: "/repo", risk: .high
            )
            try await ApprovalRepository(db).upsert(safeApproval)
            try await ApprovalRepository(db).upsert(secretApproval)

            let all = try await ApprovalEntityQuery().suggestedEntities()
            #expect(all.count == 2)

            let indexable = SiriSpotlightSupport.safeEntities(all, indexableText: \.title)
            #expect(indexable.count == 1)
            #expect(indexable[0].id == safeApproval.id.uuidString)
        }
    }
}
#endif
