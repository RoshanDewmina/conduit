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

    // MARK: - WS-8 regression: Anthropic key redaction

    @Test("Anthropic key is redacted by specific pattern")
    func anthropicKey() {
        let key = "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh1234567890-ABCDEFGHIJ"
        let (redacted, report) = Redactor.shared.redact("ANTHROPIC_API_KEY=\(key)")
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("sk-ant-"), "Anthropic key prefix must be redacted")
        #expect(report.matchedPatterns.contains("Anthropic key"),
                "Should be named 'Anthropic key', got: \(report.matchedPatterns)")
    }

    @Test("Anthropic key is still redacted by fallback sk- pattern if specific pattern changes")
    func anthropicKeyFallback() {
        // A simulated short-form sk-ant key — still caught by the sk- generic pattern
        let (redacted, _) = Redactor.shared.redact("key=sk-ant-AAABBBCCCDDDEEEFFFGGG")
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("sk-ant-"))
    }

    // MARK: - LOW-5 regression: PEM blobs and Bearer/JWT tokens

    @Test("OpenSSH PEM private key block is redacted")
    func pemPrivateKeyOpenSSH() {
        let pem = """
        -----BEGIN OPENSSH PRIVATE KEY-----
        b3BlbnNzaC1rZXktdjEAAAAA...AAAAAAAAABBBBBBBBBB
        -----END OPENSSH PRIVATE KEY-----
        """
        let (redacted, report) = Redactor.shared.redact(pem)
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("BEGIN OPENSSH PRIVATE KEY"))
        #expect(!redacted.contains("END OPENSSH PRIVATE KEY"))
        #expect(report.matchedPatterns.contains("PEM private key"))
    }

    @Test("RSA PEM private key block is redacted")
    func pemPrivateKeyRSA() {
        let pem = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEpAIBAAKCAQEA1234567890abcdefghijklmnopqrstuvwxyz
        ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890+/==
        -----END RSA PRIVATE KEY-----
        """
        let (redacted, report) = Redactor.shared.redact(pem)
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("BEGIN RSA PRIVATE KEY"))
        #expect(report.matchedPatterns.contains("PEM private key"))
    }

    @Test("EC PEM private key block is redacted")
    func pemPrivateKeyEC() {
        let pem = "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890==\n-----END EC PRIVATE KEY-----"
        let (redacted, report) = Redactor.shared.redact(pem)
        #expect(redacted.contains("[REDACTED]"))
        #expect(report.matchedPatterns.contains("PEM private key"))
    }

    @Test("Bearer token in Authorization header is redacted")
    func bearerToken() {
        let header = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
        let (redacted, report) = Redactor.shared.redact(header)
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
        #expect(report.matchedPatterns.contains("JWT") || report.matchedPatterns.contains("Bearer token"))
    }

    @Test("Bearer token with opaque value is redacted")
    func bearerOpaqueToken() {
        let input = "bearer AbCdEfGhIjKlMnOpQrStUvWxYz1234567890ABCDEFGHIJ"
        let (redacted, report) = Redactor.shared.redact(input)
        #expect(redacted.contains("[REDACTED]"))
        #expect(report.matchedPatterns.contains("Bearer token"))
    }

    @Test("bare JWT (three dot-separated base64url segments) is redacted")
    func bareJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let input = "token=\(jwt)"
        let (redacted, report) = Redactor.shared.redact(input)
        #expect(redacted.contains("[REDACTED]"))
        #expect(!redacted.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
        #expect(report.matchedPatterns.contains("JWT"))
    }

    @Test("normal text with dots is not over-redacted")
    func dotSeparatedTextNotRedacted() {
        let (redacted, report) = Redactor.shared.redact("hello.world.foo")
        #expect(redacted == "hello.world.foo")
        #expect(report.redactedCount == 0)
    }

    @Test("PEM public key block is NOT redacted (only private keys are sensitive)")
    func pemPublicKeyNotRedacted() {
        let pub = "-----BEGIN PUBLIC KEY-----\nMFwwDQYJKoZIhvcNAQEBBQADSwAwSAJBAL3jVB\n-----END PUBLIC KEY-----"
        let (redacted, report) = Redactor.shared.redact(pub)
        #expect(redacted == pub, "Public key blocks must not be redacted")
        #expect(report.redactedCount == 0)
    }
}
