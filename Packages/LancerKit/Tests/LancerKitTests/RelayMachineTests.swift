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
}
