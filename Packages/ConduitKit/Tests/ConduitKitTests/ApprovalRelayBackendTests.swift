import Testing
import Foundation
@testable import SessionFeature
@testable import ConduitCore

#if os(iOS)
@Suite struct ApprovalRelayBackendTests {
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
}
#endif
