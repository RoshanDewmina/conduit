#if os(iOS)
import Foundation
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

    /// The single authoritative liveness source for every machine in this
    /// fleet. This store no longer derives connectivity itself — it registers
    /// machines with `connectionStates` and consumes the result, same as every
    /// other surface (Home, Fleet, Settings, Siri, observed-session import).
    /// Defaults to the app-wide shared instance so those surfaces can never
    /// disagree; tests inject a fresh one.
    public let connectionStates: ConnectionStateStore

    public init(connectionStates: ConnectionStateStore = .shared) {
        self.connectionStates = connectionStates
        // Two responsibilities on every real state transition:
        // 1. Re-assign through the @Observable-synthesized setter so SwiftUI
        //    consumers reading `machines` re-render (the element is a struct
        //    wrapping the same class references, so the assignment is what
        //    notifies dependents — the c9b86283 staleness fix, now driven by
        //    the one authoritative store instead of a per-store subscription).
        // 2. Persist `lastConnectedAt` on EVERY transition into `.connected`,
        //    not just initial pairing: the persisted index is read back by
        //    launch hydration and any consumer of `RelayMachineMigration
        //    .readIndex()`, and letting it go stale was itself a bug (PR #18).
        connectionStates.addObserver { [weak self] machineID, state in
            guard let self, let i = self.machines.firstIndex(where: { $0.id == machineID }) else { return }
            self.machines[i] = self.machines[i]
            if state == .connected {
                self.machines[i].record.lastConnectedAt = self.connectionStates.lastConnectedAt[machineID] ?? .now
                let records = self.machines.map(\.record)
                Task { await RelayMachineMigration.writeIndex(records) }
            }
        }
    }

    /// Machines whose persisted pairing permanently failed to restore (hydrated
    /// with `pairingUsable: false`, or whose live pairing attempt hard-failed)
    /// can never become live without a fresh re-pair — counting them against
    /// the cap means a device that's cycled through a few uninstall/re-pair
    /// generations (Keychain survives uninstall even though the UserDefaults
    /// code/URL don't) permanently fills the fleet with dead entries and
    /// silently rejects every subsequent real pairing at `add()` below.
    public var isFull: Bool { isRelayFleetFull(count: usableMachineCount) }

    private var usableMachineCount: Int {
        machines.filter { connectionStates.state(for: $0.id) != .pairingInvalid }.count
    }

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

    /// Adds a machine and registers it with the connection-state store.
    /// `pairingUsable: false` marks a machine whose persisted pairing failed
    /// to restore (it stays listed, permanently `.pairingInvalid`, until a
    /// re-pair). Returns false (adding nothing) at the cap — callers MUST
    /// check the result and tear down the machine's live client/bridge
    /// instead of proceeding: a dropped-but-started machine keeps working
    /// in-memory until the next relaunch and then silently vanishes (it was
    /// never in the hydration index), which presents as "my machine unpaired
    /// itself overnight".
    @discardableResult
    public func add(_ machine: Machine, pairingUsable: Bool = true) -> Bool {
        guard !isFull else { return false }
        machines.append(machine)
        connectionStates.track(machineID: machine.id, client: machine.client, pairingUsable: pairingUsable)
        let records = machines.map(\.record)
        Task { await RelayMachineMigration.writeIndex(records) }
        return true
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
        connectionStates.untrack(machineID: id)
        let records = machines.map(\.record)
        Task { await RelayMachineMigration.writeIndex(records) }
    }

    /// Machines that are permanently `.pairingInvalid` — a persisted pairing
    /// that failed to restore (e.g. Keychain survived an app reinstall but
    /// UserDefaults didn't) or a live pairing attempt that hard-failed. None
    /// of these can ever reconnect without a fresh re-pair, so they only ever
    /// leave the list via `remove`/`removeAllInvalid` — they don't self-heal.
    public var invalidMachines: [Machine] {
        machines.filter { connectionStates.state(for: $0.id) == .pairingInvalid }
    }

    /// Bulk-removes every currently-`.pairingInvalid` machine. Exposed as a
    /// single "Clear invalid pairings" Settings action rather than requiring
    /// the user to tap "Unpair" on each dead entry individually — a device
    /// that's been reinstalled a few times (Keychain persists across
    /// `simctl uninstall`/app deletion even though UserDefaults doesn't)
    /// otherwise accumulates one unrecoverable ghost per reinstall with no
    /// bulk way to clean them out.
    public func removeAllInvalid() {
        for machine in invalidMachines {
            remove(machine.id)
        }
    }

    // MARK: - Liveness reads (all delegated to ConnectionStateStore)

    public func connectionState(for id: RelayMachineID) -> ConnectionStateStore.MachineState? {
        connectionStates.state(for: id)
    }

    public func isConnected(_ id: RelayMachineID) -> Bool {
        connectionStates.isConnected(id)
    }

    /// The first machine whose relay is live end-to-end — the shared fallback
    /// for callers with no per-machine context (Siri-style "any machine",
    /// composer autocomplete, observed-session transport selection).
    public var firstConnectedMachine: Machine? {
        guard let id = connectionStates.firstConnectedMachineID else { return nil }
        return machine(id)
    }

    /// Fleet-wide "most live wins" state, mirroring FleetStore.connectionState's
    /// ordering (connected > relayPaired > connecting > failed > offline) but
    /// derived from the authoritative per-machine connection states.
    public var aggregateConnectionState: Session.ConnectionState {
        guard !machines.isEmpty else { return .offline }
        return connectionStates.anyConnected ? .relayPaired : .connecting
    }
}
#endif
