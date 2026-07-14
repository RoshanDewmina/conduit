import Foundation

// MARK: - Wire shapes (G1 daemon / G2 fixtures — keep decode keys stable)

/// `repo.turnDiff` / `repo.sessionDiff` response.
public struct RepoDiffSummary: Codable, Equatable, Sendable {
    public var supported: Bool
    public var files: [RepoDiffFile]
    public var totalAdded: Int
    public var totalRemoved: Int

    public init(supported: Bool, files: [RepoDiffFile], totalAdded: Int, totalRemoved: Int) {
        self.supported = supported
        self.files = files
        self.totalAdded = totalAdded
        self.totalRemoved = totalRemoved
    }

    public var fileCount: Int { files.count }
    public var hasChanges: Bool { supported && !files.isEmpty }

    public var titleLabel: String {
        let n = fileCount
        return n == 1 ? "1 file changed" : "\(n) files changed"
    }

    /// Codex-style subtitle / pill suffix: `+A −D`.
    public var countsLabel: String {
        "+\(totalAdded) −\(totalRemoved)"
    }

    public var cardSummaryLabel: String {
        "\(titleLabel) \(countsLabel)"
    }
}

public struct RepoDiffFile: Codable, Equatable, Sendable, Identifiable {
    public var path: String
    public var added: Int
    public var removed: Int
    public var status: String

    public var id: String { path }

    public init(path: String, added: Int, removed: Int, status: String) {
        self.path = path
        self.added = added
        self.removed = removed
        self.status = status
    }

    public var fileName: String { ChatFileNameDisplay.displayName(for: path) }

    public var directoryPath: String {
        if let slash = path.lastIndex(of: "/") {
            return String(path[..<slash])
        }
        return ""
    }

    public var countsLabel: String { "+\(added) −\(removed)" }

    /// Short status for the file header (added / deleted / renamed / modified / …).
    public var statusLabel: String {
        let raw = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "modified" }
        return raw.lowercased()
    }
}

/// `repo.fileDiff` response.
public struct RepoFileDiff: Codable, Equatable, Sendable {
    public var hunks: [RepoDiffHunk]
    public var truncated: Bool

    public init(hunks: [RepoDiffHunk], truncated: Bool = false) {
        self.hunks = hunks
        self.truncated = truncated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hunks = try c.decodeIfPresent([RepoDiffHunk].self, forKey: .hunks) ?? []
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
    }
}

public struct RepoDiffHunk: Codable, Equatable, Sendable, Identifiable {
    public var header: String
    public var oldStart: Int
    public var newStart: Int
    public var lines: [RepoDiffLine]

    public var id: String { "\(header)|\(oldStart)|\(newStart)" }

    public init(header: String, oldStart: Int, newStart: Int, lines: [RepoDiffLine]) {
        self.header = header
        self.oldStart = oldStart
        self.newStart = newStart
        self.lines = lines
    }

    public var addedCount: Int { lines.filter { $0.kind == .add }.count }
    public var removedCount: Int { lines.filter { $0.kind == .del }.count }

    /// Last old/new line numbers present in the hunk (for "Lines X–Y").
    /// Uses the side that actually has lines so add-only / del-only hunks don't mix sides.
    public var lineRangeLabel: String {
        let oldNos = lines.compactMap(\.oldNo)
        let newNos = lines.compactMap(\.newNo)
        let nos: [Int]
        if oldNos.isEmpty && newNos.isEmpty {
            nos = [newStart]
        } else if oldNos.isEmpty {
            nos = newNos
        } else if newNos.isEmpty {
            nos = oldNos
        } else {
            nos = [oldNos.first!, oldNos.last!, newNos.first!, newNos.last!]
        }
        let start = nos.min() ?? newStart
        let end = nos.max() ?? start
        if start == end { return "Lines \(start)" }
        return "Lines \(start)–\(end)"
    }

    public var sectionTitle: String {
        "\(lineRangeLabel) +\(addedCount) −\(removedCount)"
    }
}

public struct RepoDiffLine: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case add
        case del
        case context
    }

    public var kind: Kind
    public var oldNo: Int?
    public var newNo: Int?
    public var text: String

    public init(kind: Kind, oldNo: Int? = nil, newNo: Int? = nil, text: String) {
        self.kind = kind
        self.oldNo = oldNo
        self.newNo = newNo
        self.text = text
    }

    /// Prefer new-side number for add/context; old-side for deletions.
    public var displayLineNumber: Int? {
        switch kind {
        case .del: return oldNo
        case .add, .context: return newNo ?? oldNo
        }
    }
}

