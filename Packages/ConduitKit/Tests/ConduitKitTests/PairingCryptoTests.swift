import Testing
import Foundation
@testable import SecurityKit

@Suite("PairingCrypto")
struct PairingCryptoTests {

    @Test("round-trip encrypt/decrypt")
    func roundtrip() throws {
        let app = PairingCrypto.generateKeyPair()
        let helper = PairingCrypto.generateKeyPair()
        let key = try PairingCrypto.deriveSessionKey(
            privateKey: app.privateKey,
            peerPublicKeyBase64URL: helper.publicKeyBase64URL,
            helperID: "test-helper",
            helperPublicKeyBase64URL: helper.publicKeyBase64URL,
            appPublicKeyBase64URL: app.publicKeyBase64URL
        )
        let helperKey = try PairingCrypto.deriveSessionKey(
            privateKey: helper.privateKey,
            peerPublicKeyBase64URL: app.publicKeyBase64URL,
            helperID: "test-helper",
            helperPublicKeyBase64URL: helper.publicKeyBase64URL,
            appPublicKeyBase64URL: app.publicKeyBase64URL
        )
        let plain = Data("hello world".utf8)
        let sealed = try PairingCrypto.encrypt(plain, using: key)
        let opened = try PairingCrypto.decrypt(sealed, using: helperKey)
        #expect(opened == plain)
    }

    @Test("base64url round-trip")
    func b64url() throws {
        let raw = Data([0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x00, 0x01, 0x02])
        let encoded = Base64URL.encode(raw)
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        let decoded = try Base64URL.decode(encoded)
        #expect(decoded == raw)
    }
}
