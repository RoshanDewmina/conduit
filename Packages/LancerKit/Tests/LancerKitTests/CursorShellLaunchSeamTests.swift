import Testing
@testable import AppFeature

@Suite("CursorShellLaunchSeam")
struct CursorShellLaunchSeamTests {
    @Test("mock shell alone enables mock")
    func mockAlone() {
        #expect(CursorShellLaunchSeam.usesMockCursorShell(cursorShell: "1", cursorShellLive: nil) == true)
    }

    @Test("live alone disables mock")
    func liveAlone() {
        #expect(CursorShellLaunchSeam.usesMockCursorShell(cursorShell: nil, cursorShellLive: "1") == false)
    }

    @Test("live wins when both are set — dual launch must not hide Remove/Clear-all")
    func liveWinsOverMock() {
        #expect(CursorShellLaunchSeam.usesMockCursorShell(cursorShell: "1", cursorShellLive: "1") == false)
    }

    @Test("neither env uses production root (not mock)")
    func neither() {
        #expect(CursorShellLaunchSeam.usesMockCursorShell(cursorShell: nil, cursorShellLive: nil) == false)
    }
}