/// One rendered row derived from a wire hunk line (stable id for ForEach).
public struct DiffDisplayRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: RepoDiffLine.Kind
    public let oldNo: Int?
    public let newNo: Int?
    public let text: String
    public let displayLineNumber: Int?

    public init(index: Int, line: RepoDiffLine) {
        self.id = "\(index)|\(line.kind.rawValue)|\(line.oldNo ?? -1)|\(line.newNo ?? -1)|\(line.text)"
        self.kind = line.kind
        self.oldNo = line.oldNo
        self.newNo = line.newNo
        self.text = line.text
        self.displayLineNumber = line.displayLineNumber
    }
}

public enum DiffHunkPresentation {
    public static func rows(from hunk: RepoDiffHunk) -> [DiffDisplayRow] {
        hunk.lines.enumerated().map { DiffDisplayRow(index: $0.offset, line: $0.element) }
    }
}

/// `repo.tree` entry.
public struct RepoTreeEntry: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var isDir: Bool

    public var id: String { "\(isDir ? "d" : "f"):\(name)" }

    public init(name: String, isDir: Bool) {
        self.name = name
        self.isDir = isDir
    }
}

/// `repo.file` response.
public struct RepoFileContent: Codable, Equatable, Sendable {
    public var content: String
    public var truncated: Bool
    public var size: Int
    public var binary: Bool

    public init(content: String, truncated: Bool = false, size: Int = 0, binary: Bool = false) {
        self.content = content
        self.truncated = truncated
        self.size = size
        self.binary = binary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        binary = try c.decodeIfPresent(Bool.self, forKey: .binary) ?? false
    }
}

// MARK: - Line comments → composer

public struct QueuedReviewComment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let path: String
    public let line: Int
    public let lineText: String
    public let comment: String

    public init(
        id: UUID = UUID(),
        path: String,
        line: Int,
        lineText: String,
        comment: String
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.lineText = lineText
        self.comment = comment
    }

    public var fileName: String { ChatFileNameDisplay.displayName(for: path) }

    /// Chip label: `Status.md:16 · comment text…`
    public var chipLabel: String {
        ReviewCommentFormatting.chipLabel(path: path, line: line, comment: comment)
    }

    /// Sent block: `file:line — quoted line — comment`
    public var embedBlock: String {
        ReviewCommentFormatting.embedBlock(
            path: path,
            line: line,
            lineText: lineText,
            comment: comment
        )
    }
}

public enum ReviewCommentFormatting {
    /// Codex attach format embedded before the user prompt on send.
    public static func embedBlock(path: String, line: Int, lineText: String, comment: String) -> String {
        let quoted = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(path):\(line) — \(quoted) — \(body)"
    }

    public static func chipLabel(path: String, line: Int, comment: String) -> String {
        let name = ChatFileNameDisplay.displayName(for: path)
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = trimmed.count > 40 ? String(trimmed.prefix(37)) + "…" : trimmed
        return "\(name):\(line) · \(short)"
    }

    /// Joins queued comments ahead of the free-text prompt (blank line between blocks and prompt).
    public static func composerPrefix(comments: [QueuedReviewComment], prompt: String) -> String {
        let blocks = comments.map(\.embedBlock)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if blocks.isEmpty { return trimmedPrompt }
        if trimmedPrompt.isEmpty { return blocks.joined(separator: "\n\n") }
        return blocks.joined(separator: "\n\n") + "\n\n" + trimmedPrompt
    }
}

// MARK: - Full-file viewer presentation

/// How a source line is laid out in the Review full-file viewer.
public enum RepoFileLineLayout: Equatable, Sendable {
    /// One visual row per source line; overflow scrolls horizontally (no soft wrap).
    case singleLineHorizontalScroll
}

public struct RepoFileDisplayLine: Equatable, Sendable, Identifiable {
    public let number: Int
    public let text: String

    public var id: Int { number }

    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
}

/// Pure layout/content model for `FileViewerView` — keeps line structure testable
/// without SwiftUI. Soft-wrap must stay off so bi-axial ScrollView does not
/// collapse long lines into a narrow character column on device.
public enum RepoFilePresentation {
    public static let lineLayout: RepoFileLineLayout = .singleLineHorizontalScroll

    /// Soft wrap forces character-column collapse inside horizontal ScrollView on iPhone.
    public static let allowsSoftWrap = false

