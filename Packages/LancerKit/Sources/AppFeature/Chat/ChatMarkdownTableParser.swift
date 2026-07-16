import Foundation

/// GitHub-flavored markdown table extracted from assistant prose.
public struct ChatMarkdownTable: Equatable, Sendable {
    public enum Alignment: String, Equatable, Sendable {
        case left
        case center
        case right
    }

    public let headers: [String]
    public let alignments: [Alignment]
    public let rows: [[String]]

    public init(headers: [String], alignments: [Alignment], rows: [[String]]) {
        self.headers = headers
        self.alignments = alignments
        self.rows = rows
    }

    public var columnCount: Int { headers.count }
}

/// Splits a prose segment into interleaved prose + GFM table blocks.
public enum ChatMarkdownTableParser: Sendable {
    public enum Segment: Equatable, Sendable {
        case prose(String)
        case table(ChatMarkdownTable)
    }

    /// Detect GitHub-style pipe tables inside a prose string.
    public static func split(_ prose: String) -> [Segment] {
        let lines = prose.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return [] }

        var segments: [Segment] = []
        var proseBuffer: [String] = []
        var index = 0

        func flushProse() {
            let joined = proseBuffer.joined(separator: "\n")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
            proseBuffer = []
            guard !joined.isEmpty else { return }
            segments.append(.prose(joined))
        }

        while index < lines.count {
            if let table = parseTable(in: lines, startingAt: index) {
                flushProse()
                segments.append(.table(table.table))
                index = table.endIndex
                continue
            }
            proseBuffer.append(lines[index])
            index += 1
        }
        flushProse()
        return segments
    }

    /// Parse a single table starting at `start` if header + separator are present.
    public static func parseTable(
        in lines: [String],
        startingAt start: Int
    ) -> (table: ChatMarkdownTable, endIndex: Int)? {
        guard start + 1 < lines.count else { return nil }
        let headerLine = lines[start]
        let separatorLine = lines[start + 1]
        guard looksLikeTableRow(headerLine), isSeparatorRow(separatorLine) else { return nil }

        let headers = splitCells(headerLine)
        guard !headers.isEmpty else { return nil }
        let alignments = parseAlignments(separatorLine, columnCount: headers.count)
        guard alignments.count == headers.count else { return nil }

        var rows: [[String]] = []
        var cursor = start + 2
        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            guard looksLikeTableRow(line) else { break }
            var cells = splitCells(line)
            if cells.count < headers.count {
                cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
            } else if cells.count > headers.count {
                cells = Array(cells.prefix(headers.count))
            }
            rows.append(cells)
            cursor += 1
        }

        let table = ChatMarkdownTable(headers: headers, alignments: alignments, rows: rows)
        return (table, cursor)
    }

    // MARK: - Helpers

    public static func looksLikeTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        // Require a pipe that isn't only an escaped leftover — GFM rows usually start/end with |.
        let cells = splitCells(trimmed)
        return cells.count >= 2
    }

    public static func isSeparatorRow(_ line: String) -> Bool {
        let cells = splitCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return false }
            var sawDash = false
            for ch in t {
                switch ch {
                case "-":
                    sawDash = true
                case ":":
                    continue
                default:
                    return false
                }
            }
            return sawDash
        }
    }

    public static func splitCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public static func parseAlignments(_ separatorLine: String, columnCount: Int) -> [ChatMarkdownTable.Alignment] {
        let cells = splitCells(separatorLine)
        guard cells.count == columnCount else { return [] }
        return cells.map { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            let left = t.hasPrefix(":")
            let right = t.hasSuffix(":")
            if left && right { return .center }
            if right { return .right }
            return .left
        }
    }
}
