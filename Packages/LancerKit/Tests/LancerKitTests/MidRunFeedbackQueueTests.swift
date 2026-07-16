import Foundation
import Testing
@testable import AppFeature

@Suite("MidRunFeedbackQueue")
struct MidRunFeedbackQueueTests {

    private func item(_ text: String, id: String? = nil) -> MidRunFeedbackItem {
        MidRunFeedbackItem(
            id: id ?? UUID().uuidString,
            text: text,
            conversationID: "conv-1",
            cwd: "/tmp/proj"
        )
    }

    @Test("enqueue preserves FIFO order")
    func enqueuePreservesOrder() {
        var queue = MidRunFeedbackQueue()
        queue.enqueue(item("first", id: "a"))
        queue.enqueue(item("second", id: "b"))
        queue.enqueue(item("third", id: "c"))

        #expect(queue.count == 3)
        #expect(queue.items.map(\.text) == ["first", "second", "third"])
        #expect(queue.items.map(\.id) == ["a", "b", "c"])
    }

    @Test("dequeueFirst returns oldest then empties")
    func dequeueFirstOrder() {
        var queue = MidRunFeedbackQueue()
        queue.enqueue(item("first", id: "a"))
        queue.enqueue(item("second", id: "b"))

        let first = queue.dequeueFirst()
        #expect(first?.id == "a")
        #expect(queue.count == 1)

        let second = queue.dequeueFirst()
        #expect(second?.id == "b")
        #expect(queue.isEmpty)

        #expect(queue.dequeueFirst() == nil)
    }

    @Test("flushNext is gated while agent is in flight")
    func flushGatedWhileInFlight() {
        var queue = MidRunFeedbackQueue()
        queue.enqueue(item("queued", id: "a"))

        #expect(queue.flushNext(agentInFlight: true) == nil)
        #expect(queue.count == 1)

        let flushed = queue.flushNext(agentInFlight: false)
        #expect(flushed?.id == "a")
        #expect(queue.isEmpty)
    }

    @Test("flushNext drains one item per idle flush")
    func flushDrainsOneAtATime() {
        var queue = MidRunFeedbackQueue()
        queue.enqueue(item("one", id: "1"))
        queue.enqueue(item("two", id: "2"))

        let first = queue.flushNext(agentInFlight: false)
        #expect(first?.text == "one")
        #expect(queue.items.map(\.id) == ["2"])

        // Still "in flight" for the just-sent follow-up — no second pop.
        #expect(queue.flushNext(agentInFlight: true) == nil)

        let second = queue.flushNext(agentInFlight: false)
        #expect(second?.text == "two")
        #expect(queue.isEmpty)
    }
}
