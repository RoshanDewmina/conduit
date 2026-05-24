import Foundation
import SwiftUI
import Observation
import ConduitCore

/// State container for a session's blocks. `@Observable` so SwiftUI views
/// re-render only the rows that change. Everything mutates on the main
/// actor; the SSH stream is funnelled through `append(_:stream:to:)` on
/// the main actor by the SessionViewModel.
@MainActor @Observable
public final class BlockRenderer {
    public private(set) var blocks: [Block] = []
    public private(set) var pendingTUIEscalation = false

    private var openState: [BlockID: SGRState] = [:]
    private var renderCache: [BlockID: AttributedString] = [:]
    private let parser = AnsiSGRParser()

    public init() {}

    // MARK: - Block lifecycle

    @discardableResult
    public func begin(sessionID: SessionID, command: String, prompt: Block.PromptInfo) -> BlockID {
        let block = Block(sessionID: sessionID, prompt: prompt, command: command)
        blocks.append(block)
        return block.id
    }

    public func append(_ data: Data, stream: BlockChunk.Stream, to id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        if TUIDetector.shouldEscalate(to: data) { pendingTUIEscalation = true }

        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""

        blocks[idx].chunks.append(BlockChunk(text: text, stream: stream))
        renderCache[id] = nil
    }

    public func finalize(id: BlockID, exitCode: Int) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].exitStatus = ExitStatus(code: exitCode)
        blocks[idx].finishedAt = .now
    }

    public func toggleCollapsed(id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].isCollapsed.toggle()
    }

    public func toggleStarred(id: BlockID) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].isStarred.toggle()
    }

    public func clear() {
        blocks.removeAll()
        openState.removeAll()
        renderCache.removeAll()
        pendingTUIEscalation = false
    }

    // MARK: - Rendering

    /// Render the block to an AttributedString. Cached until chunks change.
    public func render(_ block: Block) -> AttributedString {
        if let cached = renderCache[block.id] { return cached }
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
}
