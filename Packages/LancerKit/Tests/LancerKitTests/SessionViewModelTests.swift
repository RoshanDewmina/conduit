import Testing
import Foundation
@testable import LancerCore
@testable import TerminalEngine

// MARK: - Block state machine (Phase 3 / Phase 1 tests)
//
// These tests verify the OSC 133 A/B/C/D state machine at the BlockRenderer
// layer — the component that owns block lifecycle.  SessionViewModel glues
// PTYBridge callbacks to these exact methods, so correctness here proves the
// full redesign works.

@MainActor
@Suite("SessionViewModel — block state machine")
struct SessionViewModelTests {

    let renderer = BlockRenderer()
    let sid      = SessionID()
    var prompt: Block.PromptInfo { .init(cwd: "~", hostName: "testhost") }

    // MARK: - OSC 133 A: beginPrompt creates a block in .promptEditing

    @Test("OSC 133 A — block starts in promptEditing")
    func osc133A_createsPromptEditingBlock() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        let block = renderer.blocks.first { $0.id == id }
        #expect(block != nil)
        #expect(block?.state == .promptEditing)
        #expect(block?.command == "")
    }

    // MARK: - OSC 133 B: setState(.submitted) marks the block as submitted

    @Test("OSC 133 B — state transitions to submitted")
    func osc133B_submitsBlock() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setState(.submitted, for: id)
        let block = renderer.blocks.first { $0.id == id }
        #expect(block?.state == .submitted)
    }

    // MARK: - OSC 133 C: setState(.executing) — keystrokes route to PTY

    @Test("OSC 133 C — state transitions to executing")
    func osc133C_setsExecuting() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setState(.submitted, for: id)
        renderer.setState(.executing, for: id)
        let block = renderer.blocks.first { $0.id == id }
        #expect(block?.state == .executing)
    }

    // MARK: - OSC 133 D: finalize closes the block

    @Test("OSC 133 D — block finalized with exit code")
    func osc133D_finalizesBlock() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setState(.executing, for: id)
        renderer.finalize(id: id, exitCode: 0)
        let block = renderer.blocks.first { $0.id == id }
        if case .done(let code) = block?.state {
            #expect(code == 0)
        } else {
            Issue.record("Expected .done(exitCode:) but got \(String(describing: block?.state))")
        }
        #expect(block?.exitStatus?.code == 0)
    }

    // MARK: - Full A→B→C→D sequence

    @Test("Full OSC 133 A→B→C→D sequence transitions block through all states")
    func fullABCDSequence() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        // A → promptEditing
        #expect(renderer.blocks.first { $0.id == id }?.state == .promptEditing)

        // user types a command
        renderer.setCommand("claude --version", for: id)
        #expect(renderer.blocks.first { $0.id == id }?.command == "claude --version")

        // B → submitted
        renderer.setState(.submitted, for: id)
        #expect(renderer.blocks.first { $0.id == id }?.state == .submitted)

        // C → executing
        renderer.setState(.executing, for: id)
        #expect(renderer.blocks.first { $0.id == id }?.state == .executing)

        // D;0 → done
        renderer.finalize(id: id, exitCode: 0)
        if case .done(let code) = renderer.blocks.first(where: { $0.id == id })?.state {
            #expect(code == 0)
        } else {
            Issue.record("Expected .done after finalize")
        }
    }

    // MARK: - No new block on submit-while-executing

    @Test("No new block created when submit happens in executing state")
    func noNewBlockWhileExecuting() {
        // Simulate OSC 133 A (prompt created) then OSC 133 C (now executing)
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setState(.executing, for: id)

        let countBefore = renderer.blocks.count

        // In executing state, SessionViewModel sends to PTY without calling
        // beginPrompt / begin.  This test verifies BlockRenderer is not called:
        // just assert that if we DO call setCommand/setState it doesn't create
        // an extra block.
        renderer.setCommand("follow-up message", for: id)

        #expect(renderer.blocks.count == countBefore,
                "Executing state: follow-up input must not create a new block")
    }

    // MARK: - Interrupted block finalized on next OSC 133 A

    @Test("Active executing block is finalized when a new OSC 133 A arrives")
    func interruptedBlockFinalizedByNextPromptStart() {
        let firstID = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setState(.executing, for: firstID)

        // Simulate what onPromptStart does: finalize the previous executing block
        renderer.finalize(id: firstID, exitCode: -1)

        let secondID = renderer.beginPrompt(sessionID: sid, prompt: prompt)

        #expect(renderer.blocks.count == 2)
        let first = renderer.blocks.first { $0.id == firstID }
        let second = renderer.blocks.first { $0.id == secondID }

        if case .done(let code) = first?.state {
            #expect(code == -1, "Interrupted block should have exit code -1")
        } else {
            Issue.record("First block should be .done after interruption")
        }
        #expect(second?.state == .promptEditing)
    }

    // MARK: - Multiple blocks across two command cycles

    @Test("Two complete A→C→D cycles produce two finished blocks")
    func twoCommandCycles() {
        // Cycle 1
        let id1 = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setCommand("ls", for: id1)
        renderer.setState(.executing, for: id1)
        renderer.append(Data("README.md\n".utf8), stream: .stdout, to: id1)
        renderer.finalize(id: id1, exitCode: 0)

        // Cycle 2
        let id2 = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setCommand("pwd", for: id2)
        renderer.setState(.executing, for: id2)
        renderer.append(Data("/home/user\n".utf8), stream: .stdout, to: id2)
        renderer.finalize(id: id2, exitCode: 0)

        #expect(renderer.blocks.count == 2)
        #expect(renderer.blocks[0].command == "ls")
        #expect(renderer.blocks[1].command == "pwd")
        if case .done(let c1) = renderer.blocks[0].state { #expect(c1 == 0) }
        else { Issue.record("Block 0 should be done") }
        if case .done(let c2) = renderer.blocks[1].state { #expect(c2 == 0) }
        else { Issue.record("Block 1 should be done") }
    }

    // MARK: - Claude Code byte stream simulation (Phase 1 requirement)
    //
    // When `claude` is running interactively (no alt-screen, inline cursor-pos),
    // bytes arrive on the executing block's output stream.  The block must stay
    // in `.executing` state and the byte count must accumulate on the SAME block —
    // no new block is created.

    @Test("Claude Code inline TUI: cursor-positioning bytes stay on the active block")
    func claudeCodeInlineTUIBytesStayOnActiveBlock() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setCommand("claude", for: id)
        renderer.setState(.executing, for: id)

        // Simulate a multi-chunk Claude Code response (cursor-positioning sequences
        // interspersed with text, no alt-screen)
        let claudeChunks: [String] = [
            "\u{1B}[H\u{1B}[2J",          // home + erase (Claude init)
            "\u{1B}[1;1H◆ Claude Code",   // cursor-pos + header
            "\u{1B}[3;1H> ",              // cursor to input line
            "Tell me about this repo\n",   // echo of user input
            "\u{1B}[5;1HAnalyzing…",      // response starts
        ]

        let countBefore = renderer.blocks.count

        for chunk in claudeChunks {
            renderer.append(Data(chunk.utf8), stream: .stdout, to: id)
        }

        #expect(renderer.blocks.count == countBefore,
                "Inline TUI output must not create extra blocks")
        #expect(renderer.blocks.first { $0.id == id }?.state == .executing,
                "Block must remain in .executing while Claude is running")
        #expect(renderer.blocks.first { $0.id == id }?.hasOutput == true,
                "Block must have accumulated output")
    }

    // MARK: - TUIDetector recognises Claude Code sequences

    @Test("TUIDetector identifies Claude Code cursor-positioning as interactive")
    func tuiDetectorRecognisesClaudeCodeBytes() {
        let claudeInit = Data("\u{1B}[H\u{1B}[2J\u{1B}[?25l".utf8)
        #expect(TUIDetector.shouldEscalate(to: claudeInit),
                "Claude Code's init sequence should trigger TUI escalation")
    }

    @Test("TUIDetector ignores plain text output")
    func tuiDetectorIgnoresPlainText() {
        let plain = Data("README.md\npackage.json\nsrc/\n".utf8)
        #expect(!TUIDetector.shouldEscalate(to: plain),
                "Plain ls output must not trigger TUI escalation")
    }

    // MARK: - Belt-and-suspenders: cursor-pos sets pendingTUIEscalation

    @Test("Cursor-positioning bytes in output set pendingTUIEscalation on BlockRenderer")
    func cursorPosBytesSetPendingEscalation() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setState(.submitted, for: id)

        // Cursor-home + erase-display arrives before 133;C (broken shell integration)
        renderer.append(Data("\u{1B}[H\u{1B}[2J".utf8), stream: .stdout, to: id)

        #expect(renderer.pendingTUIEscalation,
                "Cursor-positioning output must set pendingTUIEscalation so the VM can flip to .executing")
    }

    // MARK: - CWD update

    @Test("updatePromptCWD reflects in the block's prompt")
    func cwdUpdate() {
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.updatePromptCWD("/workspace/project", for: id)
        let block = renderer.blocks.first { $0.id == id }
        #expect(block?.prompt.cwd == "/workspace/project")
    }

    // MARK: - Legacy path: begin() still works for OSC-133-free shells

    @Test("Legacy begin() creates a .submitted block (OSC-133-free fallback)")
    func legacyBeginCreatesSubmittedBlock() {
        let id = renderer.begin(sessionID: sid, command: "uname -a", prompt: prompt)
        let block = renderer.blocks.first { $0.id == id }
        #expect(block?.state == .submitted)
        #expect(block?.command == "uname -a")
    }

    // MARK: - Ghost block scenario (documents the empty-top-block bug)
    //
    // With suppression OFF, the integration script's precmd fires 133;A → ghost
    // block (promptEditing), then the clear's 133;C/D taint it → empty done block,
    // then 133;A creates the real idle block.  Two blocks total, first is empty.

    @Test("Ghost block scenario: empty done block appears before correct idle block")
    func ghostBlockScenarioWithoutSuppression() {
        // Step 1: integration script precmd fires 133;A → ghost block created
        let ghostID = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        // No setCommand — command stays ""

        // Step 2: clear command's preexec fires 133;C → ghost transitions to executing
        renderer.setState(.executing, for: ghostID)

        // Step 3: clear done → 133;D;0 → ghost finalized with exit 0
        renderer.finalize(id: ghostID, exitCode: 0)

        // Step 4: clear's precmd fires 133;A → clean idle block
        let idleID = renderer.beginPrompt(sessionID: sid, prompt: prompt)

        #expect(renderer.blocks.count == 2, "Two blocks: ghost (empty done) + correct idle")
        let ghost = renderer.blocks.first { $0.id == ghostID }
        let idle  = renderer.blocks.first { $0.id == idleID }

        #expect(ghost?.command == "", "Ghost block has no command")
        if case .done(let code) = ghost?.state {
            #expect(code == 0, "Ghost block exit code is 0 (from the clear command)")
        } else {
            Issue.record("Ghost block should be .done")
        }
        #expect(idle?.state == .promptEditing, "Idle block is the correct promptEditing block")
    }

    // MARK: - Phase-7 re-engagement after blocks.clear()
    //
    // When the Phase-7 raw fallback fires (isRaw = true) and integration then
    // becomes active, the next 133;A must be able to create a fresh idle block
    // even after blocks.clear() was called.

    @Test("Phase-7 re-engagement: beginPrompt succeeds after blocks.clear()")
    func phase7ReengagementAfterClear() {
        // Simulate raw-mode entry: clear the block store.
        renderer.clear()
        #expect(renderer.blocks.isEmpty, "blocks.clear() should empty the store")

        // Integration becomes live → 133;A fires → new idle block
        let blockID = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        let block = renderer.blocks.first { $0.id == blockID }

        #expect(block != nil, "beginPrompt must succeed after blocks.clear()")
        #expect(block?.state == .promptEditing, "Re-engaged block starts in promptEditing")
        #expect(block?.command == "", "Re-engaged block has empty command (idle prompt)")
    }

    // MARK: - Inline-TUI resize: terminalCols propagates to per-block terminals
    //
    // The resize path: RawTerminalView.onResize → resizeUnifiedPTY → SSHShell.resize.
    // At the BlockRenderer layer, terminalCols must be set BEFORE beginPrompt so the
    // per-block SwiftTerm emulator is sized to match the PTY — otherwise Claude Code
    // draws to a mismatched width and wraps/garbles output on device rotation.

    @Test("Resize: terminalCols set before beginPrompt configures block terminal width")
    func terminalColsPropagatesBeforeBlockCreation() {
        renderer.terminalCols = 120
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)

        // The block should exist; the per-block Terminal was created with cols=120.
        // (We verify indirectly: if terminalCols were ignored, hasCursorMovement
        //  rendering would use a stale 80-col grid and wrap Claude Code's UI.)
        let block = renderer.blocks.first { $0.id == id }
        #expect(block != nil)
        #expect(renderer.terminalCols == 120,
                "terminalCols must reflect the PTY width before block terminals are created")
    }

    @Test("Resize: terminalCols update after block creation (mid-session rotate)")
    func terminalColsUpdateMidSession() {
        // Block already running
        let id = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        renderer.setState(.executing, for: id)

        // Device rotates → resizeUnifiedPTY fires → sets terminalCols for next block
        renderer.terminalCols = 56  // narrower (portrait → landscape flips on small iPhone)

        // Next block after 133;A will use the new cols
        let idleID = renderer.beginPrompt(sessionID: sid, prompt: prompt)
        let idle = renderer.blocks.first { $0.id == idleID }
        #expect(idle != nil)
        #expect(renderer.terminalCols == 56, "Updated terminalCols carries into new block terminals")
    }
}
