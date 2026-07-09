import Foundation
import Testing
@testable import AppFeature

@Suite("CursorTranscriptAutoScrollPolicy")
struct CursorTranscriptAutoScrollPolicyTests {
    @Test("isNearBottom uses Orca 48pt threshold")
    func nearBottomThreshold() {
        #expect(CursorTranscriptAutoScrollPolicy.nearBottomThreshold == 48)
        #expect(CursorTranscriptAutoScrollPolicy.isNearBottom(offsetFromBottom: 0))
        #expect(CursorTranscriptAutoScrollPolicy.isNearBottom(offsetFromBottom: 48))
        #expect(!CursorTranscriptAutoScrollPolicy.isNearBottom(offsetFromBottom: 49))
    }

    @Test("jump-to-latest only when detached with content below")
    func jumpVisibility() {
        #expect(
            !CursorTranscriptAutoScrollPolicy.shouldShowJumpToLatest(
                isFollowing: true,
                hasContentBelow: true
            )
        )
        #expect(
            !CursorTranscriptAutoScrollPolicy.shouldShowJumpToLatest(
                isFollowing: false,
                hasContentBelow: false
            )
        )
        #expect(
            CursorTranscriptAutoScrollPolicy.shouldShowJumpToLatest(
                isFollowing: false,
                hasContentBelow: true
            )
        )
    }

    @Test("scroll near bottom re-engages follow and clears unread")
    func scrollReFollow() {
        var state = CursorTranscriptAutoScrollPolicy.FollowState(isFollowing: false, unreadCount: 3)
        state = state.handlingScroll(offsetFromBottom: 10)
        #expect(state.isFollowing)
        #expect(state.unreadCount == 0)
    }

    @Test("scroll away from bottom detaches without clearing unread")
    func scrollDetach() {
        var state = CursorTranscriptAutoScrollPolicy.FollowState(isFollowing: true, unreadCount: 0)
        state = state.handlingScroll(offsetFromBottom: 100)
        #expect(!state.isFollowing)
        #expect(state.unreadCount == 0)
    }

    @Test("new row while detached accrues unread; while following does not")
    func unreadAccrual() {
        var following = CursorTranscriptAutoScrollPolicy.FollowState(isFollowing: true, unreadCount: 0)
        following = following.handlingNewRow(offsetFromBottom: 0)
        #expect(following.isFollowing)
        #expect(following.unreadCount == 0)

        var detached = CursorTranscriptAutoScrollPolicy.FollowState(isFollowing: false, unreadCount: 0)
        detached = detached.handlingNewRow(offsetFromBottom: 200)
        #expect(!detached.isFollowing)
        #expect(detached.unreadCount == 1)
        detached = detached.handlingNewRow(offsetFromBottom: 200)
        #expect(detached.unreadCount == 2)
    }

    @Test("jump to latest re-follows and clears unread")
    func jumpClears() {
        let state = CursorTranscriptAutoScrollPolicy.FollowState(isFollowing: false, unreadCount: 5)
            .handlingJumpToLatest()
        #expect(state.isFollowing)
        #expect(state.unreadCount == 0)
    }
}

@Suite("CursorStreamingTextSmoother")
struct CursorStreamingTextSmootherTests {
    @Test("overlay wins only while strictly longer than persisted text")
    func antiFlicker() {
        #expect(
            CursorStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: "Hello world",
                persistedAssistantText: "Hello"
            ) == "Hello world"
        )
        #expect(
            CursorStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: "Hello",
                persistedAssistantText: "Hello world"
            ) == "Hello world"
        )
        #expect(
            CursorStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: "Hello",
                persistedAssistantText: "Hello"
            ) == "Hello"
        )
        #expect(
            CursorStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: nil,
                persistedAssistantText: "Done."
            ) == "Done."
        )
        #expect(
            CursorStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: "Streaming…",
                persistedAssistantText: ""
            ) == "Streaming…"
        )
    }

    @Test("commit and settle gates use elapsed thresholds")
    func pacingGates() {
        #expect(
            CursorStreamingTextSmoother.shouldCommit(
                elapsedSinceLastCommit: .milliseconds(100),
                minInterval: .milliseconds(100)
            )
        )
        #expect(
            !CursorStreamingTextSmoother.shouldCommit(
                elapsedSinceLastCommit: .milliseconds(50),
                minInterval: .milliseconds(100)
            )
        )
        #expect(
            CursorStreamingTextSmoother.isSettled(
                elapsedSinceLastDelta: .milliseconds(320),
                settleDelay: .milliseconds(320)
            )
        )
        #expect(
            !CursorStreamingTextSmoother.isSettled(
                elapsedSinceLastDelta: .milliseconds(100),
                settleDelay: .milliseconds(320)
            )
        )
    }
}

@Suite("CursorMarkdownPreprocessor")
struct CursorMarkdownPreprocessorTests {
    @Test("normalizes unicode bullets to markdown list markers")
    func unicodeBullets() {
        let input = "Notes:\n• First\n◦ Second\n  ▪ Nested"
        let out = CursorMarkdownPreprocessor.preprocess(input)
        #expect(out.contains("- First"))
        #expect(out.contains("- Second"))
        #expect(out.contains("  - Nested"))
    }

    @Test("wraps bare Codex Begin Patch blocks in diff fences")
    func wrapBeginPatch() {
        let input = """
        Here is the change:
        *** Begin Patch
        *** Update File: a.swift
        +let x = 1
        *** End Patch
        Done.
        """
        let out = CursorMarkdownPreprocessor.preprocess(input)
        #expect(out.contains("```diff"))
        #expect(out.contains("*** Begin Patch"))
        #expect(out.contains("*** End Patch"))
        #expect(out.contains("```\nDone."))
    }

    @Test("wraps bare diff --git hunks when no fences present")
    func wrapDiffGit() {
        let input = """
        diff --git a/foo b/foo
        --- a/foo
        +++ b/foo
        @@ -1 +1 @@
        -a
        +b
        """
        let out = CursorMarkdownPreprocessor.preprocess(input)
        #expect(out.hasPrefix("```diff\n"))
        #expect(out.hasSuffix("```"))
    }

    @Test("does not wrap patches when fences already present")
    func skipsPatchWrapWhenFenced() {
        let input = """
        ```
        *** Begin Patch
        *** End Patch
        ```
        """
        let out = CursorMarkdownPreprocessor.preprocess(input)
        // wrapBarePatchBlocks is a no-op once any fence exists; do not double-fence.
        #expect(!out.contains("```diff"))
        #expect(out.contains("*** Begin Patch"))
    }
}
