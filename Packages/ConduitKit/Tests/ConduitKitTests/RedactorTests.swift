import Testing
@testable import AgentKit

@Suite("Redactor")
struct RedactorTests {

    @Test("AWS key is redacted")
    func awsKey() {
        let (redacted, report) = Redactor.shared.redact("key: AKIAIOSFODNN7EXAMPLE123")
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("AKIA"))
        #expect(report.redactedCount == 1)
    }

    @Test("GitHub token is redacted")
    func githubToken() {
        let (redacted, report) = Redactor.shared.redact("token=ghp_abcdef1234567890ABCDEF1234567890")
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("ghp_"))
        #expect(report.redactedCount == 1)
    }

    @Test("OpenAI key is redacted")
    func openAIKey() {
        let (redacted, report) = Redactor.shared.redact("OPENAI_KEY=sk-abcdefghijklmnopqrstuvwxyz1234567890")
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("sk-"))
        #expect(report.redactedCount == 1)
    }

    @Test("GitHub server token is redacted")
    func githubServerToken() {
        let (redacted, report) = Redactor.shared.redact("auth: ghs_ABC123def456GHI789")
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("ghs_"))
        #expect(report.redactedCount == 1)
    }

    @Test("clean text passes through unchanged")
    func cleanText() {
        let (redacted, report) = Redactor.shared.redact("echo hello world")
        #expect(redacted == "echo hello world")
        #expect(report.redactedCount == 0)
        #expect(report.matchedPatterns.isEmpty)
    }

    @Test("report counts match number of redactions")
    func reportCount() {
        let input = "key1=AKIAIOSFODNN7EXAMPLE123 key2=AKIAIOSFODNN7EXAMPLE456"
        let (_, report) = Redactor.shared.redact(input)
        #expect(report.redactedCount == 2)
        #expect(report.matchedPatterns.contains("AWS key"))
    }

    @Test("multiple different secret types are all redacted")
    func multipleTypes() {
        let input = """
        AWS: AKIAIOSFODNN7EXAMPLE123
        GitHub: ghp_TestToken1234567890ABC
        OpenAI: sk-TestKeyABCDEFGHIJKLMNOPQRSTUV
        """
        let (redacted, report) = Redactor.shared.redact(input)
        #expect(!redacted.contains("AKIA"))
        #expect(!redacted.contains("ghp_"))
        #expect(!redacted.contains("sk-Test"))
        #expect(report.redactedCount == 3)
    }

    @Test("extra patterns are applied")
    func extraPatterns() {
        let (redacted, report) = Redactor.shared.redact(
            "password: supersecret123",
            extraPatterns: [#"supersecret\d+"#]
        )
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("supersecret123"))
        #expect(report.redactedCount == 1)
    }
}
