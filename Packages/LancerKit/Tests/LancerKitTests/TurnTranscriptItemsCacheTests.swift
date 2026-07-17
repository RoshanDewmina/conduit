import Foundation
import Testing
import LancerCore
@testable import AppFeature

/// Covers the WP1 perf fix in ConversationSyncCoordinator.swift: caching
/// `TurnTranscriptAssembler.items(from:)` per turn so repeated SwiftUI
/// re-renders (and multiple call sites for the same turn) don't re-sort/
/// re-walk the same event array from scratch every time.
@Suite("TurnTranscriptItemsCache")
struct TurnTranscriptItemsCacheTests {
    private let conv = "conv-cache"
    private let turnID = "turn-cache"
    private let t0 = Date(timeIntervalSince1970: 3_000_000)

    private func event(seq: Int, text: String) -> ChatEvent {
        ChatEvent(
            conversationID: conv,
            seq: seq,
            turnID: turnID,
            runID: "run-cache",
            kind: "output",
            text: text,
            payloadJSON: nil,
            createdAt: t0.addingTimeInterval(TimeInterval(seq))
        )
    }

    @Test("same event array returns the identical cached items on repeated calls")
    func cacheHitReturnsSameItems() {
        let cache = TurnTranscriptItemsCache()
        let events = [event(seq: 1, text: "hello ")]

        let first = cache.items(for: turnID, events: events)
        let second = cache.items(for: turnID, events: events)

        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.count == 1)
    }

    @Test("appending an event invalidates the cache and includes the new item")
    func appendInvalidatesCache() {
        let cache = TurnTranscriptItemsCache()
        let firstEvents = [event(seq: 1, text: "hello ")]
        let first = cache.items(for: turnID, events: firstEvents)
        #expect(first.count == 1)

        // Append-only growth (matches how eventsByTurnID is populated —
        // full re-fetch of a strictly-growing event log).
        let grownEvents = firstEvents + [event(seq: 2, text: "world")]
        let second = cache.items(for: turnID, events: grownEvents)

        // "hello " and "world" are both `output` events and get merged into
        // one prose run by the assembler, so item COUNT alone isn't the
        // signal — assert the cache actually recomputed by checking the
        // prose text grew to include the new event's text.
        if case .prose(let item) = second.first {
            #expect(item.text.contains("world"))
        } else {
            Issue.record("expected a prose item after appending an output event")
        }
    }

    @Test("different turn ids never share a cache entry")
    func differentTurnsAreIndependent() {
        let cache = TurnTranscriptItemsCache()
        let eventsA = [event(seq: 1, text: "from A")]
        let eventsB = [event(seq: 1, text: "from B")]

        let itemsA = cache.items(for: "turn-A", events: eventsA)
        let itemsB = cache.items(for: "turn-B", events: eventsB)

        guard case .prose(let a) = itemsA.first, case .prose(let b) = itemsB.first else {
            Issue.record("expected prose items for both turns")
            return
        }
        #expect(a.text == "from A")
        #expect(b.text == "from B")
    }
}
