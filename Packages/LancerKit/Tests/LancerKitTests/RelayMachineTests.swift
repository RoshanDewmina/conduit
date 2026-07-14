import Testing
import Foundation
import Security
import CryptoKit
@testable import LancerCore
@testable import SecurityKit
@testable import SSHTransport

// MARK: - Cross-platform: RelayMachineID / RelayMachineRecord / fleet cap
//
// LancerCore and SSHTransport are cross-platform, so unlike the iOS-gated
// suites elsewhere in this target, these run on macOS via `swift test` too.

@Suite struct RelayMachineCodableTests {
    @Test("RelayMachineID round-trips through Codable")
    func idRoundTrip() throws {
        let id = RelayMachineID()
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(RelayMachineID.self, from: data)
        #expect(decoded == id)
    }

    @Test("RelayMachineRecord round-trips through Codable")
    func recordRoundTrip() throws {
        let record = RelayMachineRecord(
            displayName: "Roshan's Mac Studio",
            pairedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastConnectedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(RelayMachineRecord.self, from: data)
        #expect(decoded == record)
        #expect(decoded.id == record.id)
        #expect(decoded.displayName == record.displayName)
        #expect(decoded.pairedAt == record.pairedAt)
        #expect(decoded.lastConnectedAt == record.lastConnectedAt)
    }
}

@Suite struct RelayFleetCapTests {
    @Test("isRelayFleetFull is false under the cap, true at and above it")
    func capBoundary() {
        #expect(isRelayFleetFull(count: 0) == false)
        #expect(isRelayFleetFull(count: 1) == false)
        #expect(isRelayFleetFull(count: 2) == false)
        #expect(isRelayFleetFull(count: 3) == true)
        #expect(isRelayFleetFull(count: 4) == true)
        #expect(relayFleetMaxMachines == 3)
    }
}

// MARK: - RelayMachineMigration
//
// These tests touch real `UserDefaults.standard` (no in-memory swap is
// available for it in this codebase — see `ShellIntegrationScriptTests` for
// the same accepted tradeoff) but use an in-memory `Keychain` for the
// migration's own index/legacy-delete operations, injected via
// `RelayMachineMigration.indexKeychain`.

// `.serialized`: every test in this suite mutates shared global state
// (real `UserDefaults.standard` legacy keys + `RelayMachineMigration
// .indexKeychain`, which is a single static var, not per-test). Swift
// Testing runs a suite's tests concurrently by default, which raced these
// against each other (one test's migrated index record leaking into
// another's "should still be empty" assertion). Serializing matches how
// this shared, unswappable state is actually used at runtime — one
// migration, one app launch.
@MainActor
@Suite(.serialized) struct RelayMachineMigrationTests {

    private static let legacyCodeKey = "lancer.relay.pairedCode"
    private static let legacyURLKey = "lancer.relay.pairedRelayURL"
    private static let legacyPrivKeyAccount = "lancer.relay.pairedPrivKey"
    private static let kcService = "dev.lancer.relay"

