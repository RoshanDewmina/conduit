import Testing
import Foundation
@testable import SecurityKit

@Suite("KeyStore")
struct KeyStoreTests {

    @Test("public key format is well-formed")
    func generate() async throws {
        let tag = "test-key-\(UUID().uuidString)"
        let store = KeyStore(service: "test.lancer.keystore.\(UUID().uuidString)", inMemory: true)
        let info = try await store.generateEd25519(tag: tag)
        #expect(info.openSSH.hasPrefix("ssh-ed25519 "))
        #expect(info.sha256Fingerprint.hasPrefix("SHA256:"))
        try await store.delete(tag: tag)
    }
}
