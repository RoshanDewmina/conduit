#if os(iOS)
import Testing
@testable import AppFeature

@Suite("CursorAddRepoSheet")
struct CursorAddRepoSheetTests {

    @Test("live shell never shows mock repo list")
    func liveShellUsesHonestContent() {
        #expect(CursorAddRepoSheetPresentation.showsMockRepoList(liveBridgeIsSet: true) == false)
    }

    #if DEBUG
    @Test("mock shell shows DEBUG repo list when no live bridge")
    func mockShellShowsPixelReferenceList() {
        #expect(CursorAddRepoSheetPresentation.showsMockRepoList(liveBridgeIsSet: false) == true)
    }
    #endif
}
#endif