    /// Clears every legacy key from real UserDefaults/Keychain so each test
    /// starts from a known-empty state and leaves none behind afterward.
    private func clearLegacyState() {
        UserDefaults.standard.removeObject(forKey: Self.legacyCodeKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyURLKey)
        _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.kcService,
            kSecAttrAccount as String: Self.legacyPrivKeyAccount,
        ] as CFDictionary)
    }

    /// Checks the store the migration's own delete actually targets
    /// (`RelayMachineMigration.indexKeychain`, currently the test's injected
    /// in-memory instance) — not the real device Keychain, which the
    /// migration's delete never touches once `indexKeychain` is swapped.
    private func legacyPrivKeyExists() async -> Bool {
        (try? await RelayMachineMigration.indexKeychain.read(account: Self.legacyPrivKeyAccount)) != nil
    }

    /// Writes the legacy privkey through BOTH the real device Keychain (so
    /// `E2ERelayClient.storedPairingPrivKey()` — which always reads via raw
    /// SecItem, never via the injectable `indexKeychain` — can see it) and
    /// the currently-injected `RelayMachineMigration.indexKeychain` (so the
    /// migration's own legacy-delete, which goes through `indexKeychain`,
    /// can find and remove it during this test). In production both of
    /// those resolve to the same real device Keychain entry; only under test
    /// injection do they diverge, so both must be seeded for the round trip
    /// to be exercised faithfully.
    private func writeLegacyPrivKeyRaw(_ data: Data) async {
        _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.kcService,
            kSecAttrAccount as String: Self.legacyPrivKeyAccount,
        ] as CFDictionary)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.kcService,
            kSecAttrAccount as String: Self.legacyPrivKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        _ = SecItemAdd(attrs as CFDictionary, nil)
        try? await RelayMachineMigration.indexKeychain.write(data, account: Self.legacyPrivKeyAccount)
    }

    @Test("no legacy pairing at all: no-op, returns nil, index stays empty")
    func noLegacyPairing() async {
        clearLegacyState()
        defer { clearLegacyState() }
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)

        let result = await RelayMachineMigration.migrateLegacyIfNeeded()
        #expect(result == nil)

        let index = await RelayMachineMigration.readIndex()
        #expect(index.isEmpty)
    }

    @Test("valid legacy state migrates into exactly one indexed machine, legacy keys gone")
    func validLegacyState() async {
        clearLegacyState()
        defer { clearLegacyState() }
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        UserDefaults.standard.set("123456", forKey: Self.legacyCodeKey)
        UserDefaults.standard.set("https://relay.example.com", forKey: Self.legacyURLKey)
        await writeLegacyPrivKeyRaw(privateKey.rawRepresentation)

        let result = await RelayMachineMigration.migrateLegacyIfNeeded()
        #expect(result != nil)

        guard let machineID = result else { return }
        #expect(E2ERelayClient.hasStoredPairing(machineID: machineID))
        #expect(E2ERelayClient.storedPairingCode(machineID: machineID) == "123456")
        #expect(E2ERelayClient.storedRelayURL(machineID: machineID) == "https://relay.example.com")

        let index = await RelayMachineMigration.readIndex()
        #expect(index.count == 1)
        #expect(index.first?.id == machineID)
        #expect(index.first?.displayName == "Relay host")

        #expect(UserDefaults.standard.string(forKey: Self.legacyCodeKey) == nil)
        #expect(UserDefaults.standard.string(forKey: Self.legacyURLKey) == nil)
        #expect(await legacyPrivKeyExists() == false)

        E2ERelayClient.deleteStoredPairing(machineID: machineID)
    }

    @Test("retired singular pairing migrates to Fly and backfills confirmation")
    func retiredLegacyStateBackfillsConfirmation() async {
        clearLegacyState()
        defer { clearLegacyState() }
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        UserDefaults.standard.set("232323", forKey: Self.legacyCodeKey)
        UserDefaults.standard.set(RelaySettings.retiredHostedURLString, forKey: Self.legacyURLKey)
        await writeLegacyPrivKeyRaw(privateKey.rawRepresentation)

        let result = await RelayMachineMigration.migrateLegacyIfNeeded()
        guard let machineID = result else {
            Issue.record("retired legacy pairing did not migrate")
            return
        }
        defer { E2ERelayClient.deleteStoredPairing(machineID: machineID) }

        #expect(E2ERelayClient.storedPairingCode(machineID: machineID) == "232323")
        #expect(E2ERelayClient.storedRelayURL(machineID: machineID) == RelaySettings.defaultURLString)
        #expect(E2ERelayClient.storedPairingConfirmed(machineID: machineID))
    }

    @Test("partial legacy state (code present, privkey missing) returns nil, fragments cleared")
    func partialLegacyState() async {
        clearLegacyState()
        defer { clearLegacyState() }
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)

        UserDefaults.standard.set("654321", forKey: Self.legacyCodeKey)
        // Deliberately omit the relay URL and the privkey.

        let result = await RelayMachineMigration.migrateLegacyIfNeeded()
        #expect(result == nil)

        let index = await RelayMachineMigration.readIndex()
        #expect(index.isEmpty)

        #expect(UserDefaults.standard.string(forKey: Self.legacyCodeKey) == nil)
        #expect(UserDefaults.standard.string(forKey: Self.legacyURLKey) == nil)
        #expect(await legacyPrivKeyExists() == false)
    }

    @Test("corrupt privkey bytes (present but not valid Curve25519) returns nil, fragments cleared")
    func corruptPrivKey() async {
        clearLegacyState()
        defer { clearLegacyState() }
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)

        UserDefaults.standard.set("111111", forKey: Self.legacyCodeKey)
        UserDefaults.standard.set("https://relay.example.com", forKey: Self.legacyURLKey)
        // Garbage bytes: wrong length / not a valid Curve25519 private key.
        await writeLegacyPrivKeyRaw(Data([0x00, 0x01, 0x02]))

        let result = await RelayMachineMigration.migrateLegacyIfNeeded()
        #expect(result == nil)

        let index = await RelayMachineMigration.readIndex()
        #expect(index.isEmpty)

        #expect(UserDefaults.standard.string(forKey: Self.legacyCodeKey) == nil)
        #expect(UserDefaults.standard.string(forKey: Self.legacyURLKey) == nil)
        #expect(await legacyPrivKeyExists() == false)
    }

    @Test("valid legacy state seeds an absent device identity with the legacy privkey")
    func validLegacyStateSeedsAbsentIdentity() async {
        clearLegacyState()
        defer { clearLegacyState() }
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        UserDefaults.standard.set("123456", forKey: Self.legacyCodeKey)
        UserDefaults.standard.set("https://relay.example.com", forKey: Self.legacyURLKey)
        await writeLegacyPrivKeyRaw(privateKey.rawRepresentation)

        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let result = await RelayMachineMigration.migrateLegacyIfNeeded(identity: identity)
        #expect(result != nil)
        if let machineID = result {
            E2ERelayClient.deleteStoredPairing(machineID: machineID)
        }

        // The upgrading install's already-pinned key becomes the device
        // identity — not a freshly minted one — so the very next reconnect
        // presents the SAME public key the backend already trusts.
        let (keyPair, outcome) = identity.loadOrCreate()
        #expect(outcome == .existing)
        #expect(keyPair.publicKeyBase64URL == PairingCrypto.KeyPair(privateKey: privateKey).publicKeyBase64URL)
    }

    @Test("valid legacy state does NOT clobber an already-present device identity")
    func validLegacyStateDoesNotClobberExistingIdentity() async {
        clearLegacyState()
        defer { clearLegacyState() }
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)

        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())
        let existing = identity.loadOrCreate().keyPair

        let legacyPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        UserDefaults.standard.set("123456", forKey: Self.legacyCodeKey)
        UserDefaults.standard.set("https://relay.example.com", forKey: Self.legacyURLKey)
        await writeLegacyPrivKeyRaw(legacyPrivateKey.rawRepresentation)

        let result = await RelayMachineMigration.migrateLegacyIfNeeded(identity: identity)
        if let machineID = result {
            E2ERelayClient.deleteStoredPairing(machineID: machineID)
        }

        #expect(identity.loadOrCreate().keyPair.publicKeyBase64URL == existing.publicKeyBase64URL)
    }

    // Fail-closed launch-time reconciliation. These live in this suite (not
    // in RelayDeviceIdentityTests.swift) because they mutate the shared
    // `indexKeychain` static and must serialize with every other test that
    // swaps it — separate suites run concurrently and race that static.

    @Test("a healthy (non-corrupt) identity leaves persisted machines untouched")
    func healthyIdentityNoOp() async {
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore())

        let record = RelayMachineRecord(displayName: "Test Host")
        await RelayMachineMigration.writeIndex([record])
        UserDefaults.standard.set("123456", forKey: "lancer.relay.machine.\(record.id.uuidString).code")
        UserDefaults.standard.set("https://relay.example.com", forKey: "lancer.relay.machine.\(record.id.uuidString).url")
        defer { E2ERelayClient.deleteStoredPairing(machineID: record.id) }

        let wiped = await RelayMachineMigration.invalidateAllMachinesIfIdentityRegenerated(identity: identity)
        #expect(wiped == false)

        let index = await RelayMachineMigration.readIndex()
        #expect(index.count == 1)
        #expect(E2ERelayClient.hasStoredPairing(machineID: record.id) == true)
    }

    @Test("a corrupt-and-regenerated identity wipes every persisted machine pairing")
    func corruptIdentityWipesAllMachines() async {
        RelayMachineMigration.indexKeychain = Keychain(service: Self.kcService, inMemory: true)
        let identity = RelayDeviceIdentity(store: InMemoryRelayIdentityStore(seed: Data([0x00, 0x01])))

        let record = RelayMachineRecord(displayName: "Test Host")
        await RelayMachineMigration.writeIndex([record])
        UserDefaults.standard.set("123456", forKey: "lancer.relay.machine.\(record.id.uuidString).code")
        UserDefaults.standard.set("https://relay.example.com", forKey: "lancer.relay.machine.\(record.id.uuidString).url")
        defer { E2ERelayClient.deleteStoredPairing(machineID: record.id) }

        let wiped = await RelayMachineMigration.invalidateAllMachinesIfIdentityRegenerated(identity: identity)
        #expect(wiped == true)

        let index = await RelayMachineMigration.readIndex()
        #expect(index.isEmpty)
        #expect(E2ERelayClient.hasStoredPairing(machineID: record.id) == false)
    }
}

