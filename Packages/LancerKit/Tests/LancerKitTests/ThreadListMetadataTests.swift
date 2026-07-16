import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("ThreadListMetadata")
struct ThreadListMetadataTests {
    @Test("diffTotals from RepoDiffSummary matches SessionDiffPill totals")
    func diffTotalsFromSummary() {
        let summary = RepoDiffSummary(
            supported: true,
            files: [
                RepoDiffFile(path: "a.swift", added: 10, removed: 2, status: "modified"),
                RepoDiffFile(path: "b.swift", added: 5, removed: 1, status: "modified"),
            ],
            totalAdded: 15,
            totalRemoved: 3
        )
        let totals = ThreadListMetadata.diffTotals(from: summary)
        #expect(totals?.added == 15)
        #expect(totals?.removed == 3)
        #expect(ThreadListMetadata.diffTotals(from: RepoDiffSummary(
            supported: true, files: [], totalAdded: 0, totalRemoved: 0
        )) == nil)
    }

    @Test("diffTotals aggregates tool artifact added/removed")
    func diffTotalsFromToolArtifacts() {
        let artifacts = [
            ChatArtifact(
                conversationID: "c1", turnID: "t1", runID: "r1", kind: .tool,
                title: "Edit",
                payloadJSON: #"{"name":"Edit","added":4,"removed":1}"#,
                status: .done
            ),
            ChatArtifact(
                conversationID: "c1", turnID: "t1", runID: "r1", kind: .tool,
                title: "Edit",
                payloadJSON: #"{"name":"Edit","added":2,"removed":3}"#,
                status: .done
            ),
            ChatArtifact(
                conversationID: "c1", turnID: "t1", runID: "r1", kind: .receipt,
                title: "Receipt", status: .done
            ),
        ]
        let totals = ThreadListMetadata.diffTotals(fromArtifacts: artifacts)
        #expect(totals?.added == 6)
        #expect(totals?.removed == 4)
    }

    @Test("diffTotals prefers RepoDiffSummary-shaped .diff artifact")
    func diffTotalsPrefersDiffArtifact() {
        let summaryJSON = """
        {"supported":true,"files":[{"path":"a.swift","added":9,"removed":1,"status":"modified"}],\
        "totalAdded":9,"totalRemoved":1}
        """
        let artifacts = [
            ChatArtifact(
                conversationID: "c1", turnID: "t1", runID: "r1", kind: .tool,
                title: "Edit",
                payloadJSON: #"{"name":"Edit","added":100,"removed":100}"#,
                status: .done
            ),
            ChatArtifact(
                conversationID: "c1", turnID: "t1", runID: "r1", kind: .diff,
                title: "Diff", payloadJSON: summaryJSON, status: .done
            ),
        ]
        let totals = ThreadListMetadata.diffTotals(fromArtifacts: artifacts)
        #expect(totals?.added == 9)
        #expect(totals?.removed == 1)
    }

    @Test("previewSnippet collapses whitespace and caps length")
    func previewSnippet() {
        let turn = ChatTurn(
            conversationID: "c1", ordinal: 0, prompt: "short ask",
            runID: "r1", status: .completed,
            assistantText: "Hello\n\nworld   again"
        )
        #expect(ThreadListMetadata.previewSnippet(lastTurn: turn) == "Hello world again")

        let long = String(repeating: "a", count: ThreadListMetadata.previewMaxCharacters + 20)
        let longTurn = ChatTurn(
            conversationID: "c1", ordinal: 0, prompt: "p",
            runID: "r1", status: .completed, assistantText: long
        )
        let snippet = ThreadListMetadata.previewSnippet(lastTurn: longTurn)
        #expect(snippet?.hasSuffix("…") == true)
        #expect((snippet?.count ?? 0) == ThreadListMetadata.previewMaxCharacters + 1)

        let promptOnly = ChatTurn(
            conversationID: "c1", ordinal: 0, prompt: "  just the prompt  ",
            runID: "r1", status: .completed, assistantText: "   "
        )
        #expect(ThreadListMetadata.previewSnippet(lastTurn: promptOnly) == "just the prompt")
        #expect(ThreadListMetadata.previewSnippet(lastTurn: nil) == nil)
    }

    @Test("isUnread compares last activity to last opened")
    func isUnread() {
        let activity = Date(timeIntervalSince1970: 200)
        #expect(ThreadListMetadata.isUnread(lastActivityAt: activity, lastOpenedAt: nil))
        #expect(ThreadListMetadata.isUnread(
            lastActivityAt: activity,
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        ))
        #expect(!ThreadListMetadata.isUnread(
            lastActivityAt: activity,
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        ))
        #expect(!ThreadListMetadata.isUnread(
            lastActivityAt: activity,
            lastOpenedAt: Date(timeIntervalSince1970: 300)
        ))
    }

    @Test("threadItem hydrates preview unread and diff fields")
    func threadItemHydration() {
        let conversation = ChatConversation(
            title: "Fix flow", agentID: "a", hostName: "mac", cwd: "/Users/dev/r",
            lastActivityAt: Date(timeIntervalSince1970: 500)
        )
        let turn = ChatTurn(
            conversationID: conversation.id, ordinal: 0, prompt: "go",
            runID: "r1", status: .completed, assistantText: "Done with the patch."
        )
        let item = WorkspaceRepoCatalog.threadItem(
            conversation: conversation,
            lastTurn: turn,
            includeRepoName: false,
            addedLines: 12,
            removedLines: 3,
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(item.addedLines == 12)
        #expect(item.removedLines == 3)
        #expect(item.previewSnippet == "Done with the patch.")
        #expect(item.unread)
    }
}
