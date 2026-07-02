import Testing
import Foundation
@testable import LancerCore
#if os(iOS)
@testable import SessionFeature

@Suite @MainActor struct ApprovalRelayBackendTests {
    @Test("Backend decision POST body has approvalId, decision wire value, sessionId")
    func postBody() throws {
        let data = ApprovalRelay.backendDecisionBody(
            approvalID: "appr-7",
            decision: .approvedAlways,
            sessionID: "sess-A",
            editedToolInput: nil
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["approvalId"] as? String == "appr-7")
        #expect(obj["decision"] as? String == "approveAlways")
        #expect(obj["sessionId"] as? String == "sess-A")
        #expect(obj["editedToolInput"] == nil)
    }

    // Content-hash binding: lancerd's approvalStore.resolve rejects a decision
    // whose echoed contentHash doesn't match the pending event's — the backend
    // relay POST body must actually carry it through when the caller has one.
    @Test("Backend decision POST body carries contentHash when supplied")
    func postBodyIncludesContentHash() throws {
        let data = ApprovalRelay.backendDecisionBody(
            approvalID: "appr-8",
            decision: .approved,
            sessionID: "sess-B",
            editedToolInput: nil,
            contentHash: "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3"
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["contentHash"] as? String == "c5fca73ef15566810d568ca87f42cf1d917e78ce9c51d9b641a6d783c4c5c7b3")
    }

    @Test("Backend decision POST body omits contentHash when nil")
    func postBodyOmitsContentHashWhenNil() throws {
        let data = ApprovalRelay.backendDecisionBody(
            approvalID: "appr-9",
            decision: .approved,
            sessionID: "sess-C",
            editedToolInput: nil
        )
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["contentHash"] == nil)
    }
}
#endif