// MARK: - Namespaced pairing restore (incomplete-state regression)
//
// Regression for the 2026-07-03 on-device finding: a client whose restore
// had silently no-op'd dialed the relay with an EMPTY pairing code and a
// freshly generated keypair, got HTTP 400 forever, and the UI showed the
// machine as permanently disconnected. These tests pin the behaviors that
// close that hole. Real UserDefaults + real Keychain (same accepted tradeoff
// as RelayMachineMigrationTests above); state is namespaced per fresh
// machineID, so no cross-test races.
//
// As of the 2026-07-11 stable-identity fix, the relay private key is no
// longer per-machine — every `E2ERelayClient` loads the one shared, always-
// persisted `RelayDeviceIdentity` at init time (see `RelayDeviceIdentityTests`
// for that layer's own coverage) — so restore validity now depends only on
// the namespaced code + URL, not on any per-machine Keychain entry.

@MainActor
@Suite struct E2ERelayClientRestoreTests {

    private func udCodeKey(_ id: RelayMachineID) -> String { "lancer.relay.machine.\(id.uuidString).code" }
    private func udURLKey(_ id: RelayMachineID) -> String { "lancer.relay.machine.\(id.uuidString).url" }

    @Test("complete persisted pairing restores and reports true")
    func completeRestore() {
        let relayURL = URL(string: "https://relay.example.com")!
        let client = E2ERelayClient(relayURL: relayURL, pairingCode: "222333")
        defer { E2ERelayClient.deleteStoredPairing(machineID: client.machineID) }
        client.persistPairing()

        let restored = E2ERelayClient(relayURL: URL(string: "https://other.example.com")!, pairingCode: "", machineID: client.machineID)
        #expect(restored.restoreNamespacedStoredPairing() == true)
        #expect(restored.pairingCode == "222333")
        #expect(restored.relayURL == relayURL)
        // Same device identity, so the restored client presents the exact
        // public key the original pairing pinned with the backend — the
        // property that makes a retry/relaunch/reinstall reconnect-safe.
        #expect(restored.publicKeyBase64URL == client.publicKeyBase64URL)
    }

