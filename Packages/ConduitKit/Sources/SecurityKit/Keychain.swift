import Foundation
import Security
import ConduitCore

/// A tiny, safe wrapper around the Security framework's generic-password
/// item class. Items are scoped by `service`, addressed by `account`, and
/// default to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never
/// synced to iCloud Keychain by default.
///
/// Pass `inMemory: true` in test contexts where keychain entitlements are
/// unavailable (standalone test bundles, Swift Package Manager test runs).
public actor Keychain {
    public enum Accessibility: Sendable {
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlockThisDeviceOnly

        fileprivate var rawValue: CFString {
            switch self {
            case .whenUnlockedThisDeviceOnly:     kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    public let service: String
    private let inMemory: Bool
    private var store: [String: Data] = [:]

    public init(service: String, inMemory: Bool = false) {
        self.service = service
        self.inMemory = inMemory
    }

    public func write(
        _ data: Data,
        account: String,
        accessibility: Accessibility = .whenUnlockedThisDeviceOnly
    ) throws {
        if inMemory {
            store[account] = data
            return
        }
        // Upsert: delete + add to avoid the SecItemUpdate accessibility quirk.
        _ = SecItemDelete(deleteQuery(account: account) as CFDictionary)
        let attrs: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecValueData as String:          data,
            kSecAttrAccessible as String:     accessibility.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConduitError.unknown(detail: "Keychain add failed: OSStatus \(status)")
        }
    }

    public func read(account: String) throws -> Data {
        if inMemory {
            guard let data = store[account] else {
                throw ConduitError.keyNotFound(tag: account)
            }
            return data
        }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw ConduitError.keyNotFound(tag: account)
        }
        return data
    }

    public func delete(account: String) throws {
        if inMemory {
            store.removeValue(forKey: account)
            return
        }
        let status = SecItemDelete(deleteQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConduitError.unknown(detail: "Keychain delete failed: OSStatus \(status)")
        }
    }

    public func allAccounts() throws -> [String] {
        if inMemory {
            return Array(store.keys)
        }
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecMatchLimit as String:       kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw ConduitError.unknown(detail: "Keychain list failed: OSStatus \(status)")
        }
        let items = result as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func deleteQuery(account: String) -> [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
