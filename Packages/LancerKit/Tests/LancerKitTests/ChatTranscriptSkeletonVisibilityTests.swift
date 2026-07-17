import Testing
@testable import AppFeature

@Suite("ChatTranscriptSkeletonVisibility")
struct ChatTranscriptSkeletonVisibilityTests {
    @Test("shows skeleton only while loading with no cached content")
    func showsWhileLoadingEmpty() {
        #expect(
            ChatTranscriptSkeletonVisibility.shouldShow(
                hasCachedContent: false,
                isLoadInFlight: true
            )
        )
    }

    @Test("never replaces cached content with a skeleton")
    func keepsCachedContent() {
        #expect(
            !ChatTranscriptSkeletonVisibility.shouldShow(
                hasCachedContent: true,
                isLoadInFlight: true
            )
        )
        #expect(
            !ChatTranscriptSkeletonVisibility.shouldShow(
                hasCachedContent: true,
                isLoadInFlight: false
            )
        )
    }

    @Test("hides skeleton when load finishes empty")
    func hidesWhenIdleEmpty() {
        #expect(
            !ChatTranscriptSkeletonVisibility.shouldShow(
                hasCachedContent: false,
                isLoadInFlight: false
            )
        )
    }
}
