import Foundation

#if os(iOS)
import SessionFeature
#endif

/// Read-only review RPCs — G1 daemon lands the same shapes; G2 UI binds this protocol.
public protocol ReviewDataSource: Sendable {
    func turnDiff(conversationID: String, turnID: String) async throws -> RepoDiffSummary
    func sessionDiff(conversationID: String) async throws -> RepoDiffSummary
    func fileDiff(conversationID: String, path: String, turnID: String?) async throws -> RepoFileDiff
    func tree(conversationID: String, path: String) async throws -> [RepoTreeEntry]
    func file(conversationID: String, path: String, maxBytes: Int) async throws -> RepoFileContent
}

/// Narrow bridge contract for review-only relay RPCs.
public protocol RelayReviewBridge: Sendable {
    func repoTurnDiff(conversationID: String, turnID: String) async throws -> RepoDiffSummary
    func repoSessionDiff(conversationID: String) async throws -> RepoDiffSummary
    func repoFileDiff(conversationID: String, path: String, turnID: String?) async throws -> RepoFileDiff
    func repoTree(conversationID: String, path: String) async throws -> [RepoTreeEntry]
    func repoFile(conversationID: String, path: String, maxBytes: Int) async throws -> RepoFileContent
}

/// Live relay-backed review data source with a no-bridge fallback.
public struct RelayReviewDataSource: ReviewDataSource {
    private let bridge: (any RelayReviewBridge)?

    public init(bridge: (any RelayReviewBridge)? = nil) {
        self.bridge = bridge
    }

    public func turnDiff(conversationID: String, turnID: String) async throws -> RepoDiffSummary {
        guard let bridge else {
            return RepoDiffSummary(supported: false, files: [], totalAdded: 0, totalRemoved: 0)
        }
        return try await bridge.repoTurnDiff(conversationID: conversationID, turnID: turnID)
    }

    public func sessionDiff(conversationID: String) async throws -> RepoDiffSummary {
        guard let bridge else {
            return RepoDiffSummary(supported: false, files: [], totalAdded: 0, totalRemoved: 0)
        }
        return try await bridge.repoSessionDiff(conversationID: conversationID)
    }

    public func fileDiff(conversationID: String, path: String, turnID: String?) async throws -> RepoFileDiff {
        guard let bridge else {
            return RepoFileDiff(hunks: [], truncated: false)
        }
        return try await bridge.repoFileDiff(conversationID: conversationID, path: path, turnID: turnID)
    }

    public func tree(conversationID: String, path: String) async throws -> [RepoTreeEntry] {
        guard let bridge else { return [] }
        return try await bridge.repoTree(conversationID: conversationID, path: path)
    }

    public func file(conversationID: String, path: String, maxBytes: Int) async throws -> RepoFileContent {
        guard let bridge else {
            return RepoFileContent(content: "", truncated: false, size: 0, binary: false)
        }
        return try await bridge.repoFile(conversationID: conversationID, path: path, maxBytes: maxBytes)
    }
}

#if os(iOS)
extension E2ERelayBridge: RelayReviewBridge {
    public func repoTurnDiff(conversationID: String, turnID: String) async throws -> RepoDiffSummary {
        try await relayRepoTurnDiff(
            conversationID: conversationID,
            turnID: turnID,
            as: RepoDiffSummary.self
        )
    }

    public func repoSessionDiff(conversationID: String) async throws -> RepoDiffSummary {
        try await relayRepoSessionDiff(
            conversationID: conversationID,
            as: RepoDiffSummary.self
        )
    }

    public func repoFileDiff(conversationID: String, path: String, turnID: String?) async throws -> RepoFileDiff {
        try await relayRepoFileDiff(
            conversationID: conversationID,
            path: path,
            turnID: turnID,
            as: RepoFileDiff.self
        )
    }

    public func repoTree(conversationID: String, path: String) async throws -> [RepoTreeEntry] {
        try await relayRepoTree(
            conversationID: conversationID,
            path: path,
            as: [RepoTreeEntry].self
        )
    }

    public func repoFile(conversationID: String, path: String, maxBytes: Int) async throws -> RepoFileContent {
        try await relayRepoFile(
            conversationID: conversationID,
            path: path,
            maxBytes: maxBytes,
            as: RepoFileContent.self
        )
    }
}
#endif

/// In-memory fixtures matching the frozen G1 wire shapes (verbatim JSON decode in tests).
public struct FixtureReviewDataSource: ReviewDataSource {
    public static let shared = FixtureReviewDataSource()

    public init() {}

