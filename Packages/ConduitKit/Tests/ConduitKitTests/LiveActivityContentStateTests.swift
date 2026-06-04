import Testing
import Foundation
@testable import SessionFeature

// ConduitSessionAttributes.ContentState is a plain Codable struct — no
// ActivityKit entitlement needed to test it, but the type is declared
// inside `#if os(iOS)` so we guard the test body accordingly.

@Suite("LiveActivityContentState")
struct LiveActivityContentStateTests {

#if os(iOS)

    // MARK: - Default / connected state

    @available(iOS 16.2, *)
    @Test("connected status with no pending approvals")
    func connectedNoPending() {
        let state = ConduitSessionAttributes.ContentState(
            status: "connected",
            pendingApprovals: 0,
            agentName: nil,
            pendingApprovalID: nil,
            isStreaming: false
        )
        #expect(state.status == "connected")
        #expect(state.pendingApprovals == 0)
        #expect(state.isStreaming == false)
        #expect(state.pendingApprovalID == nil)
    }

    // MARK: - Pending approval propagation

    @available(iOS 16.2, *)
    @Test("pendingApprovals > 0 sets pendingApprovalID")
    func pendingApprovalIDPresent() {
        let id = UUID().uuidString
        let state = ConduitSessionAttributes.ContentState(
            status: "connected",
            pendingApprovals: 3,
            agentName: "Claude Code",
            pendingApprovalID: id,
            isStreaming: true
        )
        #expect(state.pendingApprovals == 3)
        #expect(state.pendingApprovalID == id)
        #expect(state.agentName == "Claude Code")
        #expect(state.isStreaming == true)
    }

    // MARK: - Codable round-trips

    @available(iOS 16.2, *)
    @Test("reconnecting status round-trips through Codable")
    func reconnectingRoundTrip() throws {
        let original = ConduitSessionAttributes.ContentState(
            status: "reconnecting",
            pendingApprovals: 1,
            agentName: "Codex",
            pendingApprovalID: "abc-123",
            isStreaming: false,
            lastUpdate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ConduitSessionAttributes.ContentState.self,
            from: data
        )
        #expect(decoded.status == "reconnecting")
        #expect(decoded.pendingApprovals == 1)
        #expect(decoded.agentName == "Codex")
        #expect(decoded.pendingApprovalID == "abc-123")
        #expect(decoded.isStreaming == false)
        #expect(decoded.lastUpdate == original.lastUpdate)
    }

    @available(iOS 16.2, *)
    @Test("connected status round-trips with nil optionals")
    func connectedNilsRoundTrip() throws {
        let original = ConduitSessionAttributes.ContentState(
            status: "connected",
            pendingApprovals: 0,
            agentName: nil,
            pendingApprovalID: nil,
            isStreaming: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ConduitSessionAttributes.ContentState.self,
            from: data
        )
        #expect(decoded.status == "connected")
        #expect(decoded.pendingApprovals == 0)
        #expect(decoded.agentName == nil)
        #expect(decoded.pendingApprovalID == nil)
    }

    @available(iOS 16.2, *)
    @Test("suspended status round-trips through Codable")
    func suspendedRoundTrip() throws {
        let original = ConduitSessionAttributes.ContentState(status: "suspended")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ConduitSessionAttributes.ContentState.self,
            from: data
        )
        #expect(decoded.status == "suspended")
        #expect(decoded.pendingApprovals == 0)
    }

#endif // os(iOS)
}
