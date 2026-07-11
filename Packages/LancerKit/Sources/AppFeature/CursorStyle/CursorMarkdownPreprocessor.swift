import Foundation

/// Pure `String -> String` markdown normalization pass, run before handing assistant text
/// to MarkdownUI. No `#if os(iOS)` gate — testable via `swift test` on macOS.
///
/// Ported logic (Apache-2.0, attribution + NOTICE per
/// `docs/product/2026-07-09-chat-ui-port-map.md` §2): Omnara
/// `apps/web/src/components/dashboard/markdownConfig.tsx:11-25,58-115` `preprocessMarkdown()`
/// — normalizes unicode bullet glyphs to a Markdown `-` list marker, and wraps bare vendor
/// patch/diff output (Codex's `*** Begin Patch` blocks and bare `diff --git` hunks) in fenced
/// ` ```diff ` blocks so they render as code instead of raw text.
public enum CursorMarkdownPreprocessor {
    /// Unicode bullet glyphs some vendor CLIs emit in place of a Markdown `-`/`*` marker.
    private static let unicodeBullets: [Character] = ["•", "◦", "▪", "‣", "·"]

    public static func preprocess(_ text: String) -> String {
        var result = normalizeUnicodeBullets(text)
        result = wrapBarePatchBlocks(result)
        return result
    }

    private static func normalizeUnicodeBullets(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var trimmedLeading = ""
                var rest = Substring(line)
                while let first = rest.first, first == " " || first == "\t" {
                    trimmedLeading.append(first)
                    rest = rest.dropFirst()
                }
                guard let first = rest.first, unicodeBullets.contains(first) else {
                    return String(line)
                }
                var afterBullet = rest.dropFirst()
                if let space = afterBullet.first, space == " " {
                    afterBullet = afterBullet.dropFirst()
                }
                return trimmedLeading + "- " + afterBullet
            }
            .joined(separator: "\n")
    }

    /// Wraps a bare Codex-style `*** Begin Patch` ... `*** End Patch` block, or a bare
    /// `diff --git` hunk not already inside a fence, in a ` ```diff ` fence.
    private static func wrapBarePatchBlocks(_ text: String) -> String {
        guard !text.contains("```") else { return text }

        let lines = text.components(separatedBy: "\n")
        guard let patchStart = lines.firstIndex(where: {
            $0.hasPrefix("*** Begin Patch") || $0.hasPrefix("diff --git")
        }) else {
            return text
        }

        var patchEnd = lines.count - 1
        if let explicitEnd = lines.firstIndex(where: { $0.hasPrefix("*** End Patch") }) {
            patchEnd = explicitEnd
        }
        guard patchStart <= patchEnd else { return text }

        var result = Array(lines[0..<patchStart])
        result.append("```diff")
        result.append(contentsOf: lines[patchStart...patchEnd])
        result.append("```")
        if patchEnd + 1 < lines.count {
            result.append(contentsOf: lines[(patchEnd + 1)...])
        }
        return result.joined(separator: "\n")
    }
}
