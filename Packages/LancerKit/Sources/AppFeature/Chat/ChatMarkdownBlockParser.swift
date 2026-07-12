import Foundation

/// One top-level segment of an assistant message: prose (markdown) or a fenced code block.
public enum ChatMarkdownBlock: Equatable, Sendable {
    case prose(String)
    case codeFence(language: String?, code: String)
}

/// Splits markdown into prose vs fenced code so fences can render with monospace + copy UI.
public enum ChatMarkdownBlockParser: Sendable {
    /// UTF-8 byte ceiling for a single prose block passed through `AttributedString(markdown:)`.
    /// Degenerate inputs (e.g. an unterminated fence that yields the whole string as one block)
    /// above this size render as plain monospaced text instead.
    public static let maxAttributedBlockUTF8Count = 256 * 1024

    private final class CachedBlocks: NSObject {
        let blocks: [ChatMarkdownBlock]
        init(_ blocks: [ChatMarkdownBlock]) { self.blocks = blocks }
    }

    /// `NSCache` is thread-safe; counters are guarded by `lock`.
    private final class Store: @unchecked Sendable {
        let cache = NSCache<NSString, CachedBlocks>()
        let lock = NSLock()
        var uncachedParseCount = 0
        var cacheHitCount = 0
    }

    private static let store = Store()

    /// Number of times `parse` computed blocks from scratch (cache miss). Test seam.
    public static var uncachedParseCountForTesting: Int {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.uncachedParseCount
    }

    /// Number of times `parse` returned a cached result. Test seam.
    public static var cacheHitCountForTesting: Int {
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.cacheHitCount
    }

    /// Clears the parse cache and counters. Test seam.
    public static func resetCacheForTesting() {
        store.cache.removeAllObjects()
        store.lock.lock()
        store.uncachedParseCount = 0
        store.cacheHitCount = 0
        store.lock.unlock()
    }

    /// Whether a prose block should skip markdown attribution and render as plain monospace.
    public static func shouldUsePlainTextFallback(_ text: String) -> Bool {
        text.utf8.count > maxAttributedBlockUTF8Count
    }

    public static func parse(_ markdown: String) -> [ChatMarkdownBlock] {
        parseWithCacheInfo(markdown).blocks
    }

    /// Same as `parse`, but reports whether the result came from the NSCache.
    /// Test seam — race-free under parallel suite execution (unlike the counters).
    public static func parseWithCacheInfoForTesting(_ markdown: String) -> (blocks: [ChatMarkdownBlock], wasCached: Bool) {
        parseWithCacheInfo(markdown)
    }

    private static func parseWithCacheInfo(_ markdown: String) -> (blocks: [ChatMarkdownBlock], wasCached: Bool) {
        let key = markdown as NSString
        if let cached = store.cache.object(forKey: key) {
            store.lock.lock()
            store.cacheHitCount += 1
            store.lock.unlock()
            return (cached.blocks, true)
        }

        let blocks = parseUncached(markdown)
        store.cache.setObject(CachedBlocks(blocks), forKey: key)
        store.lock.lock()
        store.uncachedParseCount += 1
        store.lock.unlock()
        return (blocks, false)
    }

    private static func parseUncached(_ markdown: String) -> [ChatMarkdownBlock] {
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
