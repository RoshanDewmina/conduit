import Foundation

/// One top-level segment of an assistant message: prose (markdown) or a fenced code block.
public enum ChatMarkdownBlock: Equatable, Sendable {
    case prose(String)
    case codeFence(language: String?, code: String)
}

/// Splits markdown into prose vs fenced code so fences can render with monospace + copy UI.
public enum ChatMarkdownBlockParser: Sendable {
    public static func parse(_ markdown: String) -> [ChatMarkdownBlock] {
        let source = ChatMarkdownPreprocessor.preprocess(markdown)
        guard !source.isEmpty else { return [] }

        guard let regex = try? NSRegularExpression(
            pattern: #"^```([^\n`]*)\n([\s\S]*?)^```[ \t]*$"#,
            options: [.anchorsMatchLines]
        ) else {
            return [.prose(source)]
        }

        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: source, options: [], range: full)

        guard !matches.isEmpty else { return [.prose(source)] }

        var blocks: [ChatMarkdownBlock] = []
        var cursor = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > cursor {
                let prose = ns.substring(with: NSRange(location: cursor, length: matchRange.location - cursor))
                appendProse(prose, to: &blocks)
            }

            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let languageRaw = languageRange.location != NSNotFound ? ns.substring(with: languageRange) : ""
            let language = languageRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = codeRange.location != NSNotFound ? ns.substring(with: codeRange) : ""
            // Trim a single trailing newline that fence capture usually includes.
            let trimmedCode = code.hasSuffix("\n") ? String(code.dropLast()) : code
            blocks.append(.codeFence(language: language.isEmpty ? nil : language, code: trimmedCode))

            cursor = matchRange.location + matchRange.length
        }

        if cursor < ns.length {
            appendProse(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)), to: &blocks)
        }

        return blocks
    }

    private static func appendProse(_ raw: String, to blocks: inout [ChatMarkdownBlock]) {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        guard !trimmed.isEmpty else { return }
        blocks.append(.prose(trimmed))
    }
}
