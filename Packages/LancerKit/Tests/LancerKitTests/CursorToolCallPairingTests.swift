import Foundation
import Testing
@testable import AppFeature

@Suite("CursorToolCallPairing")
struct CursorToolCallPairingTests {
    @Test("start creates a running card keyed by id")
    func startCreatesRunningCard() {
        var store = CursorToolCallPairing()
        store.applyStart(id: "t1", name: "Bash", inputJSON: #"{"command":"ls"}"#)
        #expect(store.cards.count == 1)
        #expect(store.cards[0].id == "t1")
        #expect(store.cards[0].name == "Bash")
        #expect(store.cards[0].state == .running)
        #expect(store.cards[0].inputJSON == #"{"command":"ls"}"#)
    }

    @Test("result pairs by id and marks completed")
    func resultPairsByID() {
        var store = CursorToolCallPairing()
        store.applyStart(id: "t1", name: "Read", inputJSON: #"{"path":"a.swift"}"#)
        store.applyResult(id: "t1", result: "file contents", isError: false)
        #expect(store.cards.count == 1)
        #expect(store.cards[0].state == .completed)
        #expect(store.cards[0].resultPreview == "file contents")
    }

    @Test("error result marks error state")
    func errorResult() {
        var store = CursorToolCallPairing()
        store.applyStart(id: "t1", name: "Bash", inputJSON: "{}")
        store.applyResult(id: "t1", result: "exit 1", isError: true)
        #expect(store.cards[0].state == .error)
        #expect(store.cards[0].resultPreview == "exit 1")
    }

    @Test("orphan result is buffered until matching start arrives")
    func orphanResultBuffered() {
        var store = CursorToolCallPairing()
        store.applyResult(id: "late", result: "ok", isError: false)
        #expect(store.cards.isEmpty)
        #expect(store.bufferedOrphanCount == 1)

        store.applyStart(id: "late", name: "Edit", inputJSON: #"{"path":"x"}"#)
        #expect(store.bufferedOrphanCount == 0)
        #expect(store.cards.count == 1)
        #expect(store.cards[0].state == .completed)
        #expect(store.cards[0].name == "Edit")
        #expect(store.cards[0].resultPreview == "ok")
    }

    @Test("orphan error drains onto start as error")
    func orphanErrorDrains() {
        var store = CursorToolCallPairing()
        store.applyResult(id: "x", result: "denied", isError: true)
        store.applyStart(id: "x", name: "Bash", inputJSON: "{}")
        #expect(store.cards[0].state == .error)
        #expect(store.cards[0].resultPreview == "denied")
    }

    @Test("duplicate start updates name/input without duplicating card")
    func duplicateStartUpdatesInPlace() {
        var store = CursorToolCallPairing()
        store.applyStart(id: "t1", name: "Bash", inputJSON: #"{"command":"ls"}"#)
        store.applyStart(id: "t1", name: "Bash", inputJSON: #"{"command":"ls -la"}"#)
        #expect(store.cards.count == 1)
        #expect(store.cards[0].inputJSON == #"{"command":"ls -la"}"#)
    }

    @Test("cards preserve insertion order")
    func preservesOrder() {
        var store = CursorToolCallPairing()
        store.applyStart(id: "a", name: "A", inputJSON: "{}")
        store.applyStart(id: "b", name: "B", inputJSON: "{}")
        store.applyStart(id: "c", name: "C", inputJSON: "{}")
        #expect(store.cards.map(\.id) == ["a", "b", "c"])
    }

    @Test("result text is capped at 4 KB")
    func resultCap() {
        var store = CursorToolCallPairing()
        store.applyStart(id: "t1", name: "Read", inputJSON: "{}")
        let big = String(repeating: "x", count: 5_000)
        store.applyResult(id: "t1", result: big, isError: false)
        let preview = store.cards[0].resultPreview
        #expect(preview != nil)
        #expect(preview!.utf8.count <= CursorToolCallPresentation.maxResultUTF8Count + 3) // ellipsis
        #expect(preview!.hasSuffix("…"))
    }
}
