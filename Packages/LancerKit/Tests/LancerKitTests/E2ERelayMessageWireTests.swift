import Testing
import Foundation
@testable import LancerCore

/// Regression coverage for the `deviceRegistered` reply (daemon → phone), added
/// to close the gap where a relay-only pairing (no SSH host) never learned its
/// per-session capability token: `ApprovalRelay.relayToken` stayed empty for the
/// life of the process, so `postDecisionToBackend` — the only fallback when the
/// direct `approvalResponse` send doesn't get acked — silently no-opped on
/// every call. See `daemon/lancerd/e2e_router.go`'s `deviceRegister` case and
/// `E2ERelayBridge.handleRelayMessage`'s new `"deviceRegistered"` case.
///
/// This pins the wire *shape* the Go side actually emits
/// (`{"type":"deviceRegistered","payload":{"relayToken":"…"}}`) against the
/// Swift decode path, since a shape mismatch would fail silently behind a
/// `try?` and reintroduce the exact bug this fixes with no compiler warning.
@Suite struct E2ERelayMessageWireTests {
    @Test("deviceRegistered envelope decodes the daemon's relayToken")
    func decodesDaemonShape() throws {
        // Exactly what daemon/lancerd/e2e_router.go marshals:
        // json.Marshal(map[string]interface{}{"type": "deviceRegistered", "payload": map[string]interface{}{"relayToken": relayToken}})
        let wireJSON = #"{"type":"deviceRegistered","payload":{"relayToken":"abc123secret"}}"#
        let data = Data(wireJSON.utf8)

        let env = try JSONDecoder().decode(
            E2ERelayMessage.RelayInnerEnvelope<E2ERelayMessage.DeviceRegisteredData>.self, from: data
        )

        #expect(env.type == "deviceRegistered")
        #expect(env.payload.relayToken == "abc123secret")
    }

    @Test("DeviceRegisteredData round-trips through encode/decode")
    func roundTrips() throws {
        let original = E2ERelayMessage.DeviceRegisteredData(relayToken: "tok-xyz")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(E2ERelayMessage.DeviceRegisteredData.self, from: data)
        #expect(decoded.relayToken == original.relayToken)
    }
}
