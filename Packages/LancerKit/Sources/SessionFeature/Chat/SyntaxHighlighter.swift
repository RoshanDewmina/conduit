#if os(iOS)
import SwiftUI
import Foundation

// MARK: - SyntaxHighlighter
//
// ponytail: a minimal regex tokenizer, NOT a real grammar/parser. It tints three
// token classes — comments, strings, and a shared keyword set — which covers the
// languages agents emit most (swift/js/ts/go/python/rust/json/shell). Numbers and
// language-specific grammar are left uncolored; if we ever need true per-language
// highlighting, swap this for a Highlightr/tree-sitter dependency. Per-line so a
// multi-line string mid-fence may mis-tint a line — an accepted edge for the win.

enum SyntaxHighlighter {
    /// Build a colored AttributedString for a code block. `keyword`/`string`/
    /// `comment` come from the terminal palette so highlighting matches the card.
    static func highlight(_ code: String, keyword: Color, string: Color, comment: Color, base: Color) -> AttributedString {
        var out = AttributedString()
        let lines = code.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            out += highlightLine(line, keyword: keyword, string: string, comment: comment, base: base)
            if i < lines.count - 1 { out += AttributedString("\n") }
        }
        return out
    }

    private static let keywords: Set<String> = [
        // Cross-language keyword set (declarations + control flow). A token only
        // colors if it's a whole word, so "function" won't tint inside an identifier.
        "func", "function", "fn", "def", "let", "var", "const", "val", "mut",
        "class", "struct", "enum", "interface", "protocol", "extension", "impl",
        "trait", "type", "typealias", "public", "private", "internal", "static",
        "final", "override", "return", "if", "else", "elif", "for", "while", "do",
        "switch", "case", "default", "break", "continue", "guard", "defer",
        "import", "from", "package", "use", "module", "export", "async", "await",
        "try", "catch", "throw", "throws", "rethrows", "finally", "in", "is", "as",
        "new", "delete", "nil", "null", "none", "true", "false", "self", "this",
        "super", "and", "or", "not", "go", "chan", "map", "range", "select",
    ]

    private static func highlightLine(_ line: String, keyword: Color, string: Color, comment: Color, base: Color) -> AttributedString {
        // A line-leading comment (//, #, --) colors the whole line.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("--") || trimmed.hasPrefix("*") {
            var s = AttributedString(line)
            s.foregroundColor = comment
            return s
        }

        var result = AttributedString()
        // Tokenize into string-literals, words, and everything else. A quote opens a
        // string run until the matching quote (or end of line).
        let chars = Array(line)
        var idx = 0
        func appendColored(_ text: String, _ color: Color) {
            var s = AttributedString(text)
            s.foregroundColor = color
            result += s
        }

        while idx < chars.count {
            let c = chars[idx]
            if c == "\"" || c == "'" || c == "`" {
                let quote = c
                var lit = String(c)
                idx += 1
                while idx < chars.count {
                    lit.append(chars[idx])
                    if chars[idx] == quote && chars[idx - 1] != "\\" { idx += 1; break }
                    idx += 1
                }
                appendColored(lit, string)
            } else if c.isLetter || c == "_" {
                var word = ""
                while idx < chars.count, chars[idx].isLetter || chars[idx].isNumber || chars[idx] == "_" {
                    word.append(chars[idx]); idx += 1
                }
                appendColored(word, keywords.contains(word) ? keyword : base)
            } else if c == "/" && idx + 1 < chars.count && chars[idx + 1] == "/" {
                // Trailing // comment — color the rest of the line.
                appendColored(String(chars[idx...]), comment)
                break
            } else {
                appendColored(String(c), base)
                idx += 1
            }
        }
        return result
    }
}
#endif
