import Testing
import Foundation
@testable import ConduitCore
@testable import TerminalEngine

@MainActor
@Suite("BlockRenderer")
struct BlockRendererTests {

    @Test("begin -> append -> finalize")
    func lifecycle() {
        let r = BlockRenderer()
        let sid = SessionID()
        let id = r.begin(sessionID: sid, command: "ls", prompt: .init(cwd: "~", hostName: "h"))
        r.append(Data("hello\n".utf8), stream: .stdout, to: id)
        r.finalize(id: id, exitCode: 0)
        #expect(r.blocks.count == 1)
        #expect(r.blocks[0].exitStatus?.code == 0)
        #expect(r.blocks[0].hasOutput)
    }

    @Test("TUI detection sets pending flag")
    func tuiEscalation() {
        let r = BlockRenderer()
        let sid = SessionID()
        let id = r.begin(sessionID: sid, command: "vim", prompt: .init(cwd: "~", hostName: "h"))
        r.append(Data("\u{1B}[?1049h".utf8), stream: .stdout, to: id)
        #expect(r.pendingTUIEscalation)
    }

    @Test("collapse and star toggle")
    func toggles() {
        let r = BlockRenderer()
        let id = r.begin(sessionID: SessionID(), command: "ls", prompt: .init(cwd: "~", hostName: "h"))
        r.toggleCollapsed(id: id)
        r.toggleStarred(id: id)
        #expect(r.blocks[0].isCollapsed)
        #expect(r.blocks[0].isStarred)
    }
}
