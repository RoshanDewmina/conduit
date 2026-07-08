import Foundation
import Testing
@testable import LancerCore
@testable import SessionFeature

@Suite struct ReturnPacketModelTests {
    private let fixturePayload = """
    {"schema":"lancer.proof/v0","runId":"r-packet","conversationId":"c-packet","agent":"claude","status":"completed","exitCode":0,"contract":{"goal":"Ship return-to-desk packet","doneCriteria":["Packet renders","Command copies"],"validationCommands":["swift test --filter ReturnPacketModelTests"]},"criteria":[{"text":"Packet renders","status":"met"},{"text":"Command copies","status":"unmet","evidence":"UITest pending"}],"git":{"startRef":"main","endRef":"spec/j3-return-to-desk-packet","dirtyAtStart":true,"worktreePath":"/tmp/j3-worktree"},"resume":{"agent":"claude","vendorSessionId":"sess-packet-test"}}
    """

    private var fixtureReceipt: ProofReceipt {
        let data = Data(fixturePayload.utf8)
        return try! JSONDecoder().decode(ProofReceipt.self, from: data)
    }

    @Test("unmetCriteria filters to open risks only")
    func unmetCriteria() {
        let rows = ReturnPacketModel.unmetCriteria(receipt: fixtureReceipt)
        #expect(rows.count == 1)
        #expect(rows.first?.text == "Command copies")
    }

    @Test("gitBranchLabel prefers endRef over startRef")
    func gitBranchLabel() {
        #expect(ReturnPacketModel.gitBranchLabel(receipt: fixtureReceipt) == "spec/j3-return-to-desk-packet")
    }

    @Test("worktreePath prefers receipt git snapshot over thread cwd")
    func worktreePath() {
        #expect(
            ReturnPacketModel.worktreePath(
                receipt: fixtureReceipt,
                workingDirectory: "/ignored/cwd"
            ) == "/tmp/j3-worktree"
        )
        #expect(
            ReturnPacketModel.worktreePath(
                receipt: ProofReceipt(
                    runId: "r",
                    conversationId: "c",
                    agent: "claude",
                    status: "completed"
                ),
                workingDirectory: "/fallback/cwd"
            ) == "/fallback/cwd"
        )
    }

    @Test("continuationCommand builds claude --resume argv with worktree cd")
    func continuationCommandClaude() throws {
        let command = try #require(
            ReturnPacketModel.continuationCommand(
                receipt: fixtureReceipt,
                workingDirectory: "/ignored/cwd"
            )
        )
        #expect(command.contains("claude --resume sess-packet-test"))
        #expect(command.contains("/tmp/j3-worktree"))
    }

    @Test("continuationCommand builds codex resume argv")
    func continuationCommandCodex() throws {
        let receipt = ProofReceipt(
            runId: "r-codex",
            conversationId: "c-codex",
            agent: "codex",
            status: "completed",
            git: .init(worktreePath: "/repo"),
            resume: .init(agent: "codex", vendorSessionId: "sess-codex-99")
        )
        let command = try #require(ReturnPacketModel.continuationCommand(receipt: receipt))
        #expect(command.contains("codex resume sess-codex-99"))
    }

    @Test("dirtyAtStart surfaces git snapshot flag")
    func dirtyAtStart() {
        #expect(ReturnPacketModel.dirtyAtStart(receipt: fixtureReceipt) == true)
    }
}
