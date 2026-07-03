#if os(iOS)
import Foundation
import Combine
import Observation
import LancerCore
import SSHTransport
import SessionFeature

@MainActor @Observable
public final class RelayFleetStore {
    public struct Machine: Identifiable, Sendable {
        public let id: RelayMachineID
        public var record: RelayMachineRecord
        public let client: E2ERelayClient
        public let bridge: E2ERelayBridge
        public var installedAgentVendors: [String]?

        public init(
            record: RelayMachineRecord,
            client: E2ERelayClient,
            bridge: E2ERelayBridge,
            installedAgentVendors: [String]? = nil
        ) {
            self.id = record.id
            self.record = record
            self.client = client
            self.bridge = bridge
            self.installedAgentVendors = installedAgentVendors
        }
    }

    public private(set) var machines: [Machine] = []

    /// Bridges each machine's `E2ERelayBridge.$isActive` (Combine, `@Published`)
    /// into this store's own `@Observable` change tracking. Without this,
    /// SwiftUI views reading `machines[i].bridge.isActive` (directly, or via
    /// `aggregateConnectionState`, or via the `RelayHomeEntry`/`RelayMachineRow`
    /// mappings built from `machines` in AppRoot.swift) never re-render when a
    /// relay reconnects or drops — `@Observable`'s macro only tracks direct
    /// mutations to properties on THIS object; a `@Published` change inside a
    /// referenced `ObservableObject` doesn't ripple back on its own. That was
    /// the root cause of the Home/Fleet/Settings connection dot and the
    /// sidebar footer all being able to read "disconnected" long after the
    /// daemon actually reconnected (observed live: daemon logs showed a
    /// successful reconnect while the UI still showed the stale state).
    @ObservationIgnored private var bridgeSubscriptions: [RelayMachineID: AnyCancellable] = [:]

    public init() {}

    public var isFull: Bool { isRelayFleetFull(count: machines.count) }

    public func machine(_ id: RelayMachineID) -> Machine? {
        machines.first { $0.id == id }
    }

    /// Records the vendor CLIs the relay reported as installed on this machine.
    /// No-op if the machine isn't in the store (e.g. removed mid-request).
    public func setInstalledAgentVendors(_ vendors: [String], for id: RelayMachineID) {
        guard let i = machines.firstIndex(where: { $0.id == id }) else { return }
        machines[i].installedAgentVendors = vendors
    }

    /// Updates the display name — either reported by the host (e.g. from a
    /// status update carrying its `hostName`) or set by the user renaming a
    /// paired machine. No-op if the machine isn't in the store. Persists to
    /// the Keychain-backed index so the name survives relaunch/hydration.
    public func updateDisplayName(_ name: String, for id: RelayMachineID) {
        guard let i = machines.firstIndex(where: { $0.id == id }) else { return }
        machines[i].record.displayName = name
        let records = machines.map(\.record)
        Task { await RelayMachineMigration.writeIndex(records) }
    }

    /// Adds a machine. No-op if the store is already at the cap — callers
    /// (the pairing UI, a later lane) must check `isFull` first and disable
    /// pairing UI accordingly rather than relying on this silently dropping.
    public func add(_ machine: Machine) {
        guard !isFull else { return }
        machines.append(machine)
        observeBridge(for: machine)
        let records = machines.map(\.record)
        Task { await RelayMachineMigration.writeIndex(records) }
    }

    /// Subscribes to `machine.bridge.$isActive` so a Combine-side change gets
    /// turned into an `@Observable`-visible mutation on this store. Reading
    /// `isActive` fresh at render time was already correct — the missing
    /// piece was ever telling SwiftUI a re-render was needed at all.
    private func observeBridge(for machine: Machine) {
        let id = machine.id
        bridgeSubscriptions[id] = machine.bridge.$isActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let i = self.machines.firstIndex(where: { $0.id == id }) else { return }
                // Re-assigning through the @Observable-synthesized setter is
                // what actually notifies dependents, even though the element
                // itself (a struct wrapping the same class references) is
                // otherwise unchanged.
                self.machines[i] = self.machines[i]
            }
    }

    /// Removes a machine: tears down its live connection and deletes its
    /// persisted pairing (Keychain/UserDefaults) so it can't silently
    /// reappear on next launch. Also updates the on-disk machines index (see
    /// below) so migration/restore-at-launch logic doesn't resurrect it.
    public func remove(_ id: RelayMachineID) {
        guard let m = machine(id) else { return }
        m.bridge.stop()
        m.client.disconnect()
        E2ERelayClient.deleteStoredPairing(machineID: id)
        machines.removeAll { $0.id == id }
        bridgeSubscriptions.removeValue(forKey: id)
        let records = machines.map(\.record)
        Task { await RelayMachineMigration.writeIndex(records) }
    }

    /// Fleet-wide "most live wins" state, mirroring FleetStore.connectionState's
    /// ordering (connected > relayPaired > connecting > failed > offline) but
    /// derived purely from each machine's bridge.isActive (a relay machine is
    /// either fully paired-and-live, or not — there's no separate SSH-connected
    /// state for a relay machine the way FleetStore's SSH slots have).
    public var aggregateConnectionState: Session.ConnectionState {
        guard !machines.isEmpty else { return .offline }
        return machines.contains { $0.bridge.isActive } ? .relayPaired : .connecting
    }
}
#endif
