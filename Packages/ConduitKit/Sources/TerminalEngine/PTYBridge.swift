import Foundation
import SSHTransport

// NOTE: No `import SwiftUI` or `import UIKit` — this is an engine module.

/// Bridges an `SSHShell` (raw byte stream from a remote PTY) to a
/// `RawTerminalView` (SwiftTerm renderer) and back.
///
/// `PTYBridge` is the "glue" actor for raw / TUI mode:
/// - It pumps `shell.bytes` into `terminal.feed(_:)`.
/// - It scans each inbound chunk for alt-screen control sequences and
///   sets `escalationDetected` / `deescalationDetected` accordingly.
/// - It forwards user input from the keyboard rail to `shell.send(_:)`.
///
/// ## Alt-screen detection
/// The VT100/ANSI sequences that TUI programs use to enter/leave the
/// alternate screen buffer are:
/// - Enter: `ESC [ ? 1 0 4 9 h`  (bytes: `\x1b[?1049h`)
/// - Exit:  `ESC [ ? 1 0 4 9 l`  (bytes: `\x1b[?1049l`)
///
/// ## Usage
/// ```swift
/// let bridge = PTYBridge(shell: shell, terminal: terminalView)
/// await bridge.start()               // pump loop; returns when channel closes
/// try await bridge.sendInput(bytes)  // forward keyboard bytes
/// ```
public actor PTYBridge {

    // MARK: - Escalation flags

    /// `true` once an alt-screen *enter* sequence (`\x1b[?1049h`) is seen.
    public private(set) var escalationDetected: Bool = false

    /// `true` once an alt-screen *exit* sequence (`\x1b[?1049l`) is seen.
    public private(set) var deescalationDetected: Bool = false

    // MARK: - Dependencies

    private let shell: SSHShell
    private let terminal: RawTerminalView

    // MARK: - Alt-screen byte sequences

    /// Bytes for `\x1b[?1049h` — enter alternate screen.
    private static let altScreenEnter: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68
    ]

    /// Bytes for `\x1b[?1049l` — leave alternate screen.
    private static let altScreenExit: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x6c
    ]

    // MARK: - Init

    public init(shell: SSHShell, terminal: RawTerminalView) {
        self.shell = shell
        self.terminal = terminal
    }

    // MARK: - Pump

    /// Start pumping bytes from the shell into the terminal renderer.
    ///
    /// Returns when the shell's byte stream ends (remote PTY closed).
    /// Safe to call from a detached `Task`.
    public func start() async {
        for await chunk in await shell.bytes {
            scan(chunk)
            await terminal.feed(chunk)
        }
    }

    // MARK: - Input

    /// Forward raw keyboard bytes to the remote PTY.
    public func sendInput(_ bytes: [UInt8]) async throws {
        try await shell.send(bytes)
    }

    // MARK: - Alt-screen scanner (private)

    private func scan(_ chunk: [UInt8]) {
        if !escalationDetected, contains(chunk, subsequence: Self.altScreenEnter) {
            escalationDetected = true
        }
        if !deescalationDetected, contains(chunk, subsequence: Self.altScreenExit) {
            deescalationDetected = true
        }
    }

    /// Sliding-window subsequence search. Acceptable for typical PTY chunk
    /// sizes (< 64 KB); O(n·m) complexity is fine here.
    private func contains(_ haystack: [UInt8], subsequence needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let limit = haystack.count - needle.count
        for i in 0 ... limit {
            if haystack[i ..< i + needle.count].elementsEqual(needle) { return true }
        }
        return false
    }
}
