import Testing
import Foundation
@testable import TerminalEngine
import ConduitCore

@Suite("BlockSearch")
struct BlockSearchTests {
    private func makeBlock(output: String) -> Block {
        var b = Block(sessionID: SessionID(), prompt: .init(cwd: "/", hostName: "test"), command: "test")
        b.chunks = [BlockChunk(text: output, stream: .stdout)]
        return b
    }

    @Test("returns nil for empty query")
    func emptyQueryReturnsNil() {
        let block = makeBlock(output: "hello world")
        #expect(BlockSearch.search(query: "", in: block) == nil)
    }

    @Test("returns nil when block has no output")
    func noOutputReturnsNil() {
        let block = Block(sessionID: SessionID(), prompt: .init(cwd: "/", hostName: "test"), command: "cmd")
        #expect(BlockSearch.search(query: "hello", in: block) == nil)
    }

    @Test("returns nil when query not found")
    func noMatchReturnsNil() {
        let block = makeBlock(output: "hello world")
        #expect(BlockSearch.search(query: "xyz", in: block) == nil)
    }

    @Test("finds single match")
    func singleMatch() {
        let block = makeBlock(output: "hello world")
        let result = BlockSearch.search(query: "world", in: block)
        #expect(result?.matchCount == 1)
    }

    @Test("finds multiple matches")
    func multipleMatches() {
        let block = makeBlock(output: "foo bar foo baz foo")
        let result = BlockSearch.search(query: "foo", in: block)
        #expect(result?.matchCount == 3)
    }

    @Test("case-insensitive match")
    func caseInsensitive() {
        let block = makeBlock(output: "Hello WORLD hello world")
        let result = BlockSearch.search(query: "hello", in: block)
        #expect(result?.matchCount == 2)
    }

    @Test("search across multiple blocks returns per-block results")
    func multiBlock() {
        let b1 = makeBlock(output: "contains needle")
        let b2 = makeBlock(output: "no match here")
        let b3 = makeBlock(output: "needle again")
        let results = BlockSearch.search(query: "needle", in: [b1, b2, b3])
        #expect(results.count == 2)
    }
}
