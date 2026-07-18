import Foundation
import SecurityKit

/// Keychain-backed store for per-vendor account metadata + active selection.
/// Manual switching only — no auto-rotate / rate-limit logic.
public actor VendorAccountStore {
    public static let keychainService = "dev.lancer.mobile.vendorAccounts"

    private let keychain: Keychain
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(keychain: Keychain = Keychain(service: VendorAccountStore.keychainService)) {
        self.keychain = keychain
    }

    public func accounts(for vendor: String) async throws -> [VendorAccount] {
        guard let data = try? await keychain.read(account: Self.accountsKey(vendor)) else {
            return []
        }
        return try decoder.decode([VendorAccount].self, from: data)
    }

    public func activeAccountID(for vendor: String) async throws -> String? {
        guard let data = try? await keychain.read(account: Self.activeKey(vendor)),
              let id = String(data: data, encoding: .utf8),
              !id.isEmpty
        else { return nil }
        return id
    }

    public func activeAccount(for vendor: String) async throws -> VendorAccount? {
        guard let id = try await activeAccountID(for: vendor) else { return nil }
        return try await accounts(for: vendor).first { $0.id == id }
    }

    public func add(_ account: VendorAccount) async throws {
        var list = try await accounts(for: account.vendor)
        list.removeAll { $0.id == account.id }
        list.append(account)
        try await writeAccounts(list, vendor: account.vendor)
        if try await activeAccountID(for: account.vendor) == nil {
            try await setActiveID(account.id, vendor: account.vendor)
        }
    }

    public func remove(id: String, vendor: String) async throws {
        var list = try await accounts(for: vendor)
        list.removeAll { $0.id == id }
        try await writeAccounts(list, vendor: vendor)
        if try await activeAccountID(for: vendor) == id {
            if let next = list.first {
                try await setActiveID(next.id, vendor: vendor)
            } else {
                try await keychain.delete(account: Self.activeKey(vendor))
            }
        }
    }

    /// Selects an account as active and stamps `lastSelectedAt`. Caller owns
    /// restart-safety UX when a live session is running for this vendor.
    public func select(id: String, vendor: String, at date: Date = .now) async throws {
        var list = try await accounts(for: vendor)
        guard let index = list.firstIndex(where: { $0.id == id }) else {
            throw VendorAccountStoreError.accountNotFound
        }
        list[index].lastSelectedAt = date
        try await writeAccounts(list, vendor: vendor)
        try await setActiveID(id, vendor: vendor)
    }

    // MARK: - Private

    private func writeAccounts(_ accounts: [VendorAccount], vendor: String) async throws {
        let data = try encoder.encode(accounts)
        try await keychain.write(data, account: Self.accountsKey(vendor), accessibility: .afterFirstUnlockThisDeviceOnly)
    }

    private func setActiveID(_ id: String, vendor: String) async throws {
        let data = Data(id.utf8)
        try await keychain.write(data, account: Self.activeKey(vendor), accessibility: .afterFirstUnlockThisDeviceOnly)
    }

    private static func accountsKey(_ vendor: String) -> String { "accounts.\(vendor)" }
    private static func activeKey(_ vendor: String) -> String { "active.\(vendor)" }
}

public enum VendorAccountStoreError: LocalizedError, Sendable, Equatable {
    case accountNotFound

    public var errorDescription: String? {
        switch self {
        case .accountNotFound: "That account is not in the list for this vendor."
        }
    }
}
