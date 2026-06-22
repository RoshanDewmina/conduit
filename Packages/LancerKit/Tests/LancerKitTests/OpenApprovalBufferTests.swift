import Testing
@testable import NotificationsKit

struct OpenApprovalBufferTests {
    @Test func recordsAndDrainsOnce() {
        let b = OpenApprovalBuffer.shared
        _ = b.drain() // clear
        b.record(approvalID: "ABC")
        b.record(approvalID: "DEF")
        #expect(b.drain() == ["ABC", "DEF"])
        #expect(b.drain() == []) // drained once
    }
}
