import Foundation
import CryptoKit
@preconcurrency import Citadel
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
    public enum KeyAlgorithm: String, Sendable, Hashable, Codable {
        case ed25519
        case rsa
        case ecdsaP256
        case ecdsaP384
        case ecdsaP521
    }

    public enum StoredPrivateKey: Sendable {
        case ed25519(Curve25519.Signing.PrivateKey)
        case rsa(Insecure.RSA.PrivateKey)
        case ecdsaP256(P256.Signing.PrivateKey)
        case ecdsaP384(P384.Signing.PrivateKey)
        case ecdsaP521(P521.Signing.PrivateKey)
    }

    public struct PublicKeyInfo: Sendable, Hashable {
        public let algorithm: KeyAlgorithm
        public let openSSH: String
        public let sha256Fingerprint: String  // matches `ssh-keygen -l -f` SHA256

        public init(algorithm: KeyAlgorithm, openSSH: String, sha256Fingerprint: String) {
            self.algorithm = algorithm
            self.openSSH = openSSH
            self.sha256Fingerprint = sha256Fingerprint
        }
    }

    private struct StoredKeyRecord: Codable, Sendable {
        enum Format: String, Codable, Sendable {
            case rawEd25519
            case openSSH
            case pem
        }

        let algorithm: KeyAlgorithm
        let format: Format
        let payload: Data
    }

    public let keychain: Keychain

    public init(service: String = "dev.conduit.mobile.sshkeys", inMemory: Bool = false) {
        self.keychain = Keychain(service: service, inMemory: inMemory)
    }

    // MARK: - Ed25519

    public func generateEd25519(tag: String, comment: String? = nil) async throws -> PublicKeyInfo {
        let pk = Curve25519.Signing.PrivateKey()
        try await persist(
            .init(
                algorithm: .ed25519,
                format: .rawEd25519,
                payload: pk.rawRepresentation
            ),
            tag: tag
        )
        return Self.publicKey(for: pk.publicKey, comment: comment ?? tag, algorithm: .ed25519)
    }

    public func importEd25519(tag: String, rawPrivate: Data, comment: String? = nil) async throws -> PublicKeyInfo {
        let pk = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivate)
        try await persist(
            .init(
                algorithm: .ed25519,
                format: .rawEd25519,
                payload: pk.rawRepresentation
            ),
            tag: tag
        )
        return Self.publicKey(for: pk.publicKey, comment: comment ?? tag, algorithm: .ed25519)
    }

    /// Imports an OpenSSH or PEM private key string.
    public func importPrivateKey(tag: String, keyString: String, comment: String? = nil) async throws -> PublicKeyInfo {
        let normalized = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConduitError.keyDecodeFailed(reason: "Key text is empty.")
        }

        if normalized.contains("BEGIN OPENSSH PRIVATE KEY") {
            let detected = try SSHKeyDetection.detectPrivateKeyType(from: normalized)
            switch detected {
            case .ed25519:
                try await persist(
                    .init(algorithm: .ed25519, format: .openSSH, payload: Data(normalized.utf8)),
                    tag: tag
                )
                return placeholderInfo(algorithm: .ed25519, payload: Data(normalized.utf8), comment: comment ?? tag)
            case .rsa:
                try await persist(
                    .init(algorithm: .rsa, format: .openSSH, payload: Data(normalized.utf8)),
                    tag: tag
                )
                return placeholderInfo(algorithm: .rsa, payload: Data(normalized.utf8), comment: comment ?? tag)
            case .ecdsaP256, .ecdsaP384, .ecdsaP521:
                throw ConduitError.keyDecodeFailed(
                    reason: "OpenSSH ECDSA private keys are unsupported. Import a PEM ECDSA key."
                )
            default:
                throw ConduitError.keyDecodeFailed(reason: "Unsupported OpenSSH key type.")
            }
        }

        if normalized.contains("BEGIN") && normalized.contains("PRIVATE KEY") {
            if normalized.contains("BEGIN RSA PRIVATE KEY") {
                try await persist(
                    .init(algorithm: .rsa, format: .pem, payload: Data(normalized.utf8)),
                    tag: tag
                )
                return placeholderInfo(algorithm: .rsa, payload: Data(normalized.utf8), comment: comment ?? tag)
            }
            if normalized.contains("BEGIN EC PRIVATE KEY") || normalized.contains("BEGIN PRIVATE KEY") {
                try await persist(
                    .init(algorithm: .ecdsaP256, format: .pem, payload: Data(normalized.utf8)),
                    tag: tag
                )
                return placeholderInfo(algorithm: .ecdsaP256, payload: Data(normalized.utf8), comment: comment ?? tag)
            }
        }

        throw ConduitError.keyDecodeFailed(reason: "Unsupported key format.")
    }

    public func importPrivateKey(tag: String, keyData: Data, comment: String? = nil) async throws -> PublicKeyInfo {
        guard let text = String(data: keyData, encoding: .utf8) else {
            throw ConduitError.keyDecodeFailed(reason: "The selected file is not UTF-8 text.")
        }
        return try await importPrivateKey(tag: tag, keyString: text, comment: comment)
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
        switch try await loadPrivateKey(tag: tag) {
        case .ed25519(let key):
            return key
        default:
            throw ConduitError.keyDecodeFailed(reason: "Stored key is not Ed25519.")
        }
    }

    public func loadPrivateKey(tag: String) async throws -> StoredPrivateKey {
        let record = try await loadRecord(tag: tag)
        switch (record.algorithm, record.format) {
        case (.ed25519, .rawEd25519):
            return try .ed25519(Curve25519.Signing.PrivateKey(rawRepresentation: record.payload))
        case (.ed25519, .openSSH), (.ed25519, .pem):
            throw ConduitError.keyDecodeFailed(reason: "OpenSSH/PEM Ed25519 import is metadata-only in this build.")
        case (.rsa, .openSSH):
            throw ConduitError.keyDecodeFailed(reason: "OpenSSH RSA import is metadata-only in this build.")
        case (.rsa, .pem):
            throw ConduitError.keyDecodeFailed(reason: "PEM RSA import is metadata-only in this build.")
        case (.ecdsaP256, .pem):
            throw ConduitError.keyDecodeFailed(reason: "PEM ECDSA import is metadata-only in this build.")
        case (.ecdsaP384, .pem):
            throw ConduitError.keyDecodeFailed(reason: "PEM ECDSA import is metadata-only in this build.")
        case (.ecdsaP521, .pem):
            throw ConduitError.keyDecodeFailed(reason: "PEM ECDSA import is metadata-only in this build.")
        default:
            throw ConduitError.keyDecodeFailed(reason: "Unsupported key algorithm/format combination.")
        }
    }

    public func delete(tag: String) async throws {
        try await keychain.delete(account: tag)
    }

    public func allTags() async throws -> [String] {
        try await keychain.allAccounts()
    }

    public func publicKey(tag: String, comment: String? = nil) async throws -> PublicKeyInfo {
        let record = try await loadRecord(tag: tag)
        switch try await loadPrivateKey(tag: tag) {
        case .ed25519(let pk):
            return Self.publicKey(for: pk.publicKey, comment: comment ?? tag, algorithm: .ed25519)
        case .rsa:
            return placeholderInfo(algorithm: .rsa, payload: record.payload, comment: comment ?? tag)
        case .ecdsaP256:
            return placeholderInfo(algorithm: .ecdsaP256, payload: record.payload, comment: comment ?? tag)
        case .ecdsaP384:
            return placeholderInfo(algorithm: .ecdsaP384, payload: record.payload, comment: comment ?? tag)
        case .ecdsaP521:
            return placeholderInfo(algorithm: .ecdsaP521, payload: record.payload, comment: comment ?? tag)
        }
    }

    // MARK: - OpenSSH wire format

    private static func publicKey(for pub: Curve25519.Signing.PublicKey, comment: String, algorithm: KeyAlgorithm) -> PublicKeyInfo {
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

        return PublicKeyInfo(algorithm: algorithm, openSSH: openSSH, sha256Fingerprint: fingerprint)
    }

    private func persist(_ record: StoredKeyRecord, tag: String) async throws {
        let data = try JSONEncoder().encode(record)
        try await keychain.write(data, account: tag)
    }

    private func loadRecord(tag: String) async throws -> StoredKeyRecord {
        let raw = try await keychain.read(account: tag)
        if let record = try? JSONDecoder().decode(StoredKeyRecord.self, from: raw) {
            return record
        }
        // Backward compatibility with pre-import Ed25519 storage.
        if raw.count == 32 {
            return .init(algorithm: .ed25519, format: .rawEd25519, payload: raw)
        }
        throw ConduitError.keyDecodeFailed(reason: "Unknown key format in keychain.")
    }

    private func placeholderInfo(algorithm: KeyAlgorithm, payload: Data, comment: String) -> PublicKeyInfo {
        let digest = SHA256.hash(data: payload)
        let fpBase64 = Data(digest).base64EncodedString().trimmingCharacters(in: ["="])
        return PublicKeyInfo(
            algorithm: algorithm,
            openSSH: "\(algorithm.rawValue) <private-key-imported> \(comment)",
            sha256Fingerprint: "SHA256:\(fpBase64)"
        )
    }
}
