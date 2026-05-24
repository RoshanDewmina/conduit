import Foundation
import ConduitCore

/// A parsed unified diff. The parser is forgiving — it ignores binary-only
/// headers, handles git-style `diff --git` blocks and plain `--- / +++`
/// blocks, and never throws on a single malformed hunk; the offender is
/// returned in `parseErrors`.
public struct UnifiedDiff: Sendable, Hashable {
    public var files: [FilePatch]
    public var parseErrors: [String]

    public init(files: [FilePatch], parseErrors: [String] = []) {
        self.files = files
        self.parseErrors = parseErrors
    }

    public var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    public var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }
}

public struct FilePatch: Sendable, Hashable, Identifiable {
    public var id: String { newPath ?? oldPath ?? UUID().uuidString }
    public var oldPath: String?
    public var newPath: String?
    public var isBinary: Bool
    public var hunks: [Hunk]

    public init(oldPath: String?, newPath: String?, isBinary: Bool = false, hunks: [Hunk] = []) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.isBinary = isBinary
        self.hunks = hunks
    }

    public var additions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count } }
    public var deletions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count } }
    public var displayPath: String { newPath ?? oldPath ?? "(unknown)" }
}

public struct Hunk: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var header: String
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    public var lines: [Line]

    public init(
        id: UUID = .init(),
        header: String,
        oldStart: Int, oldCount: Int,
        newStart: Int, newCount: Int,
        lines: [Line]
    ) {
        self.id = id; self.header = header
        self.oldStart = oldStart; self.oldCount = oldCount
        self.newStart = newStart; self.newCount = newCount
        self.lines = lines
    }

    public struct Line: Sendable, Hashable {
        public enum Kind: Sendable, Hashable { case context, addition, deletion, noNewline }
        public var kind: Kind
        public var text: String

        public init(kind: Kind, text: String) {
            self.kind = kind; self.text = text
        }
    }
}

public enum UnifiedDiffParser {

    public static func parse(_ input: String) -> UnifiedDiff {
        var files: [FilePatch] = []
        var errors: [String] = []
        var current: FilePatch?
        var pendingHunk: Hunk?
        var lineNumber = 0

        func commitHunk() {
            if let h = pendingHunk { current?.hunks.append(h); pendingHunk = nil }
        }
        func commitFile() {
            commitHunk()
            if let c = current { files.append(c); current = nil }
        }

        for raw in input.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let line = String(raw)

            if line.hasPrefix("diff --git ") {
                commitFile()
                let parts = line.split(separator: " ")
                let a = parts.first(where: { $0.hasPrefix("a/") }).map { String($0.dropFirst(2)) }
                let b = parts.first(where: { $0.hasPrefix("b/") }).map { String($0.dropFirst(2)) }
                current = FilePatch(oldPath: a, newPath: b)
                continue
            }
            if line.hasPrefix("--- ") {
                if current == nil { current = FilePatch(oldPath: nil, newPath: nil) }
                let path = String(line.dropFirst(4))
                current?.oldPath = path == "/dev/null" ? nil : (path.hasPrefix("a/") ? String(path.dropFirst(2)) : path)
                continue
            }
            if line.hasPrefix("+++ ") {
                if current == nil { current = FilePatch(oldPath: nil, newPath: nil) }
                let path = String(line.dropFirst(4))
                current?.newPath = path == "/dev/null" ? nil : (path.hasPrefix("b/") ? String(path.dropFirst(2)) : path)
                continue
            }
            if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                current?.isBinary = true
                continue
            }
            if line.hasPrefix("@@") {
                commitHunk()
                guard let header = parseHunkHeader(line) else {
                    errors.append("line \(lineNumber): bad hunk header")
                    continue
                }
                pendingHunk = Hunk(
                    header: line,
                    oldStart: header.oldStart, oldCount: header.oldCount,
                    newStart: header.newStart, newCount: header.newCount,
                    lines: []
                )
                continue
            }

            // Content line within a hunk.
            if pendingHunk != nil {
                let kind: Hunk.Line.Kind
                let text: String
                if line.hasPrefix("+") { kind = .addition; text = String(line.dropFirst()) }
                else if line.hasPrefix("-") { kind = .deletion; text = String(line.dropFirst()) }
                else if line.hasPrefix(" ") { kind = .context;  text = String(line.dropFirst()) }
                else if line.hasPrefix("\\") { kind = .noNewline; text = String(line.dropFirst(2)) }
                else { continue }
                pendingHunk?.lines.append(Hunk.Line(kind: kind, text: text))
            }
        }
        commitFile()
        return UnifiedDiff(files: files, parseErrors: errors)
    }

    /// "@@ -oldStart,oldCount +newStart,newCount @@" — counts default to 1
    /// when omitted, per the unified diff grammar.
    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        guard let openRange = line.range(of: "@@"),
              let closeRange = line.range(of: "@@", range: openRange.upperBound..<line.endIndex)
        else { return nil }
        let body = line[openRange.upperBound ..< closeRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        let parts = body.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        func parse(_ token: Substring) -> (Int, Int)? {
            let s = token.dropFirst()  // drop -/+
            let pieces = s.split(separator: ",")
            guard let start = Int(pieces.first ?? "") else { return nil }
            let count = pieces.count > 1 ? (Int(pieces[1]) ?? 1) : 1
            return (start, count)
        }
        guard let old = parse(parts[0]), let new = parse(parts[1]) else { return nil }
        return (old.0, old.1, new.0, new.1)
    }
}
