import Foundation

/// Result of `agent.pair.begin` — a one-time phone-pairing session minted by
/// `lancerd`. `qrPayload` is the exact string to encode into the QR image;
/// `code` is the same session shown as a 6-digit string for manual entry.
public struct PairingPayload: Codable, Sendable {
    public let relay: String
    public let code: String
    public let publicKey: String
    public let qrPayload: String

    public init(relay: String, code: String, publicKey: String, qrPayload: String) {
        self.relay = relay
        self.code = code
        self.publicKey = publicKey
        self.qrPayload = qrPayload
    }
}
