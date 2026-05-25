import Testing
@testable import TerminalEngine
@testable import SSHTransport

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
private func makeMockTerminal() -> RawTerminalView {
#if canImport(UIKit) && canImport(SwiftTerm)
    let (stream, _) = AsyncStream<[UInt8]>.makeStream()
    return RawTerminalView(feed: stream, onUserBytes: { _ in }, onResize: { _, _ in })
#else
    return RawTerminalView()
#endif
}

// MARK: - Tests

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

        // Allow the pump iteration to process the chunk.
        try await Task.sleep(nanoseconds: 10_000_000) // 10 ms

        let detected = await bridge.escalationDetected
        #expect(detected == true, "escalationDetected should be true after \\x1b[?1049h")

        await mock.finish()
        await pumpTask.value
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

        try await Task.sleep(nanoseconds: 10_000_000) // 10 ms

        let detected = await bridge.deescalationDetected
        #expect(detected == true, "deescalationDetected should be true after \\x1b[?1049l")

        await mock.finish()
        await pumpTask.value
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

        try await Task.sleep(nanoseconds: 10_000_000) // 10 ms

        let esc = await bridge.escalationDetected
        let deesc = await bridge.deescalationDetected
        #expect(esc == false, "escalationDetected should remain false for plain text")
        #expect(deesc == false, "deescalationDetected should remain false for plain text")

        await mock.finish()
        await pumpTask.value
    }

    // MARK: - Sequence embedded mid-chunk

    @Test("escalation sequence detected when embedded in larger chunk")
    func embeddedSequence() async throws {
        let mock = MockShellHandle()
        let terminal = makeMockTerminal()
        let bridge = PTYBridge(shell: mock.shell, terminal: terminal)

        let pumpTask = Task { await bridge.start() }

        // Embed \x1b[?1049h inside a larger byte array
        var chunk = Array("some prefix ".utf8)
        chunk += [0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68]
        chunk += Array(" suffix".utf8)
        await mock.feed(chunk)

        try await Task.sleep(nanoseconds: 10_000_000) // 10 ms

        let detected = await bridge.escalationDetected
        #expect(detected == true, "escalationDetected should be true when sequence is embedded in chunk")

        await mock.finish()
        await pumpTask.value
    }
}