    public static let turnDiffJSON = """
    {
      "supported": true,
      "files": [
        {"path": "docs/Status.md", "added": 12, "removed": 3, "status": "modified"},
        {"path": "Packages/LancerKit/Sources/AppFeature/Chat/LiveThreadView.swift", "added": 40, "removed": 8, "status": "modified"},
        {"path": "Packages/LancerKit/Sources/AppFeature/Review/ReviewModels.swift", "added": 180, "removed": 0, "status": "added"}
      ],
      "totalAdded": 232,
      "totalRemoved": 11
    }
    """

    public static let sessionDiffJSON = """
    {
      "supported": true,
      "files": [
        {"path": "docs/Status.md", "added": 12, "removed": 3, "status": "modified"},
        {"path": "Packages/LancerKit/Sources/AppFeature/Chat/LiveThreadView.swift", "added": 40, "removed": 8, "status": "modified"},
        {"path": "Packages/LancerKit/Sources/AppFeature/Review/ReviewModels.swift", "added": 180, "removed": 0, "status": "added"},
        {"path": "Packages/LancerKit/Sources/AppFeature/Review/ReviewSheetView.swift", "added": 210, "removed": 0, "status": "added"}
      ],
      "totalAdded": 442,
      "totalRemoved": 11
    }
    """

    public static let fileDiffJSON = """
    {
      "hunks": [
        {
          "header": "@@ -14,7 +14,10 @@",
          "oldStart": 14,
          "newStart": 14,
          "lines": [
            {"kind": "context", "oldNo": 14, "newNo": 14, "text": "public struct Status {"},
            {"kind": "del", "oldNo": 15, "newNo": null, "text": "    let ready = false"},
            {"kind": "add", "oldNo": null, "newNo": 15, "text": "    let ready = true"},
            {"kind": "add", "oldNo": null, "newNo": 16, "text": "    let reviewSurface = true"},
            {"kind": "context", "oldNo": 16, "newNo": 17, "text": "}"}
          ]
        },
        {
          "header": "@@ -40,3 +43,6 @@",
          "oldStart": 40,
          "newStart": 43,
          "lines": [
            {"kind": "context", "oldNo": 40, "newNo": 43, "text": "// end of file"},
            {"kind": "add", "oldNo": null, "newNo": 44, "text": ""},
            {"kind": "add", "oldNo": null, "newNo": 45, "text": "// Lane G2 review surface"},
            {"kind": "add", "oldNo": null, "newNo": 46, "text": "// fixture hunk"}
          ]
        }
      ],
      "truncated": false
    }
    """

    public static let treeRootJSON = """
    [
      {"name": "docs", "isDir": true},
      {"name": "Packages", "isDir": true},
      {"name": "README.md", "isDir": false}
    ]
    """

    public static let treeDocsJSON = """
    [
      {"name": "Status.md", "isDir": false},
      {"name": "plans", "isDir": true}
    ]
    """

    public static let fileContentJSON = """
    {
      "content": "public struct Status {\\n    let ready = true\\n    let reviewSurface = true\\n}\\n",
      "truncated": false,
      "size": 78,
      "binary": false
    }
    """

    public func turnDiff(conversationID: String, turnID: String) async throws -> RepoDiffSummary {
        try Self.decode(Self.turnDiffJSON)
    }

    public func sessionDiff(conversationID: String) async throws -> RepoDiffSummary {
        try Self.decode(Self.sessionDiffJSON)
    }

    public func fileDiff(conversationID: String, path: String, turnID: String?) async throws -> RepoFileDiff {
        try Self.decode(Self.fileDiffJSON)
    }

    public func tree(conversationID: String, path: String) async throws -> [RepoTreeEntry] {
        if path.isEmpty || path == "." {
            return try Self.decode(Self.treeRootJSON)
        }
        if path == "docs" {
            return try Self.decode(Self.treeDocsJSON)
        }
        if path.hasPrefix("Packages") {
            return [
                RepoTreeEntry(name: "LancerKit", isDir: true),
            ]
        }
        return []
    }

    public func file(conversationID: String, path: String, maxBytes: Int) async throws -> RepoFileContent {
        if path.hasSuffix(".png") || path.hasSuffix(".jpg") {
            return RepoFileContent(content: "", truncated: false, size: 2048, binary: true)
        }
        var content: RepoFileContent = try Self.decode(Self.fileContentJSON)
        if maxBytes > 0, content.content.utf8.count > maxBytes {
            let prefix = String(content.content.prefix(maxBytes))
            content = RepoFileContent(
                content: prefix,
                truncated: true,
                size: content.size,
                binary: false
            )
        }
        return content
    }

    public static func decode<T: Decodable>(_ json: String) throws -> T {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