    public static func shouldSoftWrap(lineText: String) -> Bool {
        _ = lineText
        return allowsSoftWrap
    }

    public static func lines(from content: String) -> [RepoFileDisplayLine] {
        let parts = content.split(separator: "\n", omittingEmptySubsequences: false)
        if parts.isEmpty {
            return [RepoFileDisplayLine(number: 1, text: "")]
        }
        return parts.enumerated().map { offset, part in
            RepoFileDisplayLine(number: offset + 1, text: String(part))
        }
    }
}

// MARK: - Lazy tree merge

public struct ReviewTreeNode: Identifiable, Equatable, Sendable {
    public var name: String
    public var path: String
    public var isDir: Bool
    public var children: [ReviewTreeNode]?
    public var isExpanded: Bool
    public var isLoading: Bool

    public var id: String { path }

    public init(
        name: String,
        path: String,
        isDir: Bool,
        children: [ReviewTreeNode]? = nil,
        isExpanded: Bool = false,
        isLoading: Bool = false
    ) {
        self.name = name
        self.path = path
        self.isDir = isDir
        self.children = children
        self.isExpanded = isExpanded
        self.isLoading = isLoading
    }
}

public enum ReviewTreeMerge {
    /// Exact `.git` directory name (not `.github` / `.gitignore`).
    public static func isGitMetadataEntryName(_ name: String) -> Bool {
        name == ".git"
    }

    /// True when `path` is `.git` or nested under a `.git` path segment.
    public static func isUnderGitMetadata(_ path: String) -> Bool {
        path.split(separator: "/").contains(where: { $0 == ".git" })
    }

    /// Client-side presentation filter: drop `.git` internals, keep normal dotfiles.
    public static func visibleEntries(
        parentPath: String,
        entries: [RepoTreeEntry]
    ) -> [RepoTreeEntry] {
        if isUnderGitMetadata(parentPath) { return [] }
        return entries.filter { !isGitMetadataEntryName($0.name) }
    }

    /// Dirs first, then files; case-insensitive name within each group.
    public static func sortedEntries(_ entries: [RepoTreeEntry]) -> [RepoTreeEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDir != rhs.isDir { return lhs.isDir && !rhs.isDir }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public static func nodes(parentPath: String, entries: [RepoTreeEntry]) -> [ReviewTreeNode] {
        sortedEntries(visibleEntries(parentPath: parentPath, entries: entries)).map { entry in
            let childPath = parentPath.isEmpty ? entry.name : "\(parentPath)/\(entry.name)"
            return ReviewTreeNode(
                name: entry.name,
                path: childPath,
                isDir: entry.isDir,
                children: entry.isDir ? nil : nil
            )
        }
    }

    /// Replaces `path`'s children with freshly fetched entries (dirs-first).
    public static func mergeChildren(
        path: String,
        entries: [RepoTreeEntry],
        into roots: inout [ReviewTreeNode]
    ) {
        let children = nodes(parentPath: path, entries: entries)
        if path.isEmpty {
            roots = children
            return
        }
        _ = updateNode(path: path, in: &roots) { node in
            node.children = children
            node.isLoading = false
            node.isExpanded = true
        }
    }

    @discardableResult
    public static func updateNode(
        path: String,
        in nodes: inout [ReviewTreeNode],
        mutate: (inout ReviewTreeNode) -> Void
    ) -> Bool {
        for index in nodes.indices {
            if nodes[index].path == path {
                mutate(&nodes[index])
                return true
            }
            if var children = nodes[index].children {
                if updateNode(path: path, in: &children, mutate: mutate) {
                    nodes[index].children = children
                    return true
                }
            }
        }
        return false
    }

    /// Client-side filter of already-loaded nodes (v1 search).
    public static func filter(nodes: [ReviewTreeNode], query: String) -> [ReviewTreeNode] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nodes }
        return nodes.compactMap { filterNode($0, query: q) }
    }

    private static func filterNode(_ node: ReviewTreeNode, query: String) -> ReviewTreeNode? {
        if node.name.localizedCaseInsensitiveContains(query) ||
            node.path.localizedCaseInsensitiveContains(query) {
            return node
        }
        guard let children = node.children else { return nil }
        let filtered = children.compactMap { filterNode($0, query: query) }
        guard !filtered.isEmpty else { return nil }
        var copy = node
        copy.children = filtered
        copy.isExpanded = true
        return copy
    }
}
