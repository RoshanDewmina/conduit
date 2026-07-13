import Testing
import Foundation
@testable import LancerCore
@testable import SSHTransport

/// REL-1 C: proves the phone stops churning on a dead pairing code instead of
/// redialing forever, and decodes the relay's new structured error/waiting
/// fields. Drives the real `handleMessage` parsing via the
/// `simulateIncomingFrameForTesting` seam (mirrors `setStateForTesting`'s
/// established pattern) rather than re-describing the logic in the test.
@MainActor
@Suite struct E2ERelayClientExpiryTests {

    private func makeClient(code: String = "111222") -> E2ERelayClient {
        E2ERelayClient(relayURL: URL(string: "https://relay.example.com")!, pairingCode: code)
    }

    @Test("code_expired error frame sets .codeExpired and clears the persisted code")
    func codeExpiredSetsState() {
        let client = makeClient()
        client.persistPairing()
        #expect(E2ERelayClient.storedPairingCode(machineID: client.machineID) != nil)

        client.simulateIncomingFrameForTesting(#"{"type":"error","code":"code_expired","message":"pairing code expired, generate a new one"}"#)

        #expect(client.pairingState == .codeExpired)
        #expect(client.pairingExpiresAt == nil)
        #expect(E2ERelayClient.storedPairingCode(machineID: client.machineID) == nil)
    }

    @Test("code_expired on a confirmed pairing keeps the code (durable re-register)")
    func codeExpiredOnConfirmedKeepsCode() {
        let client = makeClient(code: "654321")
        client.setEverConfirmedForTesting(true)
        client.persistPairing()
        #expect(E2ERelayClient.storedPairingCode(machineID: client.machineID) == "654321")
        #expect(E2ERelayClient.storedPairingConfirmed(machineID: client.machineID))

        client.simulateIncomingFrameForTesting(#"{"type":"error","code":"code_expired","message":"pairing code expired, generate a new one"}"#)

        #expect(client.pairingState != .codeExpired)
        #expect(E2ERelayClient.storedPairingCode(machineID: client.machineID) == "654321")
    }

    @Test("older backend without the structured code field still falls back to substring match")
    func expiredSubstringFallback() {
        let client = makeClient()
        client.simulateIncomingFrameForTesting(#"{"type":"error","message":"pairing code expired, generate a new one"}"#)
        #expect(client.pairingState == .codeExpired)
    }

    @Test("key_mismatch (or any other error) is NOT treated as code_expired")
    func keyMismatchStaysPairingFailed() {
        let client = makeClient()
        client.simulateIncomingFrameForTesting(#"{"type":"error","code":"key_mismatch","message":"key mismatch -- pairing already established with a different key"}"#)

        guard case .pairingFailed = client.pairingState else {
            Issue.record("expected .pairingFailed, got \(client.pairingState)")
            return
        }
    }

    @Test("waiting frame decodes expiresAt into pairingExpiresAt")
    func waitingFrameDecodesExpiresAt() {
        let client = makeClient()
        let formatter = ISO8601DateFormatter()
        let expiryString = formatter.string(from: Date().addingTimeInterval(600))
        let expected = formatter.date(from: expiryString)! // round-trip: formatting drops sub-second precision

        client.simulateIncomingFrameForTesting(#"{"type":"waiting","message":"waiting for peer","expiresAt":"\#(expiryString)"}"#)

        #expect(client.pairingState == .waitingForPeer)
        #expect(client.pairingExpiresAt == expected)
    }

    @Test("waiting frame with no expiresAt (already-paired reconnect) leaves it nil")
    func waitingFrameWithoutExpiresAtStaysNil() {
        let client = makeClient()
        client.simulateIncomingFrameForTesting(#"{"type":"waiting","message":"waiting for peer"}"#)
        #expect(client.pairingState == .waitingForPeer)
        #expect(client.pairingExpiresAt == nil)
    }
}
