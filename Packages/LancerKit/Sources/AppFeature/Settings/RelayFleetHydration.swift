#if os(iOS)
import Foundation
import LancerCore
import SSHTransport
import SessionFeature

/// Launch-time hydration + shared add-machine plumbing for `RelayFleetStore`.
/// Behavior mirrors the pre-wipe `AppRoot.hydrateRelayFleetStore` /
/// `addRelayMachine` (see `git show 3789aa5f:…/AppRoot.swift`), trimmed to
/// what Settings pairing + trusted machines + New Chat vendor picker need.
@MainActor
public enum RelayFleetHydration {

    /// Migrates any legacy single-machine pairing, then restores + wires every
    /// machine in the persisted index. Call once at launch.
    public static func hydrate(into store: RelayFleetStore) async {
        _ = await RelayMachineMigration.migrateLegacyIfNeeded()
        _ = await RelayMachineMigration.invalidateAllMachinesIfIdentityRegenerated()
        let records = await RelayMachineMigration.readIndex()
        for record in records {
            let client = E2ERelayClient(relayURL: RelaySettings.url(), pairingCode: "", machineID: record.id)
            let restored = client.restoreNamespacedStoredPairing()
            addMachine(client: client, record: record, to: store, pairingUsable: restored)
            // Only a successful full restore should dial out — a partial/invalid
            // stored pairing would just spam the relay with unfixable 400s and
            // leave the UI showing the machine as forever-disconnected.
            if restored {
                client.connect()
            }
        }
    }

    /// Fetches `agent.agents.installed` for every currently-connected machine
    /// so the New Chat agent picker can filter to real host CLIs. Best-effort:
    /// failures leave `installedAgentVendors` nil (full catalog shown).
    public static func refreshInstalledAgents(into store: RelayFleetStore) async {
        for machine in store.machines where store.connectionStates.state(for: machine.id) == .connected {
            do {
                let vendors = try await machine.bridge.relayInstalledAgents()
                store.setInstalledAgentVendors(vendors, for: machine.id)
            } catch {
                continue
            }
        }
    }

    /// Builds an `E2ERelayBridge` over `client`, adds the machine to `store`,
    /// and registers the bridge with `ApprovalRelay`. Used by both launch
    /// hydration and the live-pairing sheet's `onPaired` callback. Returns
    /// `false` (and tears down `client`) when the store is at capacity — the
    /// caller must not treat the machine as live in that case.
    @discardableResult
    public static func addMachine(
        client: E2ERelayClient,
        record: RelayMachineRecord,
        to store: RelayFleetStore,
        pairingUsable: Bool = true
    ) -> Bool {
        let bridge = E2ERelayBridge(relayClient: client, approvalRelay: ApprovalRelay.shared, machineID: record.id)
        let machine = RelayFleetStore.Machine(record: record, client: client, bridge: bridge)
        guard store.add(machine, pairingUsable: pairingUsable) else {
            client.disconnect()
            return false
        }
        bridge.start()
        ApprovalRelay.shared.relayBridges[record.id] = bridge
        return true
    }
}
#endif
