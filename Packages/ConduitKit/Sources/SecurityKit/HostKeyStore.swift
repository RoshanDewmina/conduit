import Foundation
import CryptoKit
import ConduitCore

/// Persists the SHA256 fingerprint of each host's public key (TOFU).
/// First connection: prompt for confirm, then record. Subsequent
/// mismatches throw `ConduitError.hostKeyMismatch`.
public actor HostKeyStore {
    public enum Verdict: Sendable, Equatable {
        case unknown(fingerprint: String)
        case match
        case mismatch(expected: String, actual: String)
    }

    private let keychain: Keychain

    public init(service: String = "dev.conduit.mobile.hostkeys") {
        self.keychain = Keychain(service: service)
    }

    public func recorded(for hostID: HostID) async -> String? {
        guard let data = try? await keychain.read(account: hostID.uuidString) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func record(hostID: HostID, fingerprint: String) async throws {
        try await keychain.write(Data(fingerprint.utf8), account: hostID.uuidString)
    }

    public func forget(hostID: HostID) async throws {
        try await keychain.delete(account: hostID.uuidString)
    }

    public func verify(hostID: HostID, presented fingerprint: String) async -> Verdict {
        if let known = await recorded(for: hostID) {
            return known == fingerprint
                ? .match
                : .mismatch(expected: known, actual: fingerprint)
        }
        return .unknown(fingerprint: fingerprint)
    }
}
