import Foundation
import Testing
@testable import AgentKit

@Suite("ManagedModel CLI dispatch")
struct ManagedModelCLIDispatchTests {
    @Test("Claude models map to CLI aliases")
    func cliAliases() {
        #expect(ManagedModel.claudeHaiku.claudeCodeCLIAlias == "haiku")
        #expect(ManagedModel.claudeSonnet.claudeCodeCLIAlias == "sonnet")
        #expect(ManagedModel.claudeOpus.claudeCodeCLIAlias == "opus")
        #expect(ManagedModel.gpt.claudeCodeCLIAlias == nil)
    }

    @Test("normalizes legacy OpenRouter slugs for dispatch")
    func normalizeLegacySlug() {
        #expect(ManagedModel.cliDispatchSlug(for: "anthropic/claude-haiku-4") == "haiku")
        #expect(ManagedModel.cliDispatchSlug(for: "haiku") == "haiku")
    }
}
