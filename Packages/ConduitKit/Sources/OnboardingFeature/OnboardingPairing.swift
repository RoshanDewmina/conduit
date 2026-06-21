#if os(iOS)
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem
import SSHTransport

/// Shared pairing helpers for the onboarding pair/scan/paired steps. The wire format here MUST
/// stay byte-compatible with `BridgePairingView.QRPairingPayload` and the Go `conduitd pair`
/// scanner — same JSON shape `{ v, relay, code, pk }`.
public enum OnboardingPairing {

    /// Wire format for the pairing QR. Decoded by the host's `conduitd pair`.
    struct Payload: Codable {
        let v: Int
        let relay: String
        let code: String
        let pk: String
        let accountBackend: String?
        let accountChallenge: String?
        let accountSecret: String?
    }

    /// Render the pairing QR for the current client/code as a SwiftUI `Image`, or nil on failure.
    public static func renderQR(relay: URL, code: String, publicKey: String) -> Image? {
        let payload = Payload(
            v: 1, relay: relay.absoluteString, code: code, pk: publicKey,
            accountBackend: nil, accountChallenge: nil, accountSecret: nil
        )
        guard let data = try? JSONEncoder().encode(payload),
              let ui = makeQR(from: data) else { return nil }
        return Image(uiImage: ui)
    }

    /// Extract a 6-digit pairing code from a scanned QR payload (full JSON) or a raw typed code.
    public static func extractCode(fromScanned payload: String) -> String? {
        if let data = payload.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            return normalize(decoded.code)
        }
        return normalize(payload)
    }

    /// Extract the pairing code AND the relay URL from a scanned `conduitd pair` QR
    /// (full JSON). The relay is returned only when the QR carries a valid one (so a
    /// self-hoster's phone adopts their relay); callers fall back to the shipped relay
    /// otherwise. A plain typed code returns `(code, nil)`. Returns nil if no valid
    /// 6-digit code is present.
    public static func extractPairing(fromScanned payload: String) -> (code: String, relay: URL?)? {
        if let data = payload.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data),
           let code = normalize(decoded.code) {
            return (code, URL(string: decoded.relay))
        }
        if let code = normalize(payload) { return (code, nil) }
        return nil
    }

    public struct DeviceBindingChallenge: Sendable, Equatable {
        public let backendURL: URL
        public let challengeID: String
        public let secret: String
    }

    /// Returns the account-binding material only when the daemon deliberately
    /// included it in a QR challenge. Legacy/offline relay QR codes continue to
    /// decode normally and never call the account backend.
    public static func extractDeviceBinding(fromScanned payload: String) -> DeviceBindingChallenge? {
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data),
              let backend = decoded.accountBackend.flatMap(URL.init(string:)),
              let challengeID = decoded.accountChallenge, challengeID.count >= 16,
              let secret = decoded.accountSecret, secret.count >= 32
        else { return nil }
        return DeviceBindingChallenge(backendURL: backend, challengeID: challengeID, secret: secret)
    }

    /// Keep only the digits; return nil unless exactly 6.
    public static func normalize(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return digits.count == 6 ? digits : nil
    }

    // MARK: Status presentation (mirrors BridgePairingView)

    @MainActor
    public static func stateLabel(_ client: E2ERelayClient) -> String {
        switch client.pairingState {
        case .paired:                 return "paired"
        case .pairingFailed(let why): return "pairing failed — \(why)"
        case .waitingForPeer:         return "waiting for bridge…"
        case .unpaired:
            switch client.connectionState {
            case .connecting:    return "connecting to relay…"
            case .reconnecting:  return "relay unreachable — retrying…"
            case .connected:     return "waiting for bridge…"
            case .disconnected:  return "not connected"
            }
        }
    }

    @MainActor
    public static func stateColor(_ client: E2ERelayClient, tokens t: ConduitTokens) -> Color {
        switch client.pairingState {
        case .paired:                          return t.ok
        case .pairingFailed:                   return t.danger
        case .waitingForPeer, .unpaired:       return t.accent
        }
    }

    // MARK: QR generation

    private static func makeQR(from data: Data) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
#endif
