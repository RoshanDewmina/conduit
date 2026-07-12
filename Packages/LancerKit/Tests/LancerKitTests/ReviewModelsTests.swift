import Foundation
import Testing
@testable import AppFeature

@Suite struct ReviewModelsTests {
    @Test("decodes turnDiff fixture verbatim")
    func decodeTurnDiff() throws {
        let summary: RepoDiffSummary = try FixtureReviewDataSource.decode(
            FixtureReviewDataSource.turnDiffJSON
        )
        #expect(summary.supported == true)
        #expect(summary.files.count == 3)
        #expect(summary.totalAdded == 232)
        #expect(summary.totalRemoved == 11)
        #expect(summary.files[0].path == "docs/Status.md")
        #expect(summary.files[0].added == 12)
        #expect(summary.files[0].removed == 3)
        #expect(summary.files[0].status == "modified")
        #expect(summary.files[2].status == "added")
        #expect(summary.titleLabel == "3 files changed")
        #expect(summary.countsLabel == "+232 −11")
        #expect(summary.hasChanges)
    }

    @Test("decodes sessionDiff fixture verbatim")
    func decodeSessionDiff() throws {
        let summary: RepoDiffSummary = try FixtureReviewDataSource.decode(
            FixtureReviewDataSource.sessionDiffJSON
        )
        #expect(summary.fileCount == 4)
        #expect(summary.totalAdded == 442)
        #expect(summary.totalRemoved == 11)
    }

    @Test("decodes fileDiff fixture with null line numbers")
    func decodeFileDiff() throws {
        let diff: RepoFileDiff = try FixtureReviewDataSource.decode(
            FixtureReviewDataSource.fileDiffJSON
        )
        #expect(diff.truncated == false)
        #expect(diff.hunks.count == 2)
        #expect(diff.hunks[0].oldStart == 14)
        #expect(diff.hunks[0].newStart == 14)
        #expect(diff.hunks[0].lines.count == 5)
        #expect(diff.hunks[0].lines[1].kind == .del)
        #expect(diff.hunks[0].lines[1].oldNo == 15)
        #expect(diff.hunks[0].lines[1].newNo == nil)
        #expect(diff.hunks[0].lines[2].kind == .add)
        #expect(diff.hunks[0].lines[2].oldNo == nil)
        #expect(diff.hunks[0].lines[2].newNo == 15)
    }

    @Test("decodes tree and file fixtures")
    func decodeTreeAndFile() throws {
        let tree: [RepoTreeEntry] = try FixtureReviewDataSource.decode(
            FixtureReviewDataSource.treeRootJSON
        )
        #expect(tree.count == 3)
        #expect(tree[0].name == "docs")
        #expect(tree[0].isDir == true)
        #expect(tree[2].isDir == false)

        let file: RepoFileContent = try FixtureReviewDataSource.decode(
            FixtureReviewDataSource.fileContentJSON
        )
        #expect(file.binary == false)
        #expect(file.truncated == false)
        #expect(file.size == 78)
        #expect(file.content.contains("reviewSurface"))
    }

    @Test("hunk maps to display rows preserving kind and numbers")
    func hunkToRows() throws {
        let diff: RepoFileDiff = try FixtureReviewDataSource.decode(
            FixtureReviewDataSource.fileDiffJSON
        )
        let rows = DiffHunkPresentation.rows(from: diff.hunks[0])
        #expect(rows.count == 5)
        #expect(rows[0].kind == .context)
        #expect(rows[0].displayLineNumber == 14)
        #expect(rows[1].kind == .del)
        #expect(rows[1].displayLineNumber == 15)
        #expect(rows[2].kind == .add)
        #expect(rows[2].displayLineNumber == 15)
        #expect(diff.hunks[0].sectionTitle.contains("Lines"))
        #expect(diff.hunks[0].addedCount == 2)
        #expect(diff.hunks[0].removedCount == 1)
    }

    @Test("comment queue formats chip and composer prefix")
    func commentQueueFormatting() {
        let comment = QueuedReviewComment(
            path: "docs/Status.md",
            line: 16,
            lineText: "    let reviewSurface = true",
            comment: "keep this flag"
        )
        #expect(comment.chipLabel == "Status.md:16 · keep this flag")
        #expect(comment.embedBlock == "docs/Status.md:16 — let reviewSurface = true — keep this flag")

        let second = QueuedReviewComment(
            path: "a.swift",
            line: 1,
            lineText: "import Foundation",
            comment: "ok"
        )
        let prefixed = ReviewCommentFormatting.composerPrefix(
            comments: [comment, second],
            prompt: "please revise"
        )
        #expect(prefixed.hasPrefix("docs/Status.md:16 —"))
        #expect(prefixed.contains("a.swift:1 — import Foundation — ok"))
        #expect(prefixed.hasSuffix("please revise"))
    }

    @Test("tree lazy-load merge is dirs-first and nested")
    func treeLazyLoadMerge() {
        var roots: [ReviewTreeNode] = ReviewTreeMerge.nodes(
            parentPath: "",
            entries: [
                RepoTreeEntry(name: "README.md", isDir: false),
                RepoTreeEntry(name: "docs", isDir: true),
                RepoTreeEntry(name: "Packages", isDir: true),
            ]
        )
        #expect(roots.map(\.name) == ["docs", "Packages", "README.md"])
        #expect(roots[0].children == nil)

        ReviewTreeMerge.mergeChildren(
            path: "docs",
            entries: [
                RepoTreeEntry(name: "Status.md", isDir: false),
                RepoTreeEntry(name: "plans", isDir: true),
            ],
            into: &roots
        )
        #expect(roots[0].isExpanded == true)
        #expect(roots[0].children?.map(\.name) == ["plans", "Status.md"])
        #expect(roots[0].children?.first?.path == "docs/plans")

        let filtered = ReviewTreeMerge.filter(nodes: roots, query: "Status")
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "docs")
        #expect(filtered[0].children?.count == 1)
        #expect(filtered[0].children?[0].name == "Status.md")
    }

    @Test("fixture data source drives turn/session/file/tree/file RPCs")
    func fixtureDataSource() async throws {
        let source = FixtureReviewDataSource()
        let turn = try await source.turnDiff(conversationID: "c1", turnID: "t1")
        #expect(turn.hasChanges)
        let session = try await source.sessionDiff(conversationID: "c1")
        #expect(session.totalAdded == 442)
        let diff = try await source.fileDiff(conversationID: "c1", path: "docs/Status.md", turnID: "t1")
        #expect(!diff.hunks.isEmpty)
        let tree = try await source.tree(conversationID: "c1", path: "")
        #expect(tree.contains(where: { $0.name == "docs" && $0.isDir }))
        let docs = try await source.tree(conversationID: "c1", path: "docs")
        #expect(docs.contains(where: { $0.name == "Status.md" }))
        let file = try await source.file(conversationID: "c1", path: "docs/Status.md", maxBytes: 10_000)
        #expect(!file.binary)
        #expect(!file.content.isEmpty)

        let relay = RelayReviewDataSource()
        let unsupported = try await relay.sessionDiff(conversationID: "c1")
        #expect(unsupported.supported == false)
        #expect(!unsupported.hasChanges)
    }
}
