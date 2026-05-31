import Foundation
import SwiftUI
import Observation
import ConduitCore
#if canImport(SwiftTerm)
import SwiftTerm
#endif

/// State container for a session's blocks. `@Observable` so SwiftUI views
/// re-render only the rows that change. Everything mutates on the main
/// actor; the SSH stream is funnelled through `append(_:stream:to:)` on
/// the main actor by the SessionViewModel.
@MainActor @Observable
public final class BlockRenderer {
    public private(set) var blocks: [Block] = []
    /// Set to `true` by `append` when cursor-positioning sequences arrive.
    /// SessionViewModel reads and resets this as a belt-and-suspenders hint
    /// to flip the active block to `.executing` even without a 133;C marker.
    public var pendingTUIEscalation = false

    /// Terminal column count used for per-block SwiftTerm emulators.
    /// Set by SessionViewModel from the PTY's reported cols so Claude Code
    /// draws its UI to the correct width.
    public var terminalCols: Int = 80

    // MARK: - SGR path (normal linear output — colors via ANSI parser)
    private var openState: [BlockID: SGRState] = [:]
    private var renderCache: [BlockID: AttributedString] = [:]
    private let parser = AnsiSGRParser()

    /// Maximum number of lines retained per block in the linear SGR path.
    /// When output exceeds this, the oldest lines are discarded and the count
    /// is recorded in `droppedLineCount` for the truncation affordance.
    public static let maxLinearLines = 2000

    /// Number of lines that have been silently discarded for each block.
    /// Non-zero entries power the "⚠ N earlier lines dropped" affordance in
    /// `ToolCardView`. Cleared on `finalize` (terminal snapshot takes over).
    public private(set) var droppedLineCount: [BlockID: Int] = [:]

    /// Running line count for the linear SGR path (chunk-level, not rendered).
    private var linearLineCount: [BlockID: Int] = [:]

    #if canImport(SwiftTerm)
    // MARK: - Per-block terminal emulator (Warp-style VTE-per-block)
    //
    // Architecture mirrors Warp's Block.output_grid approach:
    //   • Each block owns one Terminal (the output grid)
    //   • PTY bytes are fed through terminal.feed() on every append()
    //   • Rendering extracts per-cell fg/bg/flags via the public
    //     getChar(at:) + getText(start:end:) pairing (see renderFromTerminal)
    //   • Terminal is freed on finalize() — memory held only while running
    //
    // Only engaged when cursor-movement sequences are detected (Ink/claude,
    // vim w/o alt-screen, etc.).  Normal linear commands keep using the SGR
    // path so their colors are preserved without extra overhead.
    private var terminals: [BlockID: Terminal] = [:]
    public private(set) var hasCursorMovement: Set<BlockID> = []
    #endif

    #if canImport(UIKit) && canImport(SwiftTerm)
    /// Live feed handle for blocks currently rendering an inline TUI
    /// (Ink/claude/etc.).  The view tier (`BlockRow`) embeds a
    /// `RawTerminalView(feedHandle:)` and consumes bytes in real time —
    /// Warp's "active block hosts the live grid" model.  Cleared on finalize.
    public private(set) var liveBlockHandles: [BlockID: TerminalFeedHandle] = [:]

    /// Lazily returns the live feed handle for a block, creating it the first
    /// time a TUI block needs one.  Called from `SessionViewModel.onBlockBytes`
    /// once cursor-movement is detected.
    public func ensureLiveHandle(for id: BlockID) -> TerminalFeedHandle {
        if let h = liveBlockHandles[id] { return h }
        let h = TerminalFeedHandle()
        liveBlockHandles[id] = h
        return h
    }
    #endif

    public init() {}

    // MARK: - Block lifecycle

    /// Create a block with an already-known command (legacy / OSC-133-free path).
    @discardableResult
    public func begin(sessionID: SessionID, command: String, prompt: Block.PromptInfo) -> BlockID {
        let block = Block(sessionID: sessionID, prompt: prompt, command: command, state: .submitted)
        blocks.append(block)
        #if canImport(SwiftTerm)
        terminals[block.id] = makeBlockTerminal()
        #endif
        return block.id
    }

    /// Create a block in `.promptEditing` state (OSC 133 A lifecycle).
    /// The command field starts empty and is filled in by `setCommand(_:for:)`
    /// when the user submits.
    @discardableResult
    public func beginPrompt(sessionID: SessionID, prompt: Block.PromptInfo) -> BlockID {
        let block = Block(sessionID: sessionID, prompt: prompt, command: "", state: .promptEditing)
        blocks.append(block)
        #if canImport(SwiftTerm)
        terminals[block.id] = makeBlockTerminal()
        #endif
        return block.id
    }

