import Testing
import Foundation
import CryptoKit
@testable import LancerCore
@testable import SecurityKit
@testable import SSHTransport

// MARK: - RelayDeviceIdentity
//
// Coverage for the 2026-07-11 stable-identity fix (root cause: the relay
// client used to mint a brand-new Curve25519 keypair on every construction,
// so any pairing retry — a new pairing sheet, an app relaunch, a reinstall —
// presented the push-backend a NEW public key for a code it may have already
// pinned to the OLD one, and got rejected as a hijack attempt). Every test
// here injects its own `InMemoryRelayIdentityStore` — this identity is a
// single global slot per device, not namespaced per test like the rest of
// the relay-machine state, so tests must not share `.shared`.

@Suite struct RelayDeviceIdentityTests {

    @Test("first use generates and persists a key, reporting .generated")
    func generatesOnFirstUse() {
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let (keyPair, outcome) = identity.loadOrCreate()
        #expect(outcome == .generated)
        #expect(keyPair.publicKeyBase64URL.isEmpty == false)
    }

    @Test("repeated calls on the same instance return the identical cached keypair")
    func cachesWithinInstance() {
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let first = identity.loadOrCreate()
        let second = identity.loadOrCreate()
        #expect(first.outcome == .generated)
        #expect(second.outcome == .existing)
        #expect(first.keyPair.publicKeyBase64URL == second.keyPair.publicKeyBase64URL)
    }

    @Test("a fresh instance over the same store reloads the persisted key, not a new one")
    func persistsAcrossInstances() {
        let store = InMemoryRelayIdentityStore()
        let firstLaunch = RelayDeviceIdentity(store: store)
        let originalKey = firstLaunch.loadOrCreate().keyPair

        // Simulates an app relaunch: a brand-new RelayDeviceIdentity backed
        // by the SAME persisted store (in production, the same Keychain item
        // surviving relaunch/reinstall).
        let secondLaunch = RelayDeviceIdentity(store: store)
        let (reloadedKey, outcome) = secondLaunch.loadOrCreate()
        #expect(outcome == .existing)
        #expect(reloadedKey.publicKeyBase64URL == originalKey.publicKeyBase64URL)
    }

    @Test("corrupt stored bytes are never silently reused: regenerates and reports .regeneratedAfterCorruption")
    func failsClosedOnCorruption() {
        let store = InMemoryRelayIdentityStore(seed: Data([0x00, 0x01, 0x02]))
        let identity = RelayDeviceIdentity(store: store)
        let (keyPair, outcome) = identity.loadOrCreate()
        #expect(outcome == .regeneratedAfterCorruption)
        #expect(keyPair.publicKeyBase64URL.isEmpty == false)

        // The regenerated key is now what's persisted — a subsequent load
        // sees it as .existing, not corrupt again.
        let again = RelayDeviceIdentity(store: store).loadOrCreate()
        #expect(again.outcome == .existing)
        #expect(again.keyPair.publicKeyBase64URL == keyPair.publicKeyBase64URL)
    }

    @Test("seedIfAbsent adopts the given key when no identity exists yet")
    func seedIfAbsentAdoptsWhenEmpty() {
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let legacyKey = Curve25519.KeyAgreement.PrivateKey()

        let seeded = identity.seedIfAbsent(legacyKey.rawRepresentation)
        #expect(seeded == true)

        let (keyPair, outcome) = identity.loadOrCreate()
        #expect(outcome == .existing)
        #expect(keyPair.publicKeyBase64URL == PairingCrypto.KeyPair(privateKey: legacyKey).publicKeyBase64URL)
    }

    @Test("seedIfAbsent is a no-op once an identity is already cached or persisted")
    func seedIfAbsentNoOpsWhenPresent() {
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let original = identity.loadOrCreate().keyPair

        let other = Curve25519.KeyAgreement.PrivateKey()
        let seeded = identity.seedIfAbsent(other.rawRepresentation)
        #expect(seeded == false)
        #expect(identity.loadOrCreate().keyPair.publicKeyBase64URL == original.publicKeyBase64URL)
    }

    @Test("seedIfAbsent rejects undecodable bytes and leaves the identity absent")
    func seedIfAbsentRejectsGarbage() {
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let seeded = identity.seedIfAbsent(Data([0xFF, 0xEE]))
        #expect(seeded == false)
        // Still absent: the next loadOrCreate() generates fresh, not corrupt.
        #expect(identity.loadOrCreate().outcome == .generated)
    }
}

// MARK: - E2ERelayClient uses the injected identity, never mints its own

@MainActor
@Suite struct E2ERelayClientIdentityTests {

    @Test("two client instances over the same identity present the identical public key")
    func sharedIdentityAcrossInstances() {
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let clientA = E2ERelayClient(relayURL: URL(string: "https://relay.example.com")!, pairingCode: "111111", identity: identity)
        let clientB = E2ERelayClient(relayURL: URL(string: "https://relay.example.com")!, pairingCode: "222222", identity: identity)
        #expect(clientA.publicKeyBase64URL == clientB.publicKeyBase64URL)
    }

    @Test("beginPairingSession() rolls the pairing code but never the identity key")
    func beginPairingSessionDoesNotRotateKey() {
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let client = E2ERelayClient(relayURL: URL(string: "https://relay.example.com")!, pairingCode: "111111", identity: identity)
        let originalKey = client.publicKeyBase64URL
        let originalCode = client.pairingCode

        let newCode = client.beginPairingSession()

        #expect(newCode != originalCode)
        #expect(client.pairingCode == newCode)
        #expect(client.publicKeyBase64URL == originalKey)
    }

    @Test("a client constructed after a simulated relaunch presents the same key as before")
    func relaunchPresentsSameKey() {
        let store = InMemoryRelayIdentityStore()
        let beforeRelaunch = E2ERelayClient(
            relayURL: URL(string: "https://relay.example.com")!,
            pairingCode: "111111",
            identity: RelayDeviceIdentity(store: store)
        )
        let keyBeforeRelaunch = beforeRelaunch.publicKeyBase64URL

        // A fresh process/instance over the SAME persisted store, exactly
        // like relaunching the app (or reinstalling it, since the real
        // store is Keychain-backed and survives that).
        let afterRelaunch = E2ERelayClient(
            relayURL: URL(string: "https://relay.example.com")!,
            pairingCode: "222222",
            identity: RelayDeviceIdentity(store: store)
        )
        #expect(afterRelaunch.publicKeyBase64URL == keyBeforeRelaunch)
    }

    @Test("identityLoadOutcome reflects the underlying identity's outcome")
    func identityLoadOutcomeSurfaced() {
        let corruptStore = InMemoryRelayIdentityStore(seed: Data([0x00]))
        let client = E2ERelayClient(
            relayURL: URL(string: "https://relay.example.com")!,
            pairingCode: "111111",
            identity: RelayDeviceIdentity(store: corruptStore)
        )
        #expect(client.identityLoadOutcome == .regeneratedAfterCorruption)
    }
}

// NOTE: the fail-closed launch-time reconciliation tests
// (`invalidateAllMachinesIfIdentityRegenerated`) live inside
// `RelayMachineMigrationTests` in RelayMachineTests.swift, NOT here: they
// mutate the shared `RelayMachineMigration.indexKeychain` static, and Swift
// Testing runs separate suites concurrently — a second suite touching that
// static races the `.serialized` migration suite (observed as real failures
// on this suite's first run). All index-static-touching tests must share
// that one serialized suite.
