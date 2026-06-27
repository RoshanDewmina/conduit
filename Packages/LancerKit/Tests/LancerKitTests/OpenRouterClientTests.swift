import Foundation
import Testing
@testable import AgentKit

@Suite("OpenRouterClient usage parsing")
struct OpenRouterClientTests {
    @Test("parseCompletion extracts text, tokens, and cost")
    func parsesInlineCost() throws {
        let json = """
        {
          "choices": [{"message": {"content": "Hello"}}],
          "usage": {
            "prompt_tokens": 12,
            "completion_tokens": 8,
            "cost": 0.00123
          }
        }
        """.data(using: .utf8)!

        let parsed = try OpenRouterClient.parseCompletion(json)
        #expect(parsed.text == "Hello")
        #expect(parsed.tokens.inputTokens == 12)
        #expect(parsed.tokens.outputTokens == 8)
        #expect(parsed.costUSD == 0.00123)
    }

    @Test("parseCompletion handles missing cost")
    func missingCost() throws {
        let json = """
        {
          "choices": [{"message": {"content": "Hi"}}],
          "usage": {"prompt_tokens": 1, "completion_tokens": 1}
        }
        """.data(using: .utf8)!

        let parsed = try OpenRouterClient.parseCompletion(json)
        #expect(parsed.costUSD == nil)
    }

    @Test("Redactor masks OpenRouter keys")
    func redactsOpenRouterKeys() {
        let sample = "key=sk-or-v1-abcdefghijklmnopqrstuvwxyz123456"
        let (redacted, report) = Redactor.shared.redact(sample)
        #expect(!redacted.contains("sk-or-v1"))
        #expect(report.matchedPatterns.contains("OpenRouter key"))
    }
}
