#if os(iOS)
import Foundation
import LancerCore
import SSHTransport
import SessionFeature

/// Launch-time hydration + shared add-machine plumbing for `RelayFleetStore`.
/// Behavior mirrors the pre-wipe `AppRoot.hydrateRelayFleetStore` /
/// `addRelayMachine` (see `git show 3789aa5f:…/AppRoot.swift`), trimmed to
/// exactly what M2 (Settings pairing + trusted machines) needs — no push-token
/// registration, no Live Activity tokens, no installed-agent-vendor fetch.
@MainActor
public enum RelayFleetHydration {

    /// Migrates any legacy single-machine pairing, then restores + wires every
    /// machine in the persisted index. Call once at launch.
    public static func hydrate(into store: RelayFleetStore) async {
        _ = await RelayMachineMigration.migrateLegacyIfNeeded()
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
