import Foundation
import CryptoKit
@preconcurrency import Citadel
import LancerCore

/// SSH credential supplied at connect-time. The KeyStore is consulted by
/// the caller; we keep this enum opaque to it so SSHTransport itself does
/// not import SecurityKit (avoids cycles and keeps it testable on macOS).
public enum SSHCredential: @unchecked Sendable {
    case password(String)
    case ed25519(Curve25519.Signing.PrivateKey)
    case rsa(Insecure.RSA.PrivateKey)
    case ecdsaP256(P256.Signing.PrivateKey)
    case ecdsaP384(P384.Signing.PrivateKey)
    case ecdsaP521(P521.Signing.PrivateKey)
}
