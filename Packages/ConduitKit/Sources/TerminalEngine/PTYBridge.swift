import Foundation
import SSHTransport

// NOTE: No `import SwiftUI` or `import UIKit` — this is an engine module.

/// Bridges an `SSHShell` (raw byte stream from a remote PTY) to a
/// `RawTerminalView` (SwiftTerm renderer) and back.
///
/// `PTYBridge` is the glue actor for raw/TUI mode *and* for the unified-PTY path:
/// - Pumps `shell.bytes` into `terminal.feed(_:)` (SwiftTerm always gets the
///   raw stream so its internal model stays in sync).
/// - Scans each chunk for alt-screen control sequences and fires
///   `onAltScreenEnter` / `onAltScreenExit` (and sets the
///   `escalationDetected` / `deescalationDetected` flags).
/// - Parses OSC 133 (A/B/C/D) and OSC 7 sequences, firing `onCommandStart`,
///   `onCommandDone`, and `onCWDUpdate` callbacks.
/// - For block-mode rendering, delivers OSC-stripped bytes via `onBlockBytes`
///   so that shell-integration escape sequences never appear as garbage text.
///
/// ## Alt-screen detection (existing)
/// - Enter: `\x1b[?1049h`
/// - Exit:  `\x1b[?1049l`
///
/// ## OSC 133 (shell integration)
/// - A: prompt_start — ignored for now
/// - B: prompt_end   — ignored for now
/// - C: preexec      → `onCommandStart?()`
/// - D;N: postcmd    → `onCommandDone?(exitCode)`
///
/// ## OSC 7 (CWD notification)
/// - `\e]7;file://hostname/path\a` → `onCWDUpdate?(path)`
///
/// ## Usage
/// ```swift
/// let bridge = PTYBridge(shell: shell, terminal: terminalView)
/// await bridge.start()                 // pump loop; returns when channel closes
/// try await bridge.sendInput(bytes)    // forward keyboard bytes
/// ```
public actor PTYBridge {

    // MARK: - Escalation flags (block-mode / raw-mode toggle)

    /// `true` once an alt-screen *enter* sequence (`\x1b[?1049h`) is seen.
    public private(set) var escalationDetected: Bool = false

    /// `true` once an alt-screen *exit* sequence (`\x1b[?1049l`) is seen.
    public private(set) var deescalationDetected: Bool = false

    /// `true` while the remote shell/application has enabled bracketed-paste
    /// mode (`\e[?2004h`). Callers should wrap pasted text in `\e[200~…\e[201~`
    /// when this flag is set so each paste arrives as a single atomic edit.
    public private(set) var bracketedPasteActive: Bool = false

    // MARK: - Block lifecycle callbacks
    // All closures are @Sendable so they can be set from any isolation domain
    // via the `configure(...)` method.

    /// Called when OSC 133 A (prompt_start) arrives — the shell has displayed
    /// its prompt and is waiting for user input.  This is the signal to begin
    /// a new block in the `.promptEditing` state.
    private var onPromptStart: (@Sendable () -> Void)? = nil

    /// Called when OSC 133 B (prompt_end) arrives — the user's input has been
    /// accepted by the shell (cursor has moved past the prompt).  Optional;
    /// most shells do not emit B.
    private var onPromptEnd: (@Sendable () -> Void)? = nil

    /// Called when OSC 133 C (preexec) arrives — command has started executing.
    private var onCommandStart: (@Sendable () -> Void)? = nil

    /// Called when OSC 133 D;N (postcmd) arrives — command finished with the
    /// given exit code.
    private var onCommandDone: (@Sendable (Int) -> Void)? = nil

    /// Called when OSC 7 carries a new working directory path.
    private var onCWDUpdate: (@Sendable (String) -> Void)? = nil

    /// Called with OSC-stripped bytes for each PTY chunk while the bridge is
    /// **not** in alt-screen mode. Used by unified-PTY block rendering.
    private var onBlockBytes: (@Sendable ([UInt8]) -> Void)? = nil

    /// Called when an alt-screen *enter* sequence is detected (TUI program).
    private var onAltScreenEnter: (@Sendable () -> Void)? = nil

    /// Called when an alt-screen *exit* sequence is detected.
    private var onAltScreenExit: (@Sendable () -> Void)? = nil

    /// Set all callbacks in a single actor hop. Call this before
    /// `start()` to guarantee the callbacks are in place before bytes arrive.
    public func configure(
        onBlockBytes:    (@Sendable ([UInt8]) -> Void)? = nil,
        onPromptStart:   (@Sendable () -> Void)?       = nil,
        onPromptEnd:     (@Sendable () -> Void)?       = nil,
        onCommandStart:  (@Sendable () -> Void)?       = nil,
        onCommandDone:   (@Sendable (Int) -> Void)?    = nil,
        onCWDUpdate:     (@Sendable (String) -> Void)? = nil,
        onAltScreenEnter:(@Sendable () -> Void)?       = nil,
        onAltScreenExit: (@Sendable () -> Void)?       = nil
    ) {
        self.onBlockBytes     = onBlockBytes
        self.onPromptStart    = onPromptStart
        self.onPromptEnd      = onPromptEnd
        self.onCommandStart   = onCommandStart
        self.onCommandDone    = onCommandDone
        self.onCWDUpdate      = onCWDUpdate
        self.onAltScreenEnter = onAltScreenEnter
        self.onAltScreenExit  = onAltScreenExit
    }

    // MARK: - Diagnostics

    /// The most recently detected shell name (e.g. "zsh", "bash", "fish").
    /// Populated either by a `133;Z;` probe reply or set externally.
    public var detectedShell: String? = nil

    /// Raw value from the fish-detection probe (`133;Z;<value>`).
    /// Non-nil and non-empty means fish; nil or empty means sh/bash/zsh.
    /// Set by the first `133;Z;` OSC body received.
    public private(set) var shellProbeResult: String? = nil

    /// The last ≤ 5 OSC 133/7 marker bodies that arrived, newest last.
    public private(set) var recentMarkers: [(marker: String, time: Date)] = []

    /// Whether at least one OSC 133 marker has been received this session —
    /// indicates that shell integration is working.
    public private(set) var integrationActive: Bool = false

    // MARK: - Dependencies

    private let shell: SSHShell
    private let terminal: RawTerminalView

    // MARK: - Alt-screen byte sequences

    private static let altScreenEnter: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x68  // \e[?1049h
    ]
    private static let altScreenExit: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x31, 0x30, 0x34, 0x39, 0x6c  // \e[?1049l
    ]

    // MARK: - Bracketed-paste byte sequences

    private static let bracketedPasteEnable: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x68  // \e[?2004h
    ]
    private static let bracketedPasteDisable: [UInt8] = [
        0x1b, 0x5b, 0x3f, 0x32, 0x30, 0x30, 0x34, 0x6c  // \e[?2004l
    ]

    // MARK: - Alt-screen state

    private var inAltScreen: Bool = false

    // MARK: - OSC parser state machine (shared: parses + strips simultaneously)

    private enum OSCState {
        case normal
        case sawEsc        // saw 0x1b, waiting for ] (0x5d)
        case inOSC         // inside an OSC sequence body
        case inOSCSawEsc   // inside OSC, saw 0x1b — checking for ST (0x5c)
    }

    private var oscState: OSCState = .normal
    private var oscBody: [UInt8] = []  // accumulates OSC body bytes

    // MARK: - Init

    public init(shell: SSHShell, terminal: RawTerminalView) {
        self.shell = shell
        self.terminal = terminal
    }

    // MARK: - Reset (used by unified PTY when re-entering alt-screen)

    /// Clear escalation/deescalation flags so alt-screen detection
    /// can fire again on the next TUI program launch.
    public func resetEscalationFlags() {
        escalationDetected = false
        deescalationDetected = false
    }

    // MARK: - Pump

    /// Start pumping bytes from the shell into the terminal renderer.
    ///
    /// Returns when the shell's byte stream ends (remote PTY closed).
    /// Safe to call from a detached `Task`.
    public func start() async {
        for await chunk in await shell.bytes {
            // 1. Alt-screen detection — kept for diagnostics + escalation flags,
            //    but no longer gates byte routing. The active block's embedded
            //    SwiftTerm handles `\e[?1049h` natively (it has its own primary
            //    and alt buffers), so the same byte path serves both inline
            //    TUIs (Claude/Codex) and alt-screen TUIs (htop/vim/tmux).
            scanAltScreen(chunk)

            // 2. OSC 133/7 parsing + simultaneous stripping
            //    Returns a clean copy with OSC sequences removed, suitable for
            //    block-mode rendering.
            let cleanBytes = parseAndStripOSC(chunk)

            // 3. Always feed SwiftTerm the raw bytes so its terminal model
            //    (cursor, scroll-back, colour) stays authoritative.
            await terminal.feed(chunk)

            // 4. Route clean bytes to the block renderer in all states.
            //    The view model decides whether to yield to a live in-block
            //    terminal handle or just keep the text-snapshot path.
            if let cb = onBlockBytes, !cleanBytes.isEmpty {
                cb(cleanBytes)
            }
        }
    }

    // MARK: - Input

    /// Forward raw keyboard bytes to the remote PTY.
    public func sendInput(_ bytes: [UInt8]) async throws {
        try await shell.send(bytes)
    }

    // MARK: - Alt-screen scanner

    private func scanAltScreen(_ chunk: [UInt8]) {
        if !escalationDetected, contains(chunk, subsequence: Self.altScreenEnter) {
            escalationDetected = true
            inAltScreen = true
            onAltScreenEnter?()
        }
        if !deescalationDetected, contains(chunk, subsequence: Self.altScreenExit) {
            deescalationDetected = true
            inAltScreen = false
            onAltScreenExit?()
        }
        if !bracketedPasteActive, contains(chunk, subsequence: Self.bracketedPasteEnable) {
            bracketedPasteActive = true
        } else if bracketedPasteActive, contains(chunk, subsequence: Self.bracketedPasteDisable) {
            bracketedPasteActive = false
        }
    }

    /// Boyer-Moore-Horspool-lite (linear) subsequence check. Acceptable for
    /// typical PTY chunk sizes (< 64 KB).
    private func contains(_ haystack: [UInt8], subsequence needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let limit = haystack.count - needle.count
        for i in 0 ... limit {
            if haystack[i ..< i + needle.count].elementsEqual(needle) { return true }
        }
        return false
    }

    // MARK: - OSC parser + stripper (combined, cross-chunk state)

    /// Parses OSC sequences out of `chunk`, firing appropriate callbacks, and
    /// returns the same bytes with all OSC sequences removed (so they don't
    /// appear as garbage text in block-mode output).
    private func parseAndStripOSC(_ chunk: [UInt8]) -> [UInt8] {
        var clean: [UInt8] = []
        clean.reserveCapacity(chunk.count)

        for byte in chunk {
            switch oscState {

            case .normal:
                if byte == 0x1b {
                    oscState = .sawEsc
                    // Don't emit yet — we don't know if this is OSC or CSI
                } else {
                    clean.append(byte)
                }

            case .sawEsc:
                if byte == 0x5d {       // ESC ] — OSC start
                    oscState = .inOSC
                    oscBody.removeAll()
                } else {
                    // Not OSC (e.g. ESC [ CSI, ESC O SS3 …) — emit both bytes.
                    clean.append(0x1b)
                    clean.append(byte)
                    oscState = .normal
                }

            case .inOSC:
                if byte == 0x07 {       // BEL — OSC terminator
                    dispatchOSC(String(bytes: oscBody, encoding: .utf8) ?? "")
                    oscBody.removeAll()
                    oscState = .normal
                } else if byte == 0x1b {
                    oscState = .inOSCSawEsc
                } else {
                    oscBody.append(byte)
                }

            case .inOSCSawEsc:
                if byte == 0x5c {       // ST (ESC \) — OSC terminator
                    dispatchOSC(String(bytes: oscBody, encoding: .utf8) ?? "")
                    oscBody.removeAll()
                    oscState = .normal
                } else {
                    // Not ST — the ESC was part of the OSC body.
                    oscBody.append(0x1b)
                    oscBody.append(byte)
                    oscState = .inOSC
                }
            }
        }

        return clean
    }

    private func dispatchOSC(_ body: String) {
        guard !body.isEmpty else { return }
        recordMarker(body)
        integrationActive = true

        if body.hasPrefix("133;") {
            dispatchOSC133(String(body.dropFirst(4)))
        } else if body.hasPrefix("7;") {
            dispatchOSC7(String(body.dropFirst(2)))
        }
        // Shell-detection probe reply. Older builds emitted this as `Z;<value>`;
        // the current probe uses `133;Z;<value>` so it can share the shell-
        // integration OSC namespace. Non-empty value means fish.
        if body.hasPrefix("Z;"), shellProbeResult == nil {
            shellProbeResult = String(body.dropFirst(2))
        }
    }

    private func dispatchOSC133(_ params: String) {
        switch params {
        case "A":
            // prompt_start — shell is now showing its prompt; begin a new block.
            onPromptStart?()
        case "B":
            // prompt_end — user input accepted; command about to run.
            onPromptEnd?()
        case "C":
            onCommandStart?()
        case "Z":
            if shellProbeResult == nil { shellProbeResult = "" }
        default:
            if params.hasPrefix("Z;") {
                if shellProbeResult == nil {
                    shellProbeResult = String(params.dropFirst(2))
                }
                return
            }
            guard params == "D" || params.hasPrefix("D;") else { return }
            let codeStr = params.count > 2 ? String(params.dropFirst(2)) : "0"
            let exitCode = Int(codeStr) ?? 0
            onCommandDone?(exitCode)
        }
    }

    private func dispatchOSC7(_ params: String) {
        // Expected format: file://hostname/path
        guard params.hasPrefix("file://") else { return }
        let afterScheme = params.dropFirst(7)   // strip "file://"
        // The first path component is the hostname; everything from the first
        // "/" onwards is the absolute path.
        if let slashIdx = afterScheme.firstIndex(of: "/") {
            let path = String(afterScheme[slashIdx...])
            guard !path.isEmpty else { return }
            onCWDUpdate?(path)
        }
    }

    private func recordMarker(_ body: String) {
        recentMarkers.append((marker: body, time: Date()))
        if recentMarkers.count > 5 { recentMarkers.removeFirst() }
        // Write diagnostics for the Settings view (no SwiftUI dependency needed).
        let ud = UserDefaults.standard
        ud.set(true, forKey: "conduitMarkersActive")
        ud.set(Date().timeIntervalSince1970, forKey: "conduitLastMarkerTime")
        if let shell = detectedShell {
            ud.set(shell, forKey: "conduitShellDetected")
        }
    }
}
