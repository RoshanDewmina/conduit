import Foundation
import CryptoKit
import Security

/// Storage seam for `RelayDeviceIdentity`'s persisted private key — the raw
/// SecItem calls in production, an in-memory box in tests (this repo's
/// accepted tradeoff for Keychain-backed logic; see `SecurityKit/Keychain.swift`).
public protocol RelayIdentityStore: Sendable {
    func read() -> Data?
    @discardableResult func write(_ data: Data) -> Bool
    func delete()
}

/// Real Keychain-backed store for the per-device relay identity private key.
///
/// Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` rather than the
/// `whenUnlockedThisDeviceOnly` class used elsewhere in this file's sibling
/// (`E2ERelayClient`'s now-removed per-machine key storage): this key must be
/// readable by a background relaunch/reconnect attempt (e.g. a push-triggered
/// wake) made before the device has been unlocked THIS boot, not only while
/// actively unlocked. Still `...ThisDeviceOnly` — never eligible for an
/// iCloud Keychain backup/restore-to-a-different-device, matching this
/// repo's never-sync-to-iCloud rule. It DOES survive an app delete+reinstall
/// on the same device (Keychain items are not tied to the app container and
/// are not cleared by uninstall) — that persistence, combined with never
/// regenerating this key on a fresh app launch, is what makes "pair once,
/// reconnect forever" possible across reinstalls.
public struct SecItemRelayIdentityStore: RelayIdentityStore {
    private let service: String
    private let account: String

    public init(
        service: String = "dev.lancer.relay",
        account: String = "lancer.relay.device.identity.privKey"
    ) {
        self.service = service
        self.account = account
    }

    public func read() -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    public func write(_ data: Data) -> Bool {
        _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    public func delete() {
        _ = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}

/// In-memory `RelayIdentityStore` for host-run unit tests — no Keychain
/// entitlement in a standalone SPM test bundle, and (unlike the per-machine
/// state elsewhere in this codebase, which is namespaced by a fresh
/// `RelayMachineID` per test) this identity is a single global slot, so
/// tests must inject an isolated instance rather than share the real device
/// Keychain entry.
public final class InMemoryRelayIdentityStore: RelayIdentityStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    public init(seed: Data? = nil) {
        self.data = seed
    }

    public func read() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    @discardableResult
    public func write(_ newData: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        data = newData
        return true
    }

    public func delete() {
        lock.lock()
        defer { lock.unlock() }
        data = nil
    }
}

/// Stable per-device Curve25519 identity for relay pairing.
///
/// Generated ONCE (on first use, ever) and persisted; every `E2ERelayClient`
/// instance loads THIS keypair instead of minting its own. Before this
/// existed, `E2ERelayClient.init()` called `PairingCrypto.generateKeyPair()`
/// on every construction, so a pairing retry — a new `RelayPairingSheet`
/// instance, an app relaunch, or a fresh install on the same device —
/// presented the backend a BRAND NEW public key. The push-backend pins the
/// first phone public key it sees per pairing code and rejects any other key
/// on that code as a hijack attempt, so every such retry was permanently
/// rejected (root-caused 2026-07-11 from backend logs). Loading one stable
/// identity here — and `E2ERelayClient` never regenerating it — means a
/// retry re-presents the exact key the backend already pinned.
///
/// Fail-closed on corruption: a present-but-undecodable stored key is never
/// silently reused. `loadOrCreate()` reports `.regeneratedAfterCorruption` in
/// that case so the caller (`RelayMachineMigration
/// .invalidateAllMachinesIfIdentityRegenerated`) can wipe every persisted
/// per-machine pairing and require an honest re-pair, instead of retry-
/// looping forever against a pin the new key can never satisfy.
public final class RelayDeviceIdentity: @unchecked Sendable {

    /// The app-wide instance. Production `E2ERelayClient`s default to this;
    /// tests inject a fresh instance backed by `InMemoryRelayIdentityStore`.
    public static let shared = RelayDeviceIdentity()

    public enum LoadOutcome: Sendable, Equatable {
        /// A previously persisted identity was read back successfully.
        case existing
        /// No identity existed yet (first launch ever); one was generated
        /// and persisted.
        case generated
        /// A persisted identity existed but its bytes did not decode as a
        /// valid Curve25519 private key; a fresh one was generated and
        /// persisted in its place. Callers MUST treat every previously
        /// persisted pairing as invalid — see the type doc comment.
        case regeneratedAfterCorruption
    }

    private let store: RelayIdentityStore
    private let lock = NSLock()
    private var cached: PairingCrypto.KeyPair?

    public init(store: RelayIdentityStore = SecItemRelayIdentityStore()) {
        self.store = store
    }

    /// Returns the persisted device identity keypair, generating + persisting
    /// one on first use. Safe to call from any thread/actor; internally
    /// serialized so two racing first-use callers can't mint and persist two
    /// different keypairs.
    @discardableResult
    public func loadOrCreate() -> (keyPair: PairingCrypto.KeyPair, outcome: LoadOutcome) {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return (cached, .existing) }
        if let data = store.read() {
            if let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
                let pair = PairingCrypto.KeyPair(privateKey: privateKey)
                cached = pair
                return (pair, .existing)
            }
            let pair = PairingCrypto.generateKeyPair()
            store.write(pair.privateKey.rawRepresentation)
            cached = pair
            return (pair, .regeneratedAfterCorruption)
        }
        let pair = PairingCrypto.generateKeyPair()
        store.write(pair.privateKey.rawRepresentation)
        cached = pair
        return (pair, .generated)
    }

    /// Convenience for callers that only need the keypair, not the outcome.
    public var keyPair: PairingCrypto.KeyPair { loadOrCreate().keyPair }

    /// Seeds the persisted identity with `privateKeyData` if — and only if —
    /// no identity has been generated or loaded yet. Used by the legacy
    /// single-pairing migration: an upgrading install already has a private
    /// key the backend pinned for its still-active pairing code, and letting
    /// this type mint a fresh device identity instead would make every
    /// subsequent reconnect look like a hijack attempt against that
    /// existing pin. Returns false (no-op) once an identity is already
    /// cached or persisted — this never clobbers a real identity.
    @discardableResult
    public func seedIfAbsent(_ privateKeyData: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard cached == nil, store.read() == nil else { return false }
        guard let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData) else {
            return false
        }
        let pair = PairingCrypto.KeyPair(privateKey: privateKey)
        store.write(pair.privateKey.rawRepresentation)
        cached = pair
        return true
    }
}
