import Foundation
import CryptoKit
import ConduitCore

/// X25519 + HKDF-SHA256 + ChaCha20-Poly1305 framed messaging used for
/// device-to-device or device-to-helper pairing (M5+).
///
/// This is mirrored from the Helm protocol so a future Conduit desktop
/// helper can interoperate without redesigning the handshake.
public enum PairingCrypto {

    public static let frameVersion = 1
    public static let nonceByteCount = 12
    private static let frameAAD = Data("conduit-frame-v1".utf8)

    public struct KeyPair: Sendable {
        public let privateKey: Curve25519.KeyAgreement.PrivateKey
        public var publicKeyBase64URL: String { Base64URL.encode(privateKey.publicKey.rawRepresentation) }
    }

    public struct EncryptedFrame: Codable, Sendable, Equatable {
        public let version: Int
        public let nonce: String       // Base64URL
        public let ciphertext: String  // Base64URL
        public let tag: String         // Base64URL

        public init(version: Int, nonce: String, ciphertext: String, tag: String) {
            self.version = version
            self.nonce = nonce
            self.ciphertext = ciphertext
            self.tag = tag
        }
    }

    public static func generateKeyPair() -> KeyPair {
        KeyPair(privateKey: Curve25519.KeyAgreement.PrivateKey())
    }

    public static func deriveSessionKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKeyBase64URL: String,
        helperID: String,
        helperPublicKeyBase64URL: String,
        appPublicKeyBase64URL: String
    ) throws -> SymmetricKey {
        let peerData = try Base64URL.decode(peerPublicKeyBase64URL)
        let peer: Curve25519.KeyAgreement.PublicKey
        do {
            peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerData)
        } catch {
            throw ConduitError.keyDecodeFailed(reason: "peer public key")
        }
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let saltSeed = SHA256.hash(data: Data("conduit-pairing:\(helperID)".utf8))
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(saltSeed),
            sharedInfo: Data("conduit-v1:\(helperPublicKeyBase64URL):\(appPublicKeyBase64URL)".utf8),
            outputByteCount: 32
        )
    }

    public static func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> EncryptedFrame {
        let nonceData = try randomBytes(count: nonceByteCount)
        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: frameAAD)
        return EncryptedFrame(
            version: frameVersion,
            nonce: Base64URL.encode(Data(box.nonce)),
            ciphertext: Base64URL.encode(box.ciphertext),
            tag: Base64URL.encode(box.tag)
        )
    }

    public static func decrypt(_ frame: EncryptedFrame, using key: SymmetricKey) throws -> Data {
        guard frame.version == frameVersion else {
            throw ConduitError.invalidResponse(detail: "frame version \(frame.version)")
        }
        let nonceData = try Base64URL.decode(frame.nonce)
        guard nonceData.count == nonceByteCount else {
            throw ConduitError.invalidResponse(detail: "bad nonce length")
        }
        let box = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: nonceData),
            ciphertext: Base64URL.decode(frame.ciphertext),
            tag: Base64URL.decode(frame.tag)
        )
        return try ChaChaPoly.open(box, using: key, authenticating: frameAAD)
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw ConduitError.unknown(detail: "SecRandomCopyBytes \(status)")
        }
        return Data(bytes)
    }
}

// MARK: - Base64URL

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ string: String) throws -> Data {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        guard let data = Data(base64Encoded: s) else {
            throw ConduitError.invalidResponse(detail: "bad base64url")
        }
        return data
    }
}
