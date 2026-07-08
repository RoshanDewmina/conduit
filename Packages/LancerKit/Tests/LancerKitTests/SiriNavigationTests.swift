import Foundation
import Testing
@testable import NotificationsKit

@Suite("SiriNavigationBuffer")
struct SiriNavigationBufferTests {
    @Test("record then drain returns payloads in order")
    func recordDrain() {
        let buffer = SiriNavigationBuffer.shared
        _ = buffer.drain()
        let first = SiriNavigationPayload(action: .search, searchQuery: "auth")
        let second = SiriNavigationPayload(action: .openConversation, conversationId: "conv-1")
        buffer.record(first)
        buffer.record(second)
        let drained = buffer.drain()
        #expect(drained.count == 2)
        #expect(drained[0] == first)
        #expect(drained[1] == second)
        _ = buffer.drain()
    }

    @Test("drain empties the buffer")
    func drainIsExhaustive() {
        let buffer = SiriNavigationBuffer.shared
        _ = buffer.drain()
        buffer.record(SiriNavigationPayload(action: .search, searchQuery: "x"))
        _ = buffer.drain()
        #expect(buffer.drain().isEmpty)
    }
}

@Suite("SiriNavigationPayload")
struct SiriNavigationPayloadTests {
    @Test("payload round-trips through userInfo")
    func userInfoRoundTrip() {
        let payload = SiriNavigationPayload(
            action: .openConversation,
            conversationId: "conv-42"
        )
        let restored = SiriNavigationPayload(userInfo: payload.userInfo)
        #expect(restored == payload)
    }

    @Test("search payload carries the query")
    func searchPayloadCarriesQuery() {
        let payload = SiriNavigationPayload(action: .search, searchQuery: "flaky tests")
        #expect(payload.userInfo[SiriNavigationUserInfoKey.searchQuery] as? String == "flaky tests")
        #expect(payload.userInfo[SiriNavigationUserInfoKey.action] as? String == "search")
    }

    @Test("malformed userInfo (missing action) fails to construct")
    func malformedUserInfoFailsToConstruct() {
        #expect(SiriNavigationPayload(userInfo: [SiriNavigationUserInfoKey.searchQuery: "x"]) == nil)
    }

    @Test("unknown action raw value fails to construct")
    func unknownActionFailsToConstruct() {
        #expect(SiriNavigationPayload(userInfo: [SiriNavigationUserInfoKey.action: "openMachine"]) == nil)
    }
}

@Suite("SiriNavigationDispatch")
struct SiriNavigationDispatchTests {
    @Test("post both records to the buffer and broadcasts the notification")
    func postRecordsAndBroadcasts() async {
        let buffer = SiriNavigationBuffer.shared
        _ = buffer.drain()

        let payload = SiriNavigationPayload(action: .openConversation, conversationId: "conv-99")
        let received = await withCheckedContinuation { (continuation: CheckedContinuation<SiriNavigationPayload?, Never>) in
            let observer = NotificationCenter.default.addObserver(
                forName: .lancerSiriNavigation, object: nil, queue: nil
            ) { note in
                continuation.resume(returning: SiriNavigationPayload(userInfo: note.userInfo ?? [:]))
            }
            SiriNavigationDispatch.post(payload)
            NotificationCenter.default.removeObserver(observer)
        }

        #expect(received == payload)
        #expect(buffer.drain() == [payload])
    }
}
