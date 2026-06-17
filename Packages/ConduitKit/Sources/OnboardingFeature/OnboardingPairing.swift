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
    }

    /// Render the pairing QR for the current client/code as a SwiftUI `Image`, or nil on failure.
    public static func renderQR(relay: URL, code: String, publicKey: String) -> Image? {
        let payload = Payload(v: 1, relay: relay.absoluteString, code: code, pk: publicKey)
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
