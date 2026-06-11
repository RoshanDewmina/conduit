import Testing
import Foundation
@testable import ConduitCore

@Suite struct ApprovalParityTests {
    private func params(agent: String) -> ApprovalPendingParams {
        let json = """
        {"id":"\(UUID().uuidString)","sessionId":"\(UUID().uuidString)","agent":"\(agent)",
         "kind":"command","command":"rm -rf build/","cwd":"/repo","risk":2,
         "toolName":"Bash","toolUseID":"tu-1","agentSessionID":"as-1",
         "toolInput":"{\\"command\\":\\"rm -rf build/\\"}",
         "files":["build/"],"touchesGit":false,"touchesNetwork":false,"matchedRule":"ask-high"}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(ApprovalPendingParams.self, from: json)
    }

    @Test("Each vendor decodes to the correct AgentSource and carries structured fields")
    func vendorMapping() {
        for (raw, expected): (String, Approval.AgentSource) in [
            ("claudeCode", .claudeCode), ("codex", .codex), ("opencode", .opencode),
        ] {
            let p = params(agent: raw)
            #expect(p.approvalAgent == expected)
            #expect(p.approvalToolName == "Bash")
            #expect(p.approvalKind == .command)
            #expect(p.approvalRisk == .high)
            #expect(p.blastRadius.files == ["build/"])
            #expect(p.blastRadius.matchedRule == "ask-high")
        }
    }
}
