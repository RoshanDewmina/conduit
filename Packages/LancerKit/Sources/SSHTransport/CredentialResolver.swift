import Foundation
import LancerCore
import SecurityKit

/// Resolves a `Host.AuthMethod` into a concrete `SSHCredential`.
public enum CredentialResolver {
    public static func resolve(
        authMethod: LancerCore.Host.AuthMethod,
        passwordProvider: @Sendable () async throws -> String,
        keyStore: KeyStore
    ) async throws -> SSHCredential {
        switch authMethod {
        case .password:
            return .password(try await passwordProvider())
        case .ed25519(let keyID):
            let key = try await keyStore.loadEd25519(tag: keyID.uuidString)
            return .ed25519(key)
        case .agent:
            throw LancerError.unsupportedPlatform  // M5+
        }
    }
}
