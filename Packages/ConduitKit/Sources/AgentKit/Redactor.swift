import Foundation

public struct RedactionReport: Sendable, Equatable {
    public let redactedCount: Int
    public let matchedPatterns: [String]

    public init(redactedCount: Int, matchedPatterns: [String]) {
        self.redactedCount = redactedCount
        self.matchedPatterns = matchedPatterns
    }
}

public struct Redactor: Sendable {
    public static let shared = Redactor()

    // Named patterns with their corresponding regex strings.
    private static let builtInPatterns: [(name: String, pattern: String)] = [
        ("AWS key",          #"AKIA[0-9A-Z]{16}"#),
        ("GitHub token",     #"gh[pousr]_[A-Za-z0-9_]+"#),
        // Anthropic keys start with sk-ant-; listed before the generic sk- pattern
        // to ensure the more specific match is applied first and named distinctly.
        ("Anthropic key",    #"sk-ant-[A-Za-z0-9\-_]{20,}"#),
        ("OpenRouter key",   #"sk-or-[A-Za-z0-9\-_]{20,}"#),
        ("OpenAI key",       #"sk-[A-Za-z0-9\-]{20,}"#),
        ("GitHub server",    #"ghs_[A-Za-z0-9]+"#),
    ]

    public init() {}

    /// Redacts secrets from `text`.
    /// - Parameters:
    ///   - text: The input string that may contain secrets.
    ///   - extraPatterns: Additional regex patterns to also redact.
    /// - Returns: A tuple of the sanitised string and a `RedactionReport`.
    public func redact(_ text: String, extraPatterns: [String] = []) -> (redacted: String, report: RedactionReport) {
        var result = text
        var totalCount = 0
        var matchedNames: [String] = []

        // Built-in named patterns
        for (name, pattern) in Self.builtInPatterns {
            let (next, count) = applyPattern(pattern, to: result)
            if count > 0 {
                result = next
                totalCount += count
                matchedNames.append(name)
            }
        }

        // Caller-supplied extra patterns (unnamed)
        for pattern in extraPatterns {
            let (next, count) = applyPattern(pattern, to: result)
            if count > 0 {
                result = next
                totalCount += count
                matchedNames.append(pattern)
            }
        }

        let report = RedactionReport(redactedCount: totalCount, matchedPatterns: matchedNames)
        return (redacted: result, report: report)
    }

    // MARK: - Private helpers

    private func applyPattern(_ pattern: String, to text: String) -> (String, Int) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, 0)
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return (text, 0) }
        let replaced = regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "[REDACTED]"
        )
        return (replaced, matches.count)
    }
}