    @Test("URL missing (code present) reports false and restores nothing")
    func missingURL() {
        let id = RelayMachineID()
        UserDefaults.standard.set("444555", forKey: udCodeKey(id))
        defer { E2ERelayClient.deleteStoredPairing(machineID: id) }

        let client = E2ERelayClient(relayURL: URL(string: "https://original.example.com")!, pairingCode: "", machineID: id)
        #expect(client.restoreNamespacedStoredPairing() == false)
        #expect(client.pairingCode.isEmpty)
        #expect(client.relayURL.host == "original.example.com")
    }

    @Test("code missing (URL present) reports false and restores nothing")
    func missingCode() {
        let id = RelayMachineID()
        UserDefaults.standard.set("https://relay.example.com", forKey: udURLKey(id))
        defer { E2ERelayClient.deleteStoredPairing(machineID: id) }

        let client = E2ERelayClient(relayURL: URL(string: "https://original.example.com")!, pairingCode: "", machineID: id)
        #expect(client.restoreNamespacedStoredPairing() == false)
        #expect(client.pairingCode.isEmpty)
        #expect(client.relayURL.host == "original.example.com")
    }

    @Test("invalid stored pairing code reports false and restores nothing")
    func invalidStoredCode() {
        let relayURL = URL(string: "https://relay.example.com")!
        let client = E2ERelayClient(relayURL: relayURL, pairingCode: "123456")
        defer { E2ERelayClient.deleteStoredPairing(machineID: client.machineID) }
        client.persistPairing()

        UserDefaults.standard.set("123", forKey: udCodeKey(client.machineID))
        #expect(E2ERelayClient.hasStoredPairing(machineID: client.machineID) == false)

        let restored = E2ERelayClient(relayURL: URL(string: "https://original.example.com")!, pairingCode: "", machineID: client.machineID)
        #expect(restored.restoreNamespacedStoredPairing() == false)
        #expect(restored.pairingCode.isEmpty)
        #expect(restored.relayURL.host == "original.example.com")
    }

