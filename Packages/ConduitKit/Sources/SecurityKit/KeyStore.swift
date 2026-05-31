import Foundation
import CryptoKit
import ConduitCore

/// Stores SSH Ed25519 keypairs.
///
/// On devices with a Secure Enclave, we *would* generate the key inside the
/// enclave and never expose private bytes. However, `swift-nio-ssh` and
/// `Citadel` need to sign in-process, so for the SSH use case we keep the
/// raw 32-byte private representation in the Keychain with
/// `whenUnlockedThisDeviceOnly`. A future improvement is a custom
/// `NIOSSHPrivateKey` backed by SecKey operations on Secure Enclave keys
/// (tracked in §16 Q-Enclave).
public actor KeyStore {
    public struct PublicKeyInfo: Sendable, Hashable {
        public let openSSH: String
        public let sha256Fingerprint: String  // matches `ssh-keygen -l -f` SHA256
    }

    public let keychain: Keychain

    public init(service: String = "dev.conduit.mobile.sshkeys", inMemory: Bool = false) {
        self.keychain = Keychain(service: service, inMemory: inMemory)
    }

    // MARK: - Ed25519

    public func generateEd25519(tag: String, comment: String? = nil) async throws -> PublicKeyInfo {
        let pk = Curve25519.Signing.PrivateKey()
        try await keychain.write(pk.rawRepresentation, account: tag)
        return Self.publicKey(for: pk.publicKey, comment: comment ?? tag)
    }

    public func importEd25519(tag: String, rawPrivate: Data, comment: String? = nil) async throws -> PublicKeyInfo {
        let pk = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivate)
        try await keychain.write(pk.rawRepresentation, account: tag)
        return Self.publicKey(for: pk.publicKey, comment: comment ?? tag)
    }

    /// Parse and import an OpenSSH private key PEM.
    ///
    /// - Parameters:
    ///   - tag:        Unique identifier stored in Keychain (UUID string recommended).
    ///   - pem:        Full PEM text (BEGIN OPENSSH PRIVATE KEY … END OPENSSH PRIVATE KEY).
    ///   - passphrase: Passphrase for encrypted keys; `nil` for unencrypted keys.
    ///                 **Never persisted** — used transiently during parsing only.
    ///   - comment:    Optional human-readable label. Falls back to `tag` when omitted.
    /// - Returns: `PublicKeyInfo` with the OpenSSH public key string and SHA256 fingerprint.
    /// - Throws:  `ConduitError.keyDecodeFailed` if parsing fails;
    ///            `ConduitError.keyNotFound` / Keychain errors if the write fails.
    public func importEd25519FromPEM(
        tag: String,
        pem: String,
        passphrase: String?,
        comment: String? = nil
    ) async throws -> PublicKeyInfo {
        let seed: Data
        do {
            seed = try OpenSSHKeyParser.parseEd25519(pem: pem, passphrase: passphrase)
        } catch let e as OpenSSHKeyParser.ParseError {
            throw ConduitError.keyDecodeFailed(reason: e.errorDescription ?? String(describing: e))
        }
        // Keychain attrs: whenUnlockedThisDeviceOnly, non-synchronizable (enforced by Keychain actor).
        return try await importEd25519(tag: tag, rawPrivate: seed, comment: comment)
    }

    public func loadEd25519(tag: String) async throws -> Curve25519.Signing.PrivateKey {
        let raw = try await keychain.read(account: tag)
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        } catch {
            throw ConduitError.keyDecodeFailed(reason: String(describing: error))
        }
    }

    public func delete(tag: String) async throws {
        try await keychain.delete(account: tag)
    }

    public func allTags() async throws -> [String] {
        try await keychain.allAccounts()
    }

    public func publicKey(tag: String, comment: String? = nil) async throws -> PublicKeyInfo {
        let pk = try await loadEd25519(tag: tag)
        return Self.publicKey(for: pk.publicKey, comment: comment ?? tag)
    }

    // MARK: - OpenSSH wire format

    private static func publicKey(for pub: Curve25519.Signing.PublicKey, comment: String) -> PublicKeyInfo {
        // ssh-ed25519 wire format:
        //   string  "ssh-ed25519"   (length-prefixed)
        //   string  pubkey-bytes    (length-prefixed, 32 bytes)
        var blob = Data()
        func writeLen(_ n: Int) {
            var be = UInt32(n).bigEndian
            blob.append(contentsOf: withUnsafeBytes(of: &be, Array.init))
        }
        let typeBytes = Data("ssh-ed25519".utf8)
        writeLen(typeBytes.count); blob.append(typeBytes)
        let keyBytes = pub.rawRepresentation
        writeLen(keyBytes.count);  blob.append(keyBytes)

        let b64 = blob.base64EncodedString()
        let openSSH = "ssh-ed25519 \(b64) \(comment)"

        // SHA256 fingerprint of the raw wire blob (matches `ssh-keygen -l -E sha256`).
        let digest = SHA256.hash(data: blob)
        let fpBase64 = Data(digest).base64EncodedString().trimmingCharacters(in: ["="])
        let fingerprint = "SHA256:\(fpBase64)"

        return PublicKeyInfo(openSSH: openSSH, sha256Fingerprint: fingerprint)
    }
}
