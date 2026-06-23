#if os(iOS)
import SwiftUI
import DesignSystem

// MARK: - MarkdownText
//
// Renders an assistant message as proper markdown: fenced code becomes a
// DarkCodeCard, everything else renders as prose with inline markdown
// (bold/italic/code-spans/links), plus lightweight headings and list bullets.
//
// ponytail: native AttributedString(markdown:) handles INLINE markdown only — it
// flattens block structure — so we split blocks ourselves (fences, headings,
// lists, paragraphs) and hand each line's inline span to AttributedString. That
// covers the markdown agents actually emit (prose + code + lists) without pulling
// in a full CommonMark dependency. If we later need tables / nested lists /
// blockquotes rendered faithfully, swap the block splitter for MarkdownUI.

public struct MarkdownText: View {
    private let raw: String
    private let textColor: Color

    @Environment(\.lancerTokens) private var t

    public init(_ raw: String, textColor: Color? = nil) {
        self.raw = raw
        self.textColor = textColor ?? Color.primary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(MarkdownBlock.parse(raw).enumerated()), id: \.offset) { _, block in
                view(for: block)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Streamed tokens land continuously; ease layout growth and fade each new
        // block in so the reply composes smoothly instead of snapping line-by-line.
        .animation(.easeOut(duration: 0.2), value: raw)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case let .code(language, code):
            DarkCodeCard(language: language, code: code)
        case let .heading(level, text):
            inline(text)
                .font(.dsDisplayPt(level <= 1 ? 21 : level == 2 ? 18 : 16, weight: .bold))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(t.accent)
                inline(text).foregroundStyle(textColor)
            }
            .fixedSize(horizontal: false, vertical: true)
        case let .ordered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).").foregroundStyle(t.accent).font(.dsMonoPt(14))
                inline(text).foregroundStyle(textColor)
            }
            .fixedSize(horizontal: false, vertical: true)
        case let .paragraph(text):
            inline(text)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One run of prose with inline markdown applied. Falls back to the raw string
    /// if the inline markdown is malformed, so a stray `*` never blanks a message.
    private func inline(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: s, options: options) {
            return Text(attributed).font(.dsSansPt(16))
        }
        return Text(s).font(.dsSansPt(16))
    }
}

// MARK: - Block model + parser

enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullet(String)
    case ordered(number: Int, text: String)
    case code(language: String?, code: String)

    /// Split markdown into ordered blocks. Fenced code (``` or ~~~) is peeled out
    /// first; remaining text is grouped line-by-line into headings, list items, and
    /// paragraphs (blank-line-separated). Consecutive prose lines join into one
    /// paragraph so soft wrapping reads naturally.
    static func parse(_ raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code: ``` or ~~~ (optionally with a language).
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let body = lines[i]
                    if body.trimmingCharacters(in: .whitespaces).hasPrefix(fence) { break }
                    code.append(body)
                    i += 1
                }
                blocks.append(.code(language: lang.isEmpty ? nil : lang,
                                    code: code.joined(separator: "\n")))
                i += 1 // consume closing fence
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Heading: leading #'s.
            if trimmed.hasPrefix("#") {
                flushParagraph()
                let hashes = trimmed.prefix { $0 == "#" }.count
                let text = String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: min(hashes, 6), text: text))
                i += 1
                continue
            }

            // Unordered list: -, *, or + followed by a space.
            if let bullet = ["- ", "* ", "+ "].first(where: { trimmed.hasPrefix($0) }) {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(bullet.count))))
                i += 1
                continue
            }

            // Ordered list: "N. " prefix.
            if let dot = trimmed.firstIndex(of: "."),
               let n = Int(trimmed[trimmed.startIndex..<dot]),
               trimmed.index(after: dot) < trimmed.endIndex,
               trimmed[trimmed.index(after: dot)] == " " {
                flushParagraph()
                let text = String(trimmed[trimmed.index(dot, offsetBy: 2)...])
                blocks.append(.ordered(number: n, text: text))
                i += 1
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }
}
#endif
