import Testing
import Foundation
@testable import TerminalEngine
@testable import SSHTransport

// MARK: - Thread-safe box for @Sendable closure captures in tests

/// A simple reference-type box used to capture mutable values inside
/// `@Sendable` closures in unit tests.  The test code is serial and
/// single-threaded so the unchecked Sendable conformance is safe here.
private final class Box<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Mock shell

/// A controlled `SSHShell` substitute used in `PTYBridge` tests.
///
/// Because `SSHShell.init` is `private`, we use `SSHShell.makeManual` (the
/// package-internal factory) to construct a shell whose byte stream we control
/// by calling `feedBytes(_:)` and `finishStream()`.
///
/// All interaction is actor-isolated, matching the `SSHShell` actor contract.
struct MockShellHandle: Sendable {
    let shell: SSHShell

    init() {
        // Use the internal manual factory — no real SSH connection required.
        shell = SSHShell.makeManual { _ in }
    }

    func feed(_ bytes: [UInt8]) async {
        await shell.feedBytes(bytes)
    }

    func finish() async {
        await shell.finishStream()
    }
}

// MARK: - Terminal factory

/// Creates a no-op RawTerminalView suitable for unit tests.
/// On iOS the UIViewRepresentable version needs explicit streams;
/// on macOS the stub's no-arg init is used.
@MainActor
private func makeMockTerminal() -> RawTerminalView {
#if canImport(UIKit) && canImport(SwiftTerm)
    let (stream, _) = AsyncStream<[UInt8]>.makeStream()
    return RawTerminalView(feed: stream, onUserBytes: { _ in }, onResize: { _, _ in })
#else
    return RawTerminalView()
#endif
}

// MARK: - Tests

@MainActor
@Suite("PTYBridge")
struct PTYBridgeTests {

    // MARK: - Alt-screen enter

    @Test("alt-screen enter sets escalationDetected")
    func escalationOnAltScreen() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        // Start pump in a background task.
        let pumpTask = Task { await bridge.start() }

        // Feed the alt-screen enter sequence: \x1b[?1049h
        await mock.feed([0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68])
        await mock.finish()
        await pumpTask.value

