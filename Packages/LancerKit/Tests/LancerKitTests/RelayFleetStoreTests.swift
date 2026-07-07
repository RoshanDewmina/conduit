#if os(iOS)
import Foundation
import Testing
@testable import AppFeature
@testable import SessionFeature
@testable import SSHTransport
@testable import SecurityKit
@testable import LancerCore

// Regression for the 2026-07-03 fix (commit c9b86283): `lastConnectedAt` must
// refresh on EVERY reconnect (every transition into `.connected`), not just
// the first one at pairing time. Before that fix, Siri's freshness check
// (which reads `lastConnectedAt` via `RelayMachineMigration.readIndex()`)
// could report a genuinely-live machine as offline once the stale timestamp
// aged past its threshold, even though Home's own connectivity dot was
// correct. Now pinned against `ConnectionStateStore` (the single authoritative
// liveness source), driven through `E2ERelayClient.setStateForTesting` — the
// same real-object-with-a-seam pattern the old `setActiveForTesting` used.
@MainActor
@Suite struct RelayFleetStoreTests {

    private func makeMachine() -> (machine: RelayFleetStore.Machine, client: E2ERelayClient) {
        let relayURL = URL(string: "https://relay.example.com")!
        let client = E2ERelayClient(relayURL: relayURL, pairingCode: "111222")
        let bridge = E2ERelayBridge(relayClient: client, approvalRelay: ApprovalRelay(), machineID: client.machineID)
        let record = RelayMachineRecord(id: client.machineID, displayName: "Test Machine")
        let machine = RelayFleetStore.Machine(record: record, client: client, bridge: bridge)
        return (machine, client)
    }

    @Test("lastConnectedAt refreshes on every reconnect, not just the first")
    func lastConnectedAtRefreshesOnEveryReconnect() async throws {
        // Isolate this test's persisted-index writes (RelayFleetStore.add()
        // persists via RelayMachineMigration.writeIndex) from the real device
        // Keychain, matching RelayMachineMigrationTests' existing pattern.
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)

        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        let (machine, client) = makeMachine()
        store.add(machine)

        var observedTimestamps: [Date] = []
        for isPaired in [true, false, true, false, true] {
            client.setStateForTesting(
                pairing: isPaired ? .paired : .unpaired,
                connection: isPaired ? .connected : .disconnected
            )
            // The store applies synchronously, but consecutive transitions in a
            // tight loop can land on the same Date tick — space them out so the
            // strictly-increasing assertion below is meaningful.
            try await Task.sleep(nanoseconds: 20_000_000)
            if isPaired {
                let ts = try #require(store.machine(machine.id)?.record.lastConnectedAt)
                observedTimestamps.append(ts)
            }
        }

        #expect(observedTimestamps.count == 3)
        #expect(observedTimestamps[0] < observedTimestamps[1])
        #expect(observedTimestamps[1] < observedTimestamps[2])
    }

    @Test("aggregateConnectionState reflects live connection state, not stale record data")
    func aggregateConnectionStateTracksLiveState() async throws {
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)

        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        let (machine, client) = makeMachine()
        store.add(machine)
        #expect(store.aggregateConnectionState == .connecting)

        client.setStateForTesting(pairing: .paired, connection: .connected)
        #expect(store.aggregateConnectionState == .relayPaired)
        #expect(store.isConnected(machine.id))

        client.setStateForTesting(pairing: .unpaired, connection: .disconnected)
        #expect(store.aggregateConnectionState == .connecting)
        #expect(!store.isConnected(machine.id))
    }

    @Test("a machine whose stored pairing failed to restore reads pairingInvalid, and remove() untracks it")
    func unrestorableMachineReadsPairingInvalid() async throws {
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)

        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        let (machine, _) = makeMachine()
        store.add(machine, pairingUsable: false)

        #expect(store.connectionState(for: machine.id) == .pairingInvalid)
        #expect(store.firstConnectedMachine == nil)

        store.remove(machine.id)
        #expect(store.connectionState(for: machine.id) == nil)
    }

    // Regression for the 2026-07-04 incident class: an add() past the fleet
    // cap must report failure so the caller tears the live client down,
    // instead of the machine continuing to work in-memory (bridge started,
    // ApprovalRelay-registered) while silently absent from the hydration
    // index — which presented as "my machine unpaired itself after relaunch".
    @Test("add() past the fleet cap returns false and tracks nothing")
    func addPastCapReportsFailure() async throws {
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)

        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        for _ in 0..<relayFleetMaxMachines {
            #expect(store.add(makeMachine().machine))
        }
        let (overflow, _) = makeMachine()
        #expect(!store.add(overflow))
        #expect(store.machine(overflow.id) == nil)
        #expect(store.connectionState(for: overflow.id) == nil)
    }

    @Test("invalidMachines returns only pairingInvalid machines")
    func invalidMachinesFiltersCorrectly() async throws {
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)

        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        let (valid, _) = makeMachine()
        let (invalid, _) = makeMachine()
        store.add(valid, pairingUsable: true)
        store.add(invalid, pairingUsable: false)

        #expect(store.invalidMachines.count == 1)
        #expect(store.invalidMachines.first?.id == invalid.id)
    }

    @Test("removeAllInvalid() removes only pairingInvalid machines and leaves valid ones")
    func removeAllInvalidLeavesValidMachines() async throws {
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)

        let store = RelayFleetStore(connectionStates: ConnectionStateStore())
        let (valid, _) = makeMachine()
        let (invalid1, _) = makeMachine()
        let (invalid2, _) = makeMachine()
        store.add(valid, pairingUsable: true)
        store.add(invalid1, pairingUsable: false)
        store.add(invalid2, pairingUsable: false)

        #expect(store.machines.count == 3)
        store.removeAllInvalid()

        #expect(store.machines.count == 1)
        #expect(store.machines.first?.id == valid.id)
        #expect(store.invalidMachines.isEmpty)
        #expect(store.connectionState(for: invalid1.id) == nil)
        #expect(store.connectionState(for: invalid2.id) == nil)
    }
}
#endif
