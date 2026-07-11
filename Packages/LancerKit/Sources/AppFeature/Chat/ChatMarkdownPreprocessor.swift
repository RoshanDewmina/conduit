import Foundation

/// Lightweight markdown normalizations before native `AttributedString(markdown:)` render.
/// Inspired by Omnara's preprocess pass (unicode bullets → ASCII) — logic only, not copied code.
/// Also converts common CLI-emitted HTML and inserts blank lines so block boundaries survive
/// Foundation's markdown parser (which otherwise glues adjacent headings/paragraphs).
public enum ChatMarkdownPreprocessor: Sendable {
    public static func preprocess(_ raw: String) -> String {
        var result = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        result = convertDetailsBlocks(result)
        result = convertCommonHTML(result)
        result = normalizeUnicodeBullets(result)
        result = ensureBlockBoundaries(result)
        return result
    }

    // MARK: - HTML → markdown

    /// `<details><summary>X</summary>BODY</details>` → `**X**\n\nBODY` (always expanded).
    static func convertDetailsBlocks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<details\b[^>]*>\s*<summary\b[^>]*>(.*?)</summary>(.*?)</details>"#,
            options: []
        ) else {
            return text
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let summaryRange = Range(match.range(at: 1), in: output),
                  let bodyRange = Range(match.range(at: 2), in: output),
                  let fullRange = Range(match.range, in: output)
            else { continue }

            let summary = String(output[summaryRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(output[bodyRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement: String
            if summary.isEmpty {
                replacement = body
            } else if body.isEmpty {
                replacement = "**\(summary)**"
            } else {
                replacement = "**\(summary)**\n\n\(body)"
            }
            output.replaceSubrange(fullRange, with: replacement)
        }
        return output
    }

    /// Convert common inline/block HTML CLIs emit; strip unknown tags, keep content.
    static func convertCommonHTML(_ text: String) -> String {
        var result = text

        result = replaceTag(result, names: ["br"], replacement: "\n", void: true)
        result = replacePairedTag(result, names: ["b", "strong"], open: "**", close: "**")
        result = replacePairedTag(result, names: ["i", "em"], open: "*", close: "*")
        result = replacePairedTag(result, names: ["code"], open: "`", close: "`")
        result = replacePreBlocks(result)

        // Strip any remaining HTML tags; keep inner text.
        if let strip = try? NSRegularExpression(pattern: #"</?[A-Za-z][^>]*>"#, options: []) {
            result = strip.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: ""
            )
        }

        // Decode a few entities that often accompany CLI HTML.
        result = result
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        return result
    }

    private static func replaceTag(_ text: String, names: [String], replacement: String, void: Bool) -> String {
        let alternation = names.joined(separator: "|")
        let pattern = void
            ? #"(?i)<(?:\#(alternation))\b[^>]*/?>"#
            : #"(?i)</?(?:\#(alternation))\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: replacement
        )
    }

    private static func replacePairedTag(_ text: String, names: [String], open: String, close: String) -> String {
        let alternation = names.joined(separator: "|")
        let pattern = #"(?is)<(?:\#(alternation))\b[^>]*>(.*?)</(?:\#(alternation))\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }

        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let innerRange = Range(match.range(at: 1), in: output),
                  let fullRange = Range(match.range, in: output)
            else { continue }
            let inner = String(output[innerRange])
            output.replaceSubrange(fullRange, with: open + inner + close)
        }
        return output
    }

    private static func replacePreBlocks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<pre\b[^>]*>(.*?)</pre\s*>"#,
            options: []
        ) else {
            return text
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let innerRange = Range(match.range(at: 1), in: output),
                  let fullRange = Range(match.range, in: output)
            else { continue }
            var inner = String(output[innerRange])
            // Nested <code> inside <pre> is common; strip those tags only.
            if let codeStrip = try? NSRegularExpression(pattern: #"(?i)</?code\b[^>]*>"#, options: []) {
                inner = codeStrip.stringByReplacingMatches(
                    in: inner,
                    options: [],
                    range: NSRange(location: 0, length: (inner as NSString).length),
                    withTemplate: ""
                )
            }
            let body = inner.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            output.replaceSubrange(fullRange, with: "```\n\(body)\n```")
        }
        return output
    }

    // MARK: - Bullets

    private static func normalizeUnicodeBullets(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { line -> String in
            let s = String(line)
            if s.hasPrefix("• ") { return "- " + s.dropFirst(2) }
            if s.hasPrefix("● ") { return "- " + s.dropFirst(2) }
            if s.hasPrefix("◦ ") { return "- " + s.dropFirst(2) }
            if s.hasPrefix("* ") && !s.hasPrefix("**") { return "- " + s.dropFirst(2) }
            return s
        }.joined(separator: "\n")
    }

    // MARK: - Block boundaries

    /// Insert blank lines so headings, list items, and bold-led title lines parse as
    /// separate blocks instead of one soft-wrapped paragraph.
    static func ensureBlockBoundaries(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return text }

        var result: [String] = []
        for line in lines {
            if let prev = result.last,
               !prev.isEmpty,
               !line.isEmpty,
               needsBoundary(between: prev, and: line) {
                result.append("")
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    static func needsBoundary(between prev: String, and curr: String) -> Bool {
        let prevKind = blockKind(prev)
        let currKind = blockKind(curr)

        if currKind == .heading { return true }
        if prevKind == .heading && currKind != .blank { return true }

        if currKind == .list && prevKind != .list { return true }
        if prevKind == .list && currKind == .paragraph { return true }

        // Bold-led standalone lines (quiz terms, mini-headings) need separation.
        if currKind == .boldLead && (prevKind == .boldLead || prevKind == .paragraph || prevKind == .list) {
            return true
        }
        if prevKind == .boldLead && currKind == .paragraph {
            return true
        }

        return false
    }

    private enum BlockKind {
        case blank
        case heading
        case list
        case boldLead
        case paragraph
    }

    private static func blockKind(_ line: String) -> BlockKind {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        if trimmed.hasPrefix("#") {
            let afterHashes = trimmed.drop(while: { $0 == "#" })
            if afterHashes.first == " " || afterHashes.first == "\t" || afterHashes.isEmpty {
                return .heading
            }
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("+ ") { return .list }
        if trimmed.hasPrefix("* ") && !trimmed.hasPrefix("**") { return .list }
        if let re = try? NSRegularExpression(pattern: #"^\d+\.\s+"#, options: []),
           re.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
            return .list
        }
        // Entire line is a bold span (optional trailing punctuation), e.g. `**Variable** —`
        if let re = try? NSRegularExpression(
            pattern: #"^\*\*[^*\n]+\*\*(?:\s*[—:\-].*)?$"#,
            options: []
        ),
           re.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
            return .boldLead
        }
        return .paragraph
    }
}