        let detected = await bridge.escalationDetected
        #expect(detected == true, "escalationDetected should be true after \\x1b[?1049h")
    }

    // MARK: - Alt-screen exit

    @Test("alt-screen exit sets deescalationDetected")
    func deescalationOnAltScreenExit() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let pumpTask = Task { await bridge.start() }

        // Feed the alt-screen exit sequence: \x1b[?1049l
        await mock.feed([0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x6c])
        await mock.finish()
        await pumpTask.value

        let detected = await bridge.deescalationDetected
        #expect(detected == true, "deescalationDetected should be true after \\x1b[?1049l")
    }

    // MARK: - No false positives

    @Test("unrelated bytes do not trigger escalation flags")
    func noFalsePositives() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let pumpTask = Task { await bridge.start() }

        // Plain text output
        await mock.feed(Array("hello world\r\n".utf8))
        await mock.finish()
        await pumpTask.value

        let esc = await bridge.escalationDetected
        let deesc = await bridge.deescalationDetected
        #expect(esc == false, "escalationDetected should remain false for plain text")
        #expect(deesc == false, "deescalationDetected should remain false for plain text")
    }

    // MARK: - Sequence embedded mid-chunk

    @Test("escalation sequence detected when embedded in larger chunk")
    func embeddedSequence() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let pumpTask = Task { await bridge.start() }

        var chunk = Array("some prefix ".utf8)
        chunk += [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68]
        chunk += Array(" suffix".utf8)
        await mock.feed(chunk)
        await mock.finish()
        await pumpTask.value

        let detected = await bridge.escalationDetected
        #expect(detected == true, "escalationDetected should be true when sequence is embedded in chunk")
    }

    // MARK: - OSC 133 C → onCommandStart

    @Test("OSC 133 C fires onCommandStart callback")
    func osc133CFiresCommandStart() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let fired = Box(false)
        await bridge.configure(onCommandStart: { fired.value = true })

        let pumpTask = Task { await bridge.start() }

        let osc133c: [UInt8] = [0x1b, 0x5d] + Array("133;C".utf8) + [0x07]
        await mock.feed(osc133c)
        await mock.finish()
        await pumpTask.value

        #expect(fired.value == true, "onCommandStart should fire on OSC 133;C")
    }

    // MARK: - OSC 133 D;N → onCommandDone with exit code

    @Test("OSC 133 D;42 fires onCommandDone with exit code 42")
    func osc133DFiresCommandDone() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let received = Box<Int?>(nil)
        await bridge.configure(onCommandDone: { code in received.value = code })

        let pumpTask = Task { await bridge.start() }

        let osc133d: [UInt8] = [0x1b, 0x5d] + Array("133;D;42".utf8) + [0x07]
        await mock.feed(osc133d)
        await mock.finish()
        await pumpTask.value

        #expect(received.value == 42, "onCommandDone should receive exit code 42")
    }

    // MARK: - OSC 7 → onCWDUpdate

    @Test("OSC 7 fires onCWDUpdate with correct path")
    func osc7FiresCWDUpdate() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let received = Box<String?>(nil)
        await bridge.configure(onCWDUpdate: { path in received.value = path })

        let pumpTask = Task { await bridge.start() }

        let osc7: [UInt8] = [0x1b, 0x5d] + Array("7;file://hostname/Users/alice".utf8) + [0x07]
        await mock.feed(osc7)
        await mock.finish()
        await pumpTask.value

        #expect(received.value == "/Users/alice", "onCWDUpdate should deliver the path sans hostname")
    }

    // MARK: - OSC 133 Z → shell probe result

    @Test("OSC 133 Z records shell probe result")
    func osc133ZRecordsShellProbeResult() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let pumpTask = Task { await bridge.start() }

        let osc133z: [UInt8] = [0x1b, 0x5d] + Array("133;Z;3.7.1".utf8) + [0x07]
        await mock.feed(osc133z)
        await mock.finish()
        await pumpTask.value

        let probeResult = await bridge.shellProbeResult
        #expect(probeResult == "3.7.1", "OSC 133;Z should populate shellProbeResult")
    }

    // MARK: - OSC stripping: clean bytes omit the OSC sequence

    @Test("onBlockBytes receives bytes with OSC sequences stripped")
    func osc133StrippedFromBlockBytes() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let output = Box(Data())
        await bridge.configure(onBlockBytes: { bytes in output.value.append(contentsOf: bytes) })

        let pumpTask = Task { await bridge.start() }

        var chunk = Array("hello".utf8)
        chunk += [0x1b, 0x5d] + Array("133;C".utf8) + [0x07]
        chunk += Array(" world".utf8)
        await mock.feed(chunk)
        await mock.finish()
        await pumpTask.value

        let text = String(data: output.value, encoding: .utf8) ?? ""
        #expect(text == "hello world", "OSC 133;C should be stripped from onBlockBytes output")
    }

    // MARK: - Phase 1: OSC 133 A fires onPromptStart

    @Test("OSC 133 A fires onPromptStart callback")
    func osc133AFiresPromptStart() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let fired = Box(false)
        await bridge.configure(onPromptStart: { fired.value = true })

        let pumpTask = Task { await bridge.start() }

        let osc133a: [UInt8] = [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        await mock.feed(osc133a)
        await mock.finish()
        await pumpTask.value

        #expect(fired.value == true, "onPromptStart should fire on OSC 133;A")
    }

    // MARK: - Phase 1: OSC 133 B fires onPromptEnd

    @Test("OSC 133 B fires onPromptEnd callback")
    func osc133BFiresPromptEnd() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let fired = Box(false)
        await bridge.configure(onPromptEnd: { fired.value = true })

        let pumpTask = Task { await bridge.start() }

        let osc133b: [UInt8] = [0x1b, 0x5d] + Array("133;B".utf8) + [0x07]
        await mock.feed(osc133b)
        await mock.finish()
        await pumpTask.value

        #expect(fired.value == true, "onPromptEnd should fire on OSC 133;B")
    }

    // MARK: - Phase 1: Full A→C→D sequence drives marker count

    @Test("Full OSC 133 A→C→D sequence fires all three callbacks in order")
    func osc133FullSequenceCallbacks() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let order = Box<[String]>([])
        await bridge.configure(
            onPromptStart:  { order.value.append("A") },
            onCommandStart: { order.value.append("C") },
            onCommandDone:  { code in order.value.append("D;\(code)") }
        )

        let pumpTask = Task { await bridge.start() }

        // Emulate the postcmd + preexec sequence:
        // D;0  A  (postcmd)  →  C  (preexec)  →  D;0  A  (next postcmd)
        var sequence: [UInt8] = []
        sequence += [0x1b, 0x5d] + Array("133;D;0".utf8) + [0x07]   // previous command done
        sequence += [0x1b, 0x5d] + Array("133;A".utf8)  + [0x07]   // prompt start
        sequence += [0x1b, 0x5d] + Array("133;C".utf8)  + [0x07]   // preexec
        sequence += [0x1b, 0x5d] + Array("133;D;1".utf8) + [0x07]  // command done, exit 1
        sequence += [0x1b, 0x5d] + Array("133;A".utf8)  + [0x07]   // next prompt start
        await mock.feed(sequence)
        await mock.finish()
        await pumpTask.value

        #expect(order.value == ["D;0", "A", "C", "D;1", "A"],
                "Callbacks should fire in A → C → D order matching OSC 133 sequence")
    }

    // MARK: - Phase 1: Smart-dash mutation protection

    @Test("OSC stripping preserves -- and other shell syntax verbatim")
    func shellSyntaxPreservedInCleanBytes() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let output = Box(Data())
        await bridge.configure(onBlockBytes: { bytes in output.value.append(contentsOf: bytes) })

        let pumpTask = Task { await bridge.start() }

        // Simulate output that contains shell syntax which iOS would mutate
        let shellSyntax = "claude --version | grep -E '^[0-9]'"
        await mock.feed(Array(shellSyntax.utf8))
        await mock.finish()
        await pumpTask.value

        let text = String(data: output.value, encoding: .utf8) ?? ""
        #expect(text == shellSyntax, "Double-dashes and pipes must arrive unchanged")
    }

    // MARK: - Phase 1: OSC 133 A is a no-op for onCommandStart

    @Test("OSC 133 A does not fire onCommandStart")
    func osc133ADoesNotFireCommandStart() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let startFired = Box(false)
        await bridge.configure(onCommandStart: { startFired.value = true })

        let pumpTask = Task { await bridge.start() }

        let osc133a: [UInt8] = [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        await mock.feed(osc133a)
        await mock.finish()
        await pumpTask.value

        #expect(startFired.value == false,
                "OSC 133;A (prompt_start) must not fire onCommandStart")
    }

    // MARK: - Phase-7 re-engagement: onPromptStart fires on every 133;A

    // The Phase-7 raw fallback (isRaw = true) is managed by SessionViewModel, not
    // PTYBridge.  PTYBridge's responsibility: fire onPromptStart on every 133;A
    // without any single-fire gating.  If the bridge ever stopped firing after the
    // first 133;A, SessionViewModel.onPromptStart (which does `isRaw = false`) would
    // never be reached and the terminal would stay stuck in raw mode indefinitely.

    @Test("Phase-7 re-engagement: onPromptStart fires on every 133;A, not just the first")
    func phase7ReengagementPromptStartFiresRepeatedly() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let count = Box(0)
        await bridge.configure(onPromptStart: { count.value += 1 })

        let pumpTask = Task { await bridge.start() }

        // Feed two separate 133;A markers separated by plain output.
        // This models: (1) integration-script precmd fires 133;A (ghost block),
        //              (2) clear command's precmd fires 133;A (real idle block),
        // or in Phase-7 terms: raw fallback is active, then 133;A arrives and
        // re-engages block mode — the callback must fire to let the VM flip isRaw.
        let osc133a: [UInt8] = [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        var sequence: [UInt8] = []
        sequence += osc133a
        sequence += Array("$ ".utf8)    // simulated prompt text between the two markers
        sequence += osc133a
        await mock.feed(sequence)
        await mock.finish()
        await pumpTask.value

        #expect(count.value == 2,
                "onPromptStart must fire once per 133;A — no single-fire gating in PTYBridge")
    }

    // MARK: - Phase-7 re-engagement: 133;A fires integrationActive

    @Test("Phase-7 re-engagement: first 133;A sets integrationActive on the bridge")
    func phase7FirstOSC133ASetsIntegrationActive() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let pumpTask = Task { await bridge.start() }

        let osc133a: [UInt8] = [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        await mock.feed(osc133a)
        await mock.finish()
        await pumpTask.value

        let active = await bridge.integrationActive
        #expect(active == true,
                "integrationActive should be true once any OSC 133 marker is received")
    }

    // MARK: - Hardening: rapid consecutive commands

    @Test("rapid A→C→D→A→C→D sequence — all callbacks fire in order")
    func rapidConsecutiveCommands() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let order = Box<[String]>([])
        await bridge.configure(
            onPromptStart:  { order.value.append("A") },
            onCommandStart: { order.value.append("C") },
            onCommandDone:  { code in order.value.append("D;\(code)") }
        )

        let pumpTask = Task { await bridge.start() }

        // Simulate two commands back-to-back with no extra output between them.
        var seq: [UInt8] = []
        seq += [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]   // prompt 1
        seq += [0x1b, 0x5d] + Array("133;C".utf8) + [0x07]   // cmd 1 start
        seq += [0x1b, 0x5d] + Array("133;D;0".utf8) + [0x07] // cmd 1 done
        seq += [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]   // prompt 2
        seq += [0x1b, 0x5d] + Array("133;C".utf8) + [0x07]   // cmd 2 start
        seq += [0x1b, 0x5d] + Array("133;D;1".utf8) + [0x07] // cmd 2 done
        seq += [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]   // final prompt
        await mock.feed(seq)
        await mock.finish()
        await pumpTask.value

        #expect(order.value == ["A", "C", "D;0", "A", "C", "D;1", "A"],
                "All callbacks must fire in order for rapid consecutive commands")
    }

    // MARK: - Hardening: no-output command (A→C→D with no bytes between C and D)

    @Test("no-output command — A→C→D fires all three callbacks with empty output")
    func noOutputCommand() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let output = Box(Data())
        let events = Box<[String]>([])
        await bridge.configure(
            onBlockBytes:   { bytes in output.value.append(contentsOf: bytes) },
            onPromptStart:  { events.value.append("A") },
            onCommandStart: { events.value.append("C") },
            onCommandDone:  { code in events.value.append("D;\(code)") }
        )

        let pumpTask = Task { await bridge.start() }

        // No bytes between C and D — simulates a command with no stdout/stderr.
        var seq: [UInt8] = []
        seq += [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        seq += [0x1b, 0x5d] + Array("133;C".utf8) + [0x07]
        seq += [0x1b, 0x5d] + Array("133;D;0".utf8) + [0x07]
        seq += [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        await mock.feed(seq)
        await mock.finish()
        await pumpTask.value

        #expect(events.value == ["A", "C", "D;0", "A"],
                "No-output command should still fire A, C, D;0 in order")
        let text = String(data: output.value, encoding: .utf8) ?? ""
        #expect(text.isEmpty, "No-output command should produce no block bytes")
    }

    // MARK: - Hardening: stderr-only output lands in block bytes

    @Test("stderr-only output — bytes reach onBlockBytes even with no stdout")
    func stderrOnlyOutput() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let output = Box(Data())
        await bridge.configure(onBlockBytes: { bytes in output.value.append(contentsOf: bytes) })

        let pumpTask = Task { await bridge.start() }

        // OSC 133 A/C framing with error output between them.
        var seq: [UInt8] = []
        seq += [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        seq += [0x1b, 0x5d] + Array("133;C".utf8) + [0x07]
        seq += Array("error: command not found\r\n".utf8)
        seq += [0x1b, 0x5d] + Array("133;D;127".utf8) + [0x07]
        await mock.feed(seq)
        await mock.finish()
        await pumpTask.value

        let text = String(data: output.value, encoding: .utf8) ?? ""
        #expect(text.contains("error: command not found"),
                "stderr output should appear in onBlockBytes")
    }

    // MARK: - Hardening: Ctrl-C mid-stream (D with exit code 130)

    @Test("Ctrl-C mid-stream — D;130 fires onCommandDone with exit code 130")
    func ctrlCMidStream() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let received = Box<Int?>(nil)
        await bridge.configure(onCommandDone: { code in received.value = code })

        let pumpTask = Task { await bridge.start() }

        // Ctrl-C sends SIGINT; zsh/bash exit code 130 (128 + SIGINT=2).
        var seq: [UInt8] = []
        seq += [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        seq += [0x1b, 0x5d] + Array("133;C".utf8) + [0x07]
        seq += Array("partial output\r\n".utf8)
        seq += [0x03]  // ^C byte
        seq += [0x1b, 0x5d] + Array("133;D;130".utf8) + [0x07]
        seq += [0x1b, 0x5d] + Array("133;A".utf8) + [0x07]
        await mock.feed(seq)
        await mock.finish()
        await pumpTask.value

        #expect(received.value == 130, "Ctrl-C should fire onCommandDone with exit code 130")
    }

    // MARK: - TUIDetector: alt-screen enter triggers escalation

    @Test("TUIDetector: alt-screen enter \\e[?1049h triggers shouldEscalate")
    func tuiDetectorAltScreenEnter() {
        let data = Data("\u{1B}[?1049h".utf8)
        #expect(TUIDetector.shouldEscalate(to: data),
                "\\e[?1049h (alt-screen enter) must trigger TUIDetector")
    }

    @Test("TUIDetector: older alt-screen \\e[?47h triggers shouldEscalate")
    func tuiDetectorLegacyAltScreen() {
        let data = Data("\u{1B}[?47h".utf8)
        #expect(TUIDetector.shouldEscalate(to: data),
                "\\e[?47h (legacy alt-screen) must trigger TUIDetector")
    }

    @Test("TUIDetector: application cursor keys \\e[?1h triggers shouldEscalate")
    func tuiDetectorAppCursorKeys() {
        let data = Data("\u{1B}[?1h".utf8)
        #expect(TUIDetector.shouldEscalate(to: data),
                "\\e[?1h (application cursor keys) must trigger TUIDetector")
    }

    @Test("TUIDetector: cursor home \\e[H triggers shouldEscalate")
    func tuiDetectorCursorHome() {
        let data = Data("\u{1B}[H".utf8)
        #expect(TUIDetector.shouldEscalate(to: data),
                "\\e[H (cursor home) must trigger TUIDetector for inline-TUI detection")
    }

    @Test("TUIDetector: erase display \\e[2J triggers shouldEscalate")
    func tuiDetectorEraseDisplay() {
        let data = Data("\u{1B}[2J".utf8)
        #expect(TUIDetector.shouldEscalate(to: data),
                "\\e[2J (erase display) must trigger TUIDetector for inline-TUI detection")
    }

    @Test("TUIDetector: hide cursor \\e[?25l triggers shouldEscalate")
    func tuiDetectorHideCursor() {
        let data = Data("\u{1B}[?25l".utf8)
        #expect(TUIDetector.shouldEscalate(to: data),
                "\\e[?25l (hide cursor) must trigger TUIDetector")
    }

    @Test("TUIDetector: plain text does not trigger shouldEscalate")
    func tuiDetectorPlainText() {
        let data = Data("hello world\r\n".utf8)
        #expect(!TUIDetector.shouldEscalate(to: data),
                "Plain text must not trigger TUIDetector")
    }

    @Test("TUIDetector: normal SGR sequence does not trigger shouldEscalate")
    func tuiDetectorSGROnly() {
        let data = Data("\u{1B}[32mgreen text\u{1B}[0m".utf8)
        #expect(!TUIDetector.shouldEscalate(to: data),
                "SGR color sequences must not trigger TUIDetector — only alt-screen/cursor-positioning signals TUI")
    }

    @Test("TUIDetector: promptEditing-only sequences (ZLE \\e[?1h) do not bypass the .submitted guard")
    func tuiDetectorSubmittedGuardIntent() {
        // This test verifies the detector fires on ZLE app-cursor-key mode
        // (\\e[?1h) — which is what zsh emits at every prompt. The *guard*
        // that prevents idle promptEditing from escalating lives in
        // SessionViewModel.onBlockBytes, not TUIDetector itself.  TUIDetector
        // returns true for \\e[?1h so the VM can catch it for .submitted blocks.
        let data = Data("\u{1B}[?1h".utf8)
        #expect(TUIDetector.shouldEscalate(to: data),
                "TUIDetector must return true for \\e[?1h; the .submitted guard is in the VM")
    }

    // MARK: - Hardening: bracketedPaste flag toggled by sequences

    @Test("bracketed-paste enable sequence sets bracketedPasteActive")
    func bracketedPasteEnable() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let pumpTask = Task { await bridge.start() }

        // \e[?2004h — enable bracketed paste mode
        let enable: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x68]
        await mock.feed(enable)
        await mock.finish()
        await pumpTask.value

        let active = await bridge.bracketedPasteActive
        #expect(active == true, "bracketedPasteActive should be true after \\e[?2004h")
    }

    @Test("bracketed-paste disable sequence clears bracketedPasteActive")
    func bracketedPasteDisable() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let pumpTask = Task { await bridge.start() }

        // Enable then disable
        let enable: [UInt8]  = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x68]
        let disable: [UInt8] = [0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x6c]
        await mock.feed(enable + disable)
        await mock.finish()
        await pumpTask.value

        let active = await bridge.bracketedPasteActive
        #expect(active == false, "bracketedPasteActive should be false after \\e[?2004l")
    }
}
