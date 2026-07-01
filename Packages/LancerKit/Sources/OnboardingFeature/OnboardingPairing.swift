#if os(iOS)
import Foundation

/// Shared pairing helpers for the onboarding pair/scan/paired steps. The wire format here MUST
/// stay byte-compatible with the Go `lancerd pair` scanner — same JSON shape `{ v, relay, code, pk }`.
public enum OnboardingPairing {

    /// Wire format for the pairing QR. Decoded by the host's `lancerd pair`.
    struct Payload: Codable {
        let v: Int
        let relay: String
        let code: String
        let pk: String
        let accountBackend: String?
        let accountChallenge: String?
        let accountSecret: String?
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
}
#endif
