import Foundation
import Testing
import LancerCore
@testable import AppFeature

@Suite("CursorConversationSearchSupport")
struct CursorConversationSearchSupportTests {
    @Test("scopedFTSQuery leaves All unscoped")
    func scopedQueryAll() {
        #expect(
            CursorConversationSearchSupport.scopedFTSQuery(
                rawQuery: "hello world",
                scope: .all
            ) == "hello world"
        )
    }

    @Test("scopedFTSQuery prefixes Prompts column")
    func scopedQueryPrompts() {
        #expect(
            CursorConversationSearchSupport.scopedFTSQuery(
                rawQuery: "fix bug",
                scope: .prompts
            ) == "prompt:fix prompt:bug"
        )
    }

    @Test("scopedFTSQuery prefixes Responses column")
    func scopedQueryResponses() {
        #expect(
            CursorConversationSearchSupport.scopedFTSQuery(
                rawQuery: "refactor",
                scope: .responses
            ) == "assistant_text:refactor"
        )
    }

    @Test("scopedFTSQuery prefixes Artifacts column")
    func scopedQueryArtifacts() {
        #expect(
            CursorConversationSearchSupport.scopedFTSQuery(
                rawQuery: "receipt",
                scope: .artifacts
            ) == "artifact_text:receipt"
        )
    }

    @Test("scopedFTSQuery trims whitespace")
    func scopedQueryTrims() {
        #expect(
            CursorConversationSearchSupport.scopedFTSQuery(
                rawQuery: "  hello   world  ",
                scope: .all
            ) == "hello world"
        )
        #expect(
            CursorConversationSearchSupport.scopedFTSQuery(
                rawQuery: "   ",
                scope: .all
            ) == ""
        )
    }

    @Test("repoName uses cwd basename")
    func repoName() {
        #expect(
            CursorConversationSearchSupport.repoName(from: "/Users/dev/command-center")
            == "command-center"
        )
        #expect(CursorConversationSearchSupport.repoName(from: "") == "")
    }

    @Test("contextLine combines repo and host")
    func contextLine() {
        let conv = ChatConversation(
            title: "T",
            agentID: "a",
            hostName: "Mac Studio",
            cwd: "/Users/dev/command-center"
        )
        #expect(
            CursorConversationSearchSupport.contextLine(for: conv)
            == "command-center · Mac Studio"
        )
    }

    @Test("contextLine omits empty parts")
    func contextLineMinimal() {
        let noHost = ChatConversation(title: "T", agentID: "a", hostName: "", cwd: "/tmp/proj")
        #expect(CursorConversationSearchSupport.contextLine(for: noHost) == "proj")

        let hostOnly = ChatConversation(title: "T", agentID: "a", hostName: "Relay", cwd: "")
        #expect(CursorConversationSearchSupport.contextLine(for: hostOnly) == "Relay")
    }

    @Test("displaySnippet omits title duplicate")
    func displaySnippet() {
        let conv = ChatConversation(title: "Fix onboarding", agentID: "a", hostName: "h", cwd: "/p")
        let titleOnly = ChatConversationSearchResult(conversation: conv, snippet: "Fix onboarding")
        #expect(CursorConversationSearchSupport.displaySnippet(for: titleOnly) == nil)

        let bodyHit = ChatConversationSearchResult(
            conversation: conv,
            snippet: "…matched assistant reply…"
        )
        #expect(
            CursorConversationSearchSupport.displaySnippet(for: bodyHit)
            == "…matched assistant reply…"
        )
    }

    @Test("matchRanges finds case-insensitive terms")
    func matchRanges() {
        let ranges = CursorConversationSearchSupport.matchRanges(
            in: "Hello HELLO world",
            query: "hello"
        )
        #expect(ranges.count == 2)
    }

    @Test("relativeTimestamp formats abbreviated relative time")
    func relativeTimestamp() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hourAgo = now.addingTimeInterval(-3_600)
        let label = CursorConversationSearchSupport.relativeTimestamp(hourAgo, now: now)
        #expect(!label.isEmpty)
    }
}
