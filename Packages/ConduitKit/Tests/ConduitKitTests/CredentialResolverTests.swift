import Testing
import Foundation
import CryptoKit
@testable import SSHTransport
@testable import SecurityKit
import ConduitCore

// Minimal BiometricGate subtype that always succeeds without prompting hardware.
// We can't subclass an actor, so we test CredentialResolver indirectly for paths
// that don't touch biometrics (password, agent-error). The ed25519 path is covered
// by the KeyStore integration tests.

@Suite("CredentialResolver")
struct CredentialResolverTests {

    @Test("Password auth method returns password credential immediately")
    func passwordPath() async throws {
        let keyStore = KeyStore(service: "dev.conduit.test.keys.\(UUID().uuidString)")

        let credential = try await CredentialResolver.resolve(
            authMethod: .password,
            passwordProvider: { "s3cr3t" },
            keyStore: keyStore
        )

        if case .password(let pw) = credential {
            #expect(pw == "s3cr3t")
        } else {
            Issue.record("Expected .password credential")
        }
    }

    @Test("Agent auth method throws unsupportedPlatform")
    func agentThrows() async throws {
        let keyStore = KeyStore(service: "dev.conduit.test.keys.\(UUID().uuidString)")

        await #expect(throws: ConduitError.unsupportedPlatform) {
            try await CredentialResolver.resolve(
                authMethod: .agent,
                passwordProvider: { "" },
                keyStore: keyStore
            )
        }
    }

    @Test("Ed25519 path unlocks biometrics and loads key from store")
    func ed25519Path() async throws {
        let service = "dev.conduit.test.keys.\(UUID().uuidString)"
        let keyStore = KeyStore(service: service)
        let privateKey = Curve25519.Signing.PrivateKey()
        let keyID = KeyID()
        _ = try await keyStore.importEd25519(tag: keyID.uuidString, rawPrivate: privateKey.rawRepresentation)

        // BiometricGate.shared degrades gracefully when no biometrics enrolled (simulator).
        let credential = try await CredentialResolver.resolve(
            authMethod: .ed25519(keyID: keyID),
            passwordProvider: { "" },
            keyStore: keyStore
        )

        try await keyStore.delete(tag: keyID.uuidString)

        if case .ed25519(let loadedKey) = credential {
            #expect(loadedKey.publicKey.rawRepresentation == privateKey.publicKey.rawRepresentation)
        } else {
            Issue.record("Expected .ed25519 credential")
        }
    }
}
