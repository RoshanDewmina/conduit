import Foundation
import ConduitCore
import SecurityKit

/// Resolves a `Host.AuthMethod` into a concrete `SSHCredential`.
/// For Ed25519, gates the private-key load behind biometric authentication.
public enum CredentialResolver {
    public typealias BiometricUnlock = @Sendable () async throws -> Void

    public static func resolve(
        authMethod: ConduitCore.Host.AuthMethod,
        passwordProvider: @Sendable () async throws -> String,
        keyStore: KeyStore,
        biometricUnlock: BiometricUnlock? = nil
    ) async throws -> SSHCredential {
        switch authMethod {
        case .password:
            return .password(try await passwordProvider())
        case .ed25519(let keyID):
            if let biometricUnlock {
                try await biometricUnlock()
            } else {
                try await BiometricGate.shared.unlock()
            }
            let key = try await keyStore.loadEd25519(tag: keyID.uuidString)
            return .ed25519(key)
        case .agent:
            throw ConduitError.unsupportedPlatform  // M5+
        }
    }
}
