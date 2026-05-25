import Testing
import Foundation
@testable import SecurityKit
import ConduitCore

@Suite("HostKeyStore TOFU logic")
struct HostKeyStoreTests {

    // Use a unique in-memory store per test run to avoid cross-test pollution
    // and to work around keychain entitlement restrictions in standalone test bundles.
    private func freshStore() -> HostKeyStore {
        HostKeyStore(service: "dev.conduit.test.hostkeys.\(UUID().uuidString)", inMemory: true)
    }

    @Test("First connect returns unknown with the presented fingerprint")
    func firstConnectIsUnknown() async {
        let store = freshStore()
        let hostID = HostID()
        let fp = "SHA256:abcdef1234567890"

        let verdict = await store.verify(hostID: hostID, presented: fp)

        #expect(verdict == .unknown(fingerprint: fp))
    }

    @Test("Second connect after record returns match")
    func secondConnectIsMatch() async throws {
        let store = freshStore()
        let hostID = HostID()
        let fp = "SHA256:abcdef1234567890"

        try await store.record(hostID: hostID, fingerprint: fp)
        let verdict = await store.verify(hostID: hostID, presented: fp)

        #expect(verdict == .match)
    }

    @Test("Changed fingerprint returns mismatch with expected/actual")
    func changedFingerprintIsMismatch() async throws {
        let store = freshStore()
        let hostID = HostID()
        let original = "SHA256:original"
        let changed  = "SHA256:changed"

        try await store.record(hostID: hostID, fingerprint: original)
        let verdict = await store.verify(hostID: hostID, presented: changed)

        #expect(verdict == .mismatch(expected: original, actual: changed))
    }

    @Test("forget clears the record so next connect is unknown again")
    func forgetResetsToUnknown() async throws {
        let store = freshStore()
        let hostID = HostID()
        let fp = "SHA256:abcdef1234567890"

        try await store.record(hostID: hostID, fingerprint: fp)
        try await store.forget(hostID: hostID)
        let verdict = await store.verify(hostID: hostID, presented: fp)

        #expect(verdict == .unknown(fingerprint: fp))
    }

    @Test("Different hosts tracked independently")
    func differentHostsAreIndependent() async throws {
        let store = freshStore()
        let hostA = HostID()
        let hostB = HostID()
        let fpA = "SHA256:aaaa"
        let fpB = "SHA256:bbbb"

        try await store.record(hostID: hostA, fingerprint: fpA)

        let verdictA = await store.verify(hostID: hostA, presented: fpA)
        let verdictB = await store.verify(hostID: hostB, presented: fpB)

        #expect(verdictA == .match)
        #expect(verdictB == .unknown(fingerprint: fpB))
    }
}
