import Foundation
import ConduitCore

/// Tier 2.2 — text search over a Block's accumulated output chunks.
///
/// Implements the approach from Warp's ripgrep integration (warp_ripgrep/search.rs)
/// but using Swift's native `Regex` on in-memory text — no subprocess needed since
/// mobile block sizes are tractable.
public struct BlockSearchResult: Sendable {
    public let blockID: BlockID
    /// Byte ranges in the block's `joinedOutput` where matches occur.
    public let ranges: [Range<String.Index>]
    public var matchCount: Int { ranges.count }

    public init(blockID: BlockID, ranges: [Range<String.Index>]) {
        self.blockID = blockID
        self.ranges = ranges
    }
}

public struct BlockSearch {
    private init() {}

    /// Search for `query` in `block.joinedOutput`.
    /// - Returns: `nil` if query is empty or block has no output.
    public static func search(query: String, in block: Block) -> BlockSearchResult? {
        guard !query.isEmpty, block.hasOutput else { return nil }
        let text = block.joinedOutput
        let ranges = findRanges(of: query, in: text)
        guard !ranges.isEmpty else { return nil }
        return BlockSearchResult(blockID: block.id, ranges: ranges)
    }

    /// Search across multiple blocks, returning one result per block that matches.
    public static func search(query: String, in blocks: [Block]) -> [BlockSearchResult] {
        guard !query.isEmpty else { return [] }
        return blocks.compactMap { search(query: query, in: $0) }
    }

    // MARK: - Internal

    private static func findRanges(of query: String, in text: String) -> [Range<String.Index>] {
        var results: [Range<String.Index>] = []
        var searchStart = text.startIndex
        let lower = query.lowercased()
        let lowerText = text.lowercased()
        while searchStart < text.endIndex {
            guard let range = lowerText.range(of: lower, range: searchStart ..< text.endIndex) else {
                break
            }
            results.append(range)
            searchStart = range.upperBound == range.lowerBound
                ? text.index(after: range.upperBound)
                : range.upperBound
            if results.count >= 500 { break }  // cap for very noisy output
        }
        return results
    }
}
