import Foundation
import Testing
@testable import AccountKit
@testable import SecurityKit

@Suite("Vendor account store")
struct VendorAccountStoreTests {
    private func makeStore() -> VendorAccountStore {
        VendorAccountStore(
            keychain: Keychain(service: "test.vendorAccounts.\(UUID().uuidString)", inMemory: true)
        )
    }

    @Test("round-trips accounts per vendor")
    func roundTrip() async throws {
        let store = makeStore()
        let a = VendorAccount(vendor: "claudeCode", label: "Work", handle: "work@example.com")
        let b = VendorAccount(vendor: "claudeCode", label: "Personal", handle: "me@example.com")
        try await store.add(a)
        try await store.add(b)

        let list = try await store.accounts(for: "claudeCode")
        #expect(list.count == 2)
        #expect(Set(list.map(\.handle)) == Set(["work@example.com", "me@example.com"]))
        #expect(try await store.accounts(for: "codex").isEmpty)
    }

    @Test("first add becomes active; select updates active and lastSelectedAt")
    func activeSelection() async throws {
        let store = makeStore()
        let a = VendorAccount(vendor: "codex", label: "A", handle: "a@x.com")
        let b = VendorAccount(vendor: "codex", label: "B", handle: "b@x.com")
        try await store.add(a)
        try await store.add(b)

        #expect(try await store.activeAccountID(for: "codex") == a.id)

        let selectedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.select(id: b.id, vendor: "codex", at: selectedAt)

        #expect(try await store.activeAccountID(for: "codex") == b.id)
        let active = try await store.activeAccount(for: "codex")
        #expect(active?.id == b.id)
        #expect(active?.lastSelectedAt == selectedAt)
    }

    @Test("remove clears active and promotes remaining account")
    func removePromotes() async throws {
        let store = makeStore()
        let a = VendorAccount(vendor: "kimi", label: "A", handle: "a")
        let b = VendorAccount(vendor: "kimi", label: "B", handle: "b")
        try await store.add(a)
        try await store.add(b)
        try await store.select(id: a.id, vendor: "kimi")

        try await store.remove(id: a.id, vendor: "kimi")
        #expect(try await store.activeAccountID(for: "kimi") == b.id)
        #expect(try await store.accounts(for: "kimi").map(\.id) == [b.id])

        try await store.remove(id: b.id, vendor: "kimi")
        #expect(try await store.activeAccountID(for: "kimi") == nil)
        #expect(try await store.accounts(for: "kimi").isEmpty)
    }

    @Test("select unknown id throws")
    func selectMissingThrows() async {
        let store = makeStore()
        await #expect(throws: VendorAccountStoreError.accountNotFound) {
            try await store.select(id: "missing", vendor: "pi")
        }
    }

    @Test("vendor catalog includes pi")
    func catalogIncludesPi() {
        #expect(VendorAccountVendor.allCases.map(\.rawValue).contains("pi"))
        #expect(VendorAccountVendor.pi.displayName == "Pi")
    }
}