    @Test("persistPairing refuses invalid pairing code shape")
    func invalidCodeNotPersisted() {
        let client = E2ERelayClient(relayURL: URL(string: "https://relay.example.com")!, pairingCode: "123")
        defer { E2ERelayClient.deleteStoredPairing(machineID: client.machineID) }

        client.persistPairing()

        #expect(E2ERelayClient.storedPairingCode(machineID: client.machineID) == nil)
        #expect(E2ERelayClient.hasStoredPairing(machineID: client.machineID) == false)
    }

    @Test("connect() with an invalid pairing code is refused, not dialed")
    func invalidCodeConnectRefused() {
        let client = E2ERelayClient(relayURL: URL(string: "https://relay.example.com")!, pairingCode: "123")
        client.connect()
        #expect(client.connectionState == .disconnected)
        #expect(client.pairingState == .unpaired)
    }

    @Test("retired hosted endpoint migrates without changing pairing identity")
    func retiredEndpointMigrates() {
        let id = RelayMachineID()
        UserDefaults.standard.set("909090", forKey: udCodeKey(id))
        UserDefaults.standard.set(RelaySettings.retiredHostedURLString, forKey: udURLKey(id))
        defer { E2ERelayClient.deleteStoredPairing(machineID: id) }

        let client = E2ERelayClient(
            relayURL: URL(string: "https://original.example.com")!,
            pairingCode: "",
            machineID: id
        )
        #expect(client.restoreNamespacedStoredPairing())
        #expect(client.relayURL.absoluteString == RelaySettings.defaultURLString)
        #expect(client.pairingCode == "909090")
        #expect(E2ERelayClient.storedPairingConfirmed(machineID: id))
        #expect(E2ERelayClient.storedRelayURL(machineID: id) == RelaySettings.defaultURLString)
    }

    @Test("self-host and lookalike endpoints are never migrated")
    func customEndpointsRemainUnchanged() {
        for relayURL in [
            "wss://self-host.example.com",
            RelaySettings.retiredHostedURLString + ".attacker.example",
        ] {
            let id = RelayMachineID()
            UserDefaults.standard.set("909091", forKey: udCodeKey(id))
            UserDefaults.standard.set(relayURL, forKey: udURLKey(id))
            defer { E2ERelayClient.deleteStoredPairing(machineID: id) }

            let client = E2ERelayClient(
                relayURL: URL(string: "https://original.example.com")!,
                pairingCode: "",
                machineID: id
            )
            #expect(client.restoreNamespacedStoredPairing())
            #expect(client.relayURL.absoluteString == relayURL)
        }
    }
}

@Suite struct RelaySettingsCutoverTests {
    @Test("DEBUG persisted retired override migrates but self-host override remains")
    func debugOverrideMigration() {
        let suite = "RelaySettingsCutoverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(RelaySettings.retiredHostedURLString, forKey: "lancer.debug.relayURL")
        #expect(RelaySettings.urlString(defaults: defaults) == RelaySettings.defaultURLString)
        #expect(defaults.string(forKey: "lancer.debug.relayURL") == RelaySettings.defaultURLString)

        defaults.set("wss://self-host.example.com", forKey: "lancer.debug.relayURL")
        #expect(RelaySettings.urlString(defaults: defaults) == "wss://self-host.example.com")
    }
}
