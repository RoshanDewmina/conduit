import Testing
import Foundation
@testable import ConduitCore
@testable import TerminalEngine

// MARK: - B4: History restore on reconnect

@MainActor
@Suite("BlockRenderer — history restore (prepend)")
struct HistoryRestoreTests {

    let renderer = BlockRenderer()
    let sid = SessionID()
    var prompt: Block.PromptInfo { .init(cwd: "~", hostName: "srv") }

    @Test("prepend inserts finished blocks before live blocks")
    func prependPutsHistoryFirst() {
        // Live block (from current shell session)
        let liveID = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setCommand("echo live", for: liveID)
        renderer.setState(.submitted, for: liveID)

        // Simulate persisted history
        let hist1 = makeFinishedBlock(command: "ls", exitCode: 0)
        let hist2 = makeFinishedBlock(command: "pwd", exitCode: 0)

        renderer.appendHistory([hist1, hist2])

        #expect(renderer.blocks.count == 3)
        #expect(renderer.blocks[0].command == "ls",  "history first")
        #expect(renderer.blocks[1].command == "pwd", "history second")
        #expect(renderer.blocks[2].command == "echo live", "live block last")
    }

    @Test("prepend with empty array is a no-op")
    func prependEmptyIsNoOp() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.appendHistory([])
        #expect(renderer.blocks.count == 1)
        #expect(renderer.blocks[0].id == id)
    }

    @Test("prepend de-duplication: existing block ID is skipped by caller")
    func callerCanDeduplicateByID() {
        // Simulate a block already in the renderer (persisted mid-session)
        let existingBlock = makeFinishedBlock(command: "git status", exitCode: 0)
        renderer.appendHistory([existingBlock])
        #expect(renderer.blocks.count == 1)

        // Caller filters by existing IDs before calling prepend again
        let existingIDs = Set(renderer.blocks.map(\.id))
        let toInsert = [existingBlock].filter { !existingIDs.contains($0.id) }
        renderer.appendHistory(toInsert)

        #expect(renderer.blocks.count == 1, "de-duplication prevents double insertion")
    }

    @Test("prepended blocks are always .done state")
    func prependedBlocksAreDone() {
        let b1 = makeFinishedBlock(command: "make test", exitCode: 0)
        let b2 = makeFinishedBlock(command: "make build", exitCode: 1)
        renderer.appendHistory([b1, b2])

        for block in renderer.blocks {
            if case .done(let code) = block.state {
                #expect(code == block.exitStatus?.code)
            } else {
                Issue.record("Restored block must be in .done state, got \(block.state)")
            }
        }
    }

    // MARK: - Helper

    private func makeFinishedBlock(command: String, exitCode: Int) -> Block {
        let sid2 = SessionID()
        var block = Block(
            sessionID: sid2,
            prompt: prompt,
            command: command,
            state: .done(exitCode: exitCode)
        )
        block.exitStatus = ExitStatus(code: exitCode)
        block.finishedAt = .now
        return block
    }
}