    /// Update the command string of an existing block.
    /// Called by `SessionViewModel.submit()` to capture the text the user typed
    /// before sending it to the PTY.
    public func setCommand(_ command: String, for id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].command = command
    }

    /// Transition a block to a new lifecycle state.
    public func setState(_ state: BlockState, for id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].state = state
    }

    /// Tier 2.3: record which snippet produced this block.
    public func setOriginatingSnippet(_ snippetID: SnippetID, for id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].originatingSnippetID = snippetID
    }

    /// Update the CWD on the prompt info of an existing block.
    /// Called when OSC 7 fires so the active block's prompt header stays current.
    public func updatePromptCWD(_ cwd: String, for id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].prompt.cwd = cwd
    }

    // Reset the pending-TUI-escalation flag (used by the belt-and-suspenders hint).
    // This is intentionally `var` so the VM can clear it after acting on it.
    // Declared as stored property at the top; just exposing a setter here is not
    // needed — callers access `.pendingTUIEscalation` directly.

    public func append(_ data: Data, stream: BlockChunk.Stream, to id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        if TUIDetector.shouldEscalate(to: data) { pendingTUIEscalation = true }

        let decodedText = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let text = normalizeLineEditorControls(decodedText, blockIndex: idx)

        if !text.isEmpty {
            blocks[idx].chunks.append(BlockChunk(text: text, stream: stream))
            // Track line count for the linear SGR path. Trim oldest chunks when
            // the block exceeds maxLinearLines so memory stays bounded.
            let newLines = text.filter { $0 == "\n" }.count
            linearLineCount[id, default: 0] += newLines
            truncateOldestLinesIfNeeded(id: id, blockIndex: idx)
        }
        renderCache[id] = nil

        #if canImport(SwiftTerm)
        terminals[id]?.feed(byteArray: Array(data))

        // Detect Ink-style cursor positioning (claude, warp-style TUI in block mode).
        if !hasCursorMovement.contains(id) {
            if text.contains("\u{1B}[H") || text.contains("\u{1B}[2J") || text.contains("\u{1B}[?25l") {
                hasCursorMovement.insert(id)
            }
        }
        #endif
    }

    /// Remove the oldest chunks from `blocks[blockIndex]` when the running line
    /// count exceeds `maxLinearLines`. Dropped lines are tallied in
    /// `droppedLineCount` so the view can show a "N earlier lines dropped" banner.
    private func truncateOldestLinesIfNeeded(id: BlockID, blockIndex idx: Int) {
        let limit = Self.maxLinearLines
        guard (linearLineCount[id] ?? 0) > limit else { return }
        let excess = (linearLineCount[id] ?? 0) - limit
        var dropped = 0
        while dropped < excess, !blocks[idx].chunks.isEmpty {
            let chunk = blocks[idx].chunks[0]
            let linesInChunk = chunk.text.filter { $0 == "\n" }.count
            if dropped + linesInChunk <= excess {
                blocks[idx].chunks.removeFirst()
                dropped += linesInChunk
            } else {
                // Partially trim the first chunk: drop enough lines from the front.
                let linesToDrop = excess - dropped
                var remaining = chunk.text
                var dropCount = 0
                while dropCount < linesToDrop, let nl = remaining.firstIndex(of: "\n") {
                    remaining = String(remaining[remaining.index(after: nl)...])
                    dropCount += 1
                }
                blocks[idx].chunks[0] = BlockChunk(text: remaining, stream: chunk.stream,
                                                    receivedAt: chunk.receivedAt)
                dropped += dropCount
                break
            }
        }
        linearLineCount[id] = limit
        droppedLineCount[id, default: 0] += dropped
        // SGR state is now stale — reset it so the next render re-parses from the
        // trimmed start. This loses accumulated open-color state but prevents
        // applying a state from lines that no longer exist.
        openState[id] = nil
        renderCache[id] = nil
    }

    private func normalizeLineEditorControls(_ text: String, blockIndex idx: Int) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x08, 0x7F:
                if !output.isEmpty {
                    output.removeLast()
                } else {
                    removeLastOutputCharacter(blockIndex: idx)
                }
            default:
                output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    private func removeLastOutputCharacter(blockIndex idx: Int) {
        while let chunkIndex = blocks[idx].chunks.indices.last {
            let chunk = blocks[idx].chunks[chunkIndex]
            guard !chunk.text.isEmpty else {
                blocks[idx].chunks.removeLast()
                continue
            }

            var text = chunk.text
            text.removeLast()
            if text.isEmpty {
                blocks[idx].chunks.removeLast()
            } else {
                blocks[idx].chunks[chunkIndex] = BlockChunk(
                    text: text,
                    stream: chunk.stream,
                    receivedAt: chunk.receivedAt
                )
            }
            return
        }
    }

    /// Discard a block's accumulated output. Called when an alt-screen TUI
    /// program takes over so pre-escalation partial frames don't appear.
    public func clearChunks(id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].chunks.removeAll()
        renderCache[id] = nil
        linearLineCount[id] = nil
        droppedLineCount[id] = nil
        openState[id] = nil
        #if canImport(SwiftTerm)
        hasCursorMovement.remove(id)
        terminals[id] = makeBlockTerminal()
        #endif
    }

    public func finalize(id: BlockID, exitCode: Int) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].exitStatus = ExitStatus(code: exitCode)
        blocks[idx].finishedAt = .now
        blocks[idx].state = .done(exitCode: exitCode)
        linearLineCount[id] = nil
        #if canImport(SwiftTerm)
        // Freeze the final screen state into the render cache, then free the terminal.
        if let term = terminals[id], hasCursorMovement.contains(id) {
            renderCache[id] = renderFromTerminal(term)
        }
        terminals[id] = nil
        hasCursorMovement.remove(id)
        #endif
        #if canImport(UIKit) && canImport(SwiftTerm)
        // Stop the live byte stream — block becomes a frozen text snapshot.
        liveBlockHandles[id]?.finish()
        liveBlockHandles[id] = nil
        #endif
    }

    public func toggleCollapsed(id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].isCollapsed.toggle()
    }

    public func toggleStarred(id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].isStarred.toggle()
    }

    /// Prepend finished blocks from persistent storage so the transcript is
    /// non-empty after a reconnect or app relaunch. Called after the unified
    /// shell re-opens; de-duplication is the caller's responsibility.
    public func prepend(contentsOf restored: [Block]) {
        guard !restored.isEmpty else { return }
        blocks.insert(contentsOf: restored, at: 0)
    }

    public func clear() {
        blocks.removeAll()
        openState.removeAll()
        renderCache.removeAll()
        linearLineCount.removeAll()
        droppedLineCount.removeAll()
        pendingTUIEscalation = false
        #if canImport(SwiftTerm)
        terminals.removeAll()
        hasCursorMovement.removeAll()
        #endif
        #if canImport(UIKit) && canImport(SwiftTerm)
        for (_, h) in liveBlockHandles { h.finish() }
        liveBlockHandles.removeAll()
        #endif
    }

    // MARK: - Rendering

    /// Render the block to an AttributedString. Cached until chunks change.
    public func render(_ block: Block) -> AttributedString {
        if let cached = renderCache[block.id] { return cached }

        #if canImport(SwiftTerm)
        // Cursor-positioning programs: use per-block terminal emulator.
        // Warp-style: extract fg/bg/flags per cell for full colored output.
        if hasCursorMovement.contains(block.id), let term = terminals[block.id] {
            let result = renderFromTerminal(term)
            renderCache[block.id] = result
            return result
        }
        #endif

        // Linear output: SGR parser preserves all ANSI colors.
        var state = openState[block.id] ?? SGRState()
        var out = AttributedString()
        for chunk in block.chunks {
            let (frag, next) = parser.parse(chunk.text, inheriting: state)
            out += frag
            state = next
        }
        openState[block.id] = state
        renderCache[block.id] = out
        return out
    }

    // MARK: - Warp-style per-block terminal rendering

    #if canImport(SwiftTerm)
    private func makeBlockTerminal() -> Terminal {
        // cols × 2000 rows, no scrollback — all output lives in the viewport
        // so buffer.y (cursor row) gives the last content line and yDisp stays 0.
        // cols is set from SessionViewModel so Claude Code draws for the actual
        // block width, not a fixed 80 that wraps on an iPhone screen.
        var opts = TerminalOptions.default
        opts.cols = terminalCols
        opts.rows = 2000
        opts.scrollback = 0
        opts.convertEol = false
        return Terminal(delegate: BlockTerminalDelegate(), options: opts)
    }

    /// Warp-style extraction: pair text characters (getText) with per-cell
    /// fg/bg/flags (getChar) to build a fully-colored AttributedString.
    ///
    /// Warp does this by iterating Cell.fg / Cell.bg / Cell.flags directly.
    /// SwiftTerm exposes these via the public CharData.attribute + getChar(at:)
    /// API.  The pairing works because getText(row r) returns exactly
    /// trimmedLength chars, and getChar(col c, row r) returns the CharData at
    /// that column — a 1:1 mapping by column index.
    private func renderFromTerminal(_ term: Terminal) -> AttributedString {
        let cursorRow = term.buffer.y
        let cols = term.cols
        let theme = TerminalTheme.current

        var rows: [AttributedString] = []

        for r in 0...cursorRow {
            // getText for single row: start/end have same row, different cols
            // → _getSelectedLines processes only the first-line branch with trimRight.
            let rowText = term.getText(
                start: Position(col: 0, row: r),
                end: Position(col: cols - 1, row: r)
            )

            if rowText.isEmpty {
                rows.append(AttributedString())
                continue
            }

            // Pair each character with its cell attribute.
            var rowResult = AttributedString()
            var runText = ""
            var runAttr: Attribute? = nil

            func flush() {
                guard !runText.isEmpty else { return }
                var chunk = AttributedString(runText)
                if let a = runAttr {
                    chunk.mergeAttributes(makeContainer(a, theme: theme))
                }
                rowResult += chunk
                runText = ""
            }

            for (col, ch) in rowText.enumerated() {
                let cd = term.buffer.getChar(at: Position(col: col, row: r))
                if cd.attribute != runAttr { flush(); runAttr = cd.attribute }
                runText.append(ch)
            }
            flush()
            rows.append(rowResult)
        }

        // Trim trailing all-empty rows (viewport padding below cursor).
        let trimmed = rows.reversed().drop(while: { $0.characters.isEmpty })
            .reversed()

        guard !trimmed.isEmpty else { return AttributedString() }

        var result = AttributedString()
        for (i, row) in trimmed.enumerated() {
            if i > 0 { result += AttributedString("\n") }
            result += row
        }
        return result
    }

    /// Map a SwiftTerm Attribute to a SwiftUI AttributeContainer.
    /// Mirrors Warp's FontStyle::from(flags) + Color resolution.
    private func makeContainer(_ attr: Attribute, theme: TerminalTheme) -> AttributeContainer {
        var c = AttributeContainer()
        let style = attr.style
        let isInverse = style.contains(.inverse)

        var fg: SwiftUI.Color? = resolveColor(attr.fg, isFg: true,  theme: theme)
        var bg: SwiftUI.Color? = resolveColor(attr.bg, isFg: false, theme: theme)
        if isInverse { swap(&fg, &bg) }

        if let fg { c.foregroundColor = fg }
        if let bg { c.backgroundColor = bg }

        var font: SwiftUI.Font = .custom("FragmentMono-Regular", size: 17)
        if style.contains(.bold)   { font = font.bold() }
        if style.contains(.italic) { font = .custom("FragmentMono-Italic", size: 17) }
        c.font = font
        if style.contains(.underline) { c.underlineStyle = .single }
        if style.contains(.dim) { c.foregroundColor = (fg ?? theme.foreground).opacity(0.7) }
        return c
    }

    /// Resolve a SwiftTerm Attribute.Color to a SwiftUI Color.
    /// Mirrors Warp's color::List palette lookup (Named → 16-color palette,
    /// Indexed → 256-color, Rgb → true color).
    private func resolveColor(_ color: Attribute.Color, isFg: Bool, theme: TerminalTheme) -> SwiftUI.Color? {
        switch color {
        case .defaultColor:          return isFg ? theme.foreground : nil
        case .defaultInvertedColor:  return isFg ? nil : theme.background
        case .trueColor(let r, let g, let b):
            return SwiftUI.Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
        case .ansi256(let code):
            let i = Int(code)
            switch i {
            case 0...7:    return theme.ansiNormal[i]
            case 8...15:   return theme.ansiBright[i - 8]
            case 16...231:
                let n = i - 16
                return SwiftUI.Color(
                    red:   Double((n / 36)       * 51) / 255,
                    green: Double(((n % 36) / 6) * 51) / 255,
                    blue:  Double((n % 6)         * 51) / 255
                )
            case 232...255:
                let v = Double((i - 232) * 10 + 8) / 255
                return SwiftUI.Color(red: v, green: v, blue: v)
            default: return isFg ? theme.foreground : nil
            }
        }
    }
    #endif
}

// MARK: - No-op TerminalDelegate for block emulation

#if canImport(SwiftTerm)
/// Mirrors Warp's BlockGrid Handler impl — block terminals never send data
/// back to the remote host so send() is a no-op. All other TerminalDelegate
/// methods have default no-op implementations in SwiftTerm's protocol extension.
private final class BlockTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}
#endif
