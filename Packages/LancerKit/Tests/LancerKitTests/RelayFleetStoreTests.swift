#if os(iOS)
import Foundation
import Testing
@testable import AppFeature
@testable import SessionFeature
@testable import SSHTransport
@testable import SecurityKit
@testable import LancerCore

// Regression for the 2026-07-03 fix (commit c9b86283): RelayFleetStore's
// `observeBridge` must refresh `record.lastConnectedAt` on EVERY reconnect
// (every `isActive == true` edge), not just the first one at pairing time.
// Before that fix, Siri's freshness check (which reads `lastConnectedAt`
// via `RelayMachineMigration.readIndex()`) could report a genuinely-live
// machine as offline once the stale timestamp aged past its threshold, even
// though Home's own connectivity dot (reading `bridge.isActive` live) was
// correct. This test pins that behavior so it can't silently regress.
@MainActor
@Suite struct RelayFleetStoreTests {

    private func makeMachine() -> (machine: RelayFleetStore.Machine, bridge: E2ERelayBridge) {
        let relayURL = URL(string: "https://relay.example.com")!
        let client = E2ERelayClient(relayURL: relayURL, pairingCode: "111222")
        let bridge = E2ERelayBridge(relayClient: client, approvalRelay: ApprovalRelay(), machineID: client.machineID)
        let record = RelayMachineRecord(id: client.machineID, displayName: "Test Machine")
        let machine = RelayFleetStore.Machine(record: record, client: client, bridge: bridge)
        return (machine, bridge)
    }

    @Test("lastConnectedAt refreshes on every reconnect, not just the first")
    func lastConnectedAtRefreshesOnEveryReconnect() async throws {
        // Isolate this test's persisted-index writes (RelayFleetStore.add()
        // persists via RelayMachineMigration.writeIndex) from the real device
        // Keychain, matching RelayMachineMigrationTests' existing pattern.
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)

        let store = RelayFleetStore()
        let (machine, bridge) = makeMachine()
        store.add(machine)

        var observedTimestamps: [Date] = []
        for isActive in [true, false, true, false, true] {
            bridge.setActiveForTesting(isActive)
            // Combine's `.receive(on: DispatchQueue.main)` dispatches
            // asynchronously even when already on the main queue — give the
            // sink a tick to run before reading the store's state back.
            try await Task.sleep(nanoseconds: 20_000_000)
            if isActive {
                let ts = try #require(store.machine(machine.id)?.record.lastConnectedAt)
                observedTimestamps.append(ts)
            }
        }

        #expect(observedTimestamps.count == 3)
        #expect(observedTimestamps[0] < observedTimestamps[1])
        #expect(observedTimestamps[1] < observedTimestamps[2])
    }

    @Test("aggregateConnectionState reflects live bridge state, not stale record data")
    func aggregateConnectionStateTracksLiveBridge() async throws {
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)

        let store = RelayFleetStore()
        let (machine, bridge) = makeMachine()
        store.add(machine)
        #expect(store.aggregateConnectionState == .connecting)

        bridge.setActiveForTesting(true)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(store.aggregateConnectionState == .relayPaired)

        bridge.setActiveForTesting(false)
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(store.aggregateConnectionState == .connecting)
    }
}
#endif
