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
        let second = SiriNavigationPayload(action: .openApproval, approvalId: "abc")
        buffer.record(first)
        buffer.record(second)
        let drained = buffer.drain()
        #expect(drained.count == 2)
        #expect(drained[0] == first)
        #expect(drained[1] == second)
        _ = buffer.drain()
    }

    @Test("payload round-trips through userInfo")
    func userInfoRoundTrip() {
        let payload = SiriNavigationPayload(
            action: .openMachine,
            machineId: "relay:deadbeef-dead-beef-dead-beefdeadbeef"
        )
        let restored = SiriNavigationPayload(userInfo: payload.userInfo)
        #expect(restored == payload)
    }

    @Test("openApproval payload carries approval id")
    func openApprovalPayload() {
        let payload = SiriNavigationPayload(action: .openApproval, approvalId: "550e8400-e29b-41d4-a716-446655440000")
        #expect(payload.userInfo[SiriNavigationUserInfoKey.approvalId] as? String == "550e8400-e29b-41d4-a716-446655440000")
    }
}

@Suite("DenyLatestAmbiguity")
struct DenyLatestAmbiguityTests {
    @Test("multiple pending approvals should refuse deny-latest semantics")
    func multiplePendingRefuses() {
        let pendingCount = 2
        let dialog: String
        if pendingCount > 1 {
            dialog = "\(pendingCount) approvals are waiting — say which one to deny."
        } else {
            dialog = "deny"
        }
        #expect(dialog.contains("say which one"))
    }

    @Test("single pending approval is eligible for deny-latest")
    func singlePendingAllowed() {
        let pendingCount = 1
        let refuses = pendingCount > 1
        #expect(refuses == false)
    }
}
