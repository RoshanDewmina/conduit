import Foundation
import CryptoKit
import ConduitCore

/// SSH credential supplied at connect-time. The KeyStore is consulted by
/// the caller; we keep this enum opaque to it so SSHTransport itself does
/// not import SecurityKit (avoids cycles and keeps it testable on macOS).
public enum SSHCredential: Sendable {
    case password(String)
    case ed25519(Curve25519.Signing.PrivateKey)
}
