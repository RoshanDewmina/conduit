import Testing
import Foundation
import CryptoKit
@testable import SSHTransport
@testable import SecurityKit
import LancerCore

@Suite("CredentialResolver")
struct CredentialResolverTests {

    @Test("Password auth method returns password credential immediately")
    func passwordPath() async throws {
        let keyStore = KeyStore(service: "dev.lancer.test.keys.\(UUID().uuidString)", inMemory: true)
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
        let keyStore = KeyStore(service: "dev.lancer.test.keys.\(UUID().uuidString)", inMemory: true)

        await #expect(throws: LancerError.unsupportedPlatform) {
            try await CredentialResolver.resolve(
                authMethod: .agent,
                passwordProvider: { "" },
                keyStore: keyStore
            )
        }
    }

    @Test("Ed25519 path loads key from store")
    func ed25519Path() async throws {
        let service = "dev.lancer.test.keys.\(UUID().uuidString)"
        let keyStore = KeyStore(service: service, inMemory: true)
        let privateKey = Curve25519.Signing.PrivateKey()
        let keyID = KeyID()
        _ = try await keyStore.importEd25519(tag: keyID.uuidString, rawPrivate: privateKey.rawRepresentation)

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
