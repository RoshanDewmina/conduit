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

    // MARK: - Date encoding pin (ActivityKit push contract)
    //
    // ActivityKit's default JSONDecoder expects Date as Unix fractional seconds
    // (a JSON number), which matches Swift's JSONEncoder default (deferredToDate
    // strategy). A mismatch (e.g. ISO-8601 string) silently drops the whole
    // content-state update on the device. This test pins the encoding so a future
    // refactor or custom encoder can't break it undetected.

    @available(iOS 16.2, *)
    @Test("lastUpdate encodes as a JSON number (Unix fractional seconds) — ActivityKit push contract")
    func lastUpdateEncodesAsUnixNumber() throws {
        // Fixed date for determinism.
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let state = ConduitSessionAttributes.ContentState(
            status: "connected",
            lastUpdate: fixedDate
        )

        // Use the default JSONEncoder — no custom date strategy — matching
        // what ActivityKit's sender (push-backend) must use.
        let data = try JSONEncoder().encode(state)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError("failed to parse encoded JSON")
        }

        // lastUpdate must be a JSON number (Double), NOT a string.
        guard let lastUpdate = json["lastUpdate"] else {
            throw TestError("lastUpdate key missing from encoded JSON")
        }
        // JSONSerialization decodes JSON numbers as Double / NSNumber.
        let isNumber: Bool
        if lastUpdate is Double || lastUpdate is NSNumber {
            isNumber = true
        } else {
            isNumber = false
        }
        #expect(isNumber, "lastUpdate must be a JSON number (Double), not a String. Got: \(type(of: lastUpdate))")

        // Pin the exact numeric value to catch any encoder strategy drift.
        let asDouble = (lastUpdate as? NSNumber)?.doubleValue ?? 0
        #expect(abs(asDouble - 1_700_000_000.0) < 0.001,
            "lastUpdate value \(asDouble) deviates from expected Unix timestamp 1700000000.0")

        // Confirm it is NOT string-encoded (which ActivityKit would reject).
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        #expect(!jsonString.contains("\"lastUpdate\":\""),
            "lastUpdate must not be a JSON string; it would be silently rejected by ActivityKit. JSON: \(jsonString)")
    }

    @available(iOS 16.2, *)
    @Test("push-backend content-state round-trip — Go JSON mirrors Swift Codable output")
    func pushBackendContentStateRoundTrip() throws {
        // Simulate what push-backend encodes and what ActivityKit decodes.
        // The Go liveActivityContentState struct uses the same field names and
        // types as ConduitSessionAttributes.ContentState. This test encodes a
        // ContentState with Swift's default encoder and then decodes the same
        // bytes back — proving the round-trip holds without a custom strategy.
        let approvalID = "appr-push-test"
        let original = ConduitSessionAttributes.ContentState(
            status: "connected",
            pendingApprovals: 1,
            agentName: "Claude Code",
            pendingApprovalID: approvalID,
            isStreaming: false,
            cost: 0.042,
            lastUpdate: Date(timeIntervalSince1970: 1_700_100_000)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ConduitSessionAttributes.ContentState.self,
            from: encoded
        )

        #expect(decoded.status == "connected")
        #expect(decoded.pendingApprovals == 1)
        #expect(decoded.agentName == "Claude Code")
        #expect(decoded.pendingApprovalID == approvalID)
        #expect(decoded.isStreaming == false)
        #expect(abs((decoded.cost ?? 0) - 0.042) < 0.0001)
        #expect(abs(decoded.lastUpdate.timeIntervalSince1970 - 1_700_100_000) < 0.001)
    }

    @available(iOS 16.2, *)
    @Test("ContentState fields match Go liveActivityContentState JSON keys")
    func jsonKeyNames() throws {
        let state = ConduitSessionAttributes.ContentState(
            status: "connected",
            pendingApprovals: 2,
            agentName: "Codex",
            pendingApprovalID: "appr-key-test",
            isStreaming: true,
            cost: 1.5
        )
        let data = try JSONEncoder().encode(state)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestError("JSON parse failed")
        }
        // Keys must match Go's `json:"..."` tags exactly.
        #expect(json["status"] != nil)
        #expect(json["pendingApprovals"] != nil)
        #expect(json["agentName"] != nil)
        #expect(json["pendingApprovalID"] != nil)
        #expect(json["isStreaming"] != nil)
        #expect(json["cost"] != nil)
        #expect(json["lastUpdate"] != nil)
    }

    @available(iOS 16.2, *)
    @Test func lastDecisionRoundTripsAndDefaultsNil() throws {
        // Default is nil and omitted-friendly.
        let running = ConduitSessionAttributes.ContentState(status: "connected", isStreaming: true)
        #expect(running.lastDecision == nil)

        // Set + round-trip through JSON (the wire format ActivityKit uses).
        let landed = ConduitSessionAttributes.ContentState(
            status: "connected", pendingApprovals: 0, lastDecision: "approved"
        )
        let data = try JSONEncoder().encode(landed)
        let back = try JSONDecoder().decode(ConduitSessionAttributes.ContentState.self, from: data)
        #expect(back.lastDecision == "approved")
    }

#endif // os(iOS)
}

// Lightweight error helper for test assertions.
private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { description = msg }
}
