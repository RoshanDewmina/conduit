import Testing
import Foundation
@testable import SecurityKit

@Suite("KeyStore")
struct KeyStoreTests {

    @Test("public key format is well-formed", .disabled("requires Keychain entitlement"))
    func generate() async throws {
        let store = KeyStore(service: "test.conduit.keystore")
        let info = try await store.generateEd25519(tag: "test-key")
        #expect(info.openSSH.hasPrefix("ssh-ed25519 "))
        #expect(info.sha256Fingerprint.hasPrefix("SHA256:"))
        try await store.delete(tag: "test-key")
    }
}
