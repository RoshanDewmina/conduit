import Foundation

/// Lightweight markdown normalizations before native `AttributedString(markdown:)` render.
/// Inspired by Omnara's preprocess pass (unicode bullets → ASCII) — logic only, not copied code.
public enum ChatMarkdownPreprocessor: Sendable {
    public static func preprocess(_ raw: String) -> String {
        var result = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Normalize common unicode list markers to ASCII markdown bullets.
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
        result = lines.map { line -> String in
            let s = String(line)
            if s.hasPrefix("• ") { return "- " + s.dropFirst(2) }
            if s.hasPrefix("● ") { return "- " + s.dropFirst(2) }
            if s.hasPrefix("◦ ") { return "- " + s.dropFirst(2) }
            if s.hasPrefix("* ") && !s.hasPrefix("**") { return "- " + s.dropFirst(2) }
            return s
        }.joined(separator: "\n")

        return result
    }
}
