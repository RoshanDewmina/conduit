import Foundation
import CryptoKit
import LancerCore
import SecurityKit

/// One-shot migration from the single legacy relay pairing to the new
/// namespaced + indexed multi-machine scheme. Call `migrateLegacyIfNeeded()`
/// once at app launch (a later lane wires the call site — this file is not
/// yet called from anywhere).
///
/// `@MainActor` because it reads `E2ERelayClient`'s legacy static persistence
/// API, and `E2ERelayClient` itself is `@MainActor`.
@MainActor
public enum RelayMachineMigration {

    /// Keychain service shared with `E2ERelayClient`'s raw SecItem calls —
    /// same attributes (whenUnlockedThisDeviceOnly, non-synchronizable), so
    /// entries written by one are readable by the other.
    private static let kcService = "dev.lancer.relay"

    /// Legacy singular Keychain account for the pairing private key, mirrored
    /// from `E2ERelayClient`'s private `kcAccountPrivKey` (not reachable from
    /// here since it's `private`, so the literal is duplicated intentionally —
    /// it is the one legacy key this migration deletes and never writes).
    private static let legacyKcAccountPrivKey = "lancer.relay.pairedPrivKey"

    /// Injectable Keychain used for the machines-index entry and for deleting
    /// the legacy privkey account, so tests can swap in an in-memory instance
    /// without touching the real device Keychain. Safe as a plain
    /// `@MainActor`-isolated static var since the enclosing type is
    /// `@MainActor` (no cross-isolation mutation to guard against).
    static var indexKeychain = Keychain(service: kcService)

    /// Reads the three legacy singular keys. If all three are present and the
    /// privkey decodes as a valid Curve25519 private key, migrates them into
    /// one `RelayMachineRecord` under a fresh `RelayMachineID`, writes the
    /// machines-index, deletes the legacy keys, and returns the new id.
    ///
    /// If any legacy piece is missing, or the privkey is present but invalid,
    /// deletes whatever legacy fragments exist and returns nil.
    ///
    /// If no legacy pairing exists at all, this is a no-op that returns nil.
    @discardableResult
    public static func migrateLegacyIfNeeded() async -> RelayMachineID? {
        guard E2ERelayClient.hasStoredPairing else { return nil }

        guard
            let code = E2ERelayClient.storedPairingCode(),
            let privKeyBase64 = E2ERelayClient.storedPairingPrivKey(),
            let relayURLString = E2ERelayClient.storedRelayURL(),
            let privKeyData = try? Base64URL.decode(privKeyBase64),
            (try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privKeyData)) != nil
        else {
            await deleteLegacyFragments()
            return nil
        }

        let machineID = RelayMachineID()
        UserDefaults.standard.set(code, forKey: "lancer.relay.machine.\(machineID.uuidString).code")
        UserDefaults.standard.set(relayURLString, forKey: "lancer.relay.machine.\(machineID.uuidString).url")
        do {
            try await indexKeychain.write(privKeyData, account: "lancer.relay.machine.\(machineID.uuidString).privKey")
        } catch {
            // Namespaced write failed: leave no partial state under the new id.
            UserDefaults.standard.removeObject(forKey: "lancer.relay.machine.\(machineID.uuidString).code")
            UserDefaults.standard.removeObject(forKey: "lancer.relay.machine.\(machineID.uuidString).url")
            await deleteLegacyFragments()
            return nil
        }

        let record = RelayMachineRecord(id: machineID, displayName: "Relay host")
        await writeIndex([record])
        await deleteLegacyFragments()
        return machineID
    }

    /// Reads the machines-index Keychain entry and decodes it, or `[]` if
    /// absent/corrupt.
    public static func readIndex() async -> [RelayMachineRecord] {
        guard let data = try? await indexKeychain.read(account: E2ERelayClient.kcAccountMachinesIndex),
              let records = try? JSONDecoder().decode([RelayMachineRecord].self, from: data)
        else { return [] }
        return records
    }

    /// Encodes and writes the machines-index Keychain entry.
    public static func writeIndex(_ records: [RelayMachineRecord]) async {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? await indexKeychain.write(data, account: E2ERelayClient.kcAccountMachinesIndex)
    }

    /// Deletes the three legacy singular keys, whichever of them exist. Used
    /// both on successful migration and on any invalid/partial legacy state.
    private static func deleteLegacyFragments() async {
        UserDefaults.standard.removeObject(forKey: "lancer.relay.pairedCode")
        UserDefaults.standard.removeObject(forKey: "lancer.relay.pairedRelayURL")
        try? await indexKeychain.delete(account: legacyKcAccountPrivKey)
    }
}
