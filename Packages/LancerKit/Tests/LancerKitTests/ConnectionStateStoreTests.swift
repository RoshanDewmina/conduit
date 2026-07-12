#if os(iOS)
import Foundation
import Testing
@testable import SessionFeature
@testable import SSHTransport
@testable import LancerCore

/// Pins `ConnectionStateStore` — the single authoritative source of per-relay-
/// machine liveness — so no consumer ever needs to re-derive connectivity from
/// `E2ERelayBridge.isActive` again. The derivation matrix is the load-bearing
/// part: collapsing "actively retrying" into "known bad, needs a human" is the
/// exact confusion behind the 2026-07-02→07-04 connectivity bug streak.
@MainActor
@Suite struct ConnectionStateStoreTests {

    private func makeClient() -> E2ERelayClient {
        E2ERelayClient(relayURL: URL(string: "https://relay.example.com")!, pairingCode: "111222")
    }

    @Test("derivation matrix distinguishes retrying from needs-a-human")
    func deriveMatrix() {
        typealias S = ConnectionStateStore.MachineState
        // Paired end-to-end → connected, regardless of how it got there.
        #expect(ConnectionStateStore.derive(pairingUsable: true, pairing: .paired, connection: .connected) == S.connected)
        // A rejected pairing needs a human even while the socket keeps trying.
        #expect(ConnectionStateStore.derive(pairingUsable: true, pairing: .pairingFailed("relay error"), connection: .connected) == S.pairingInvalid)
        // An expired-unconfirmed code (REL-1 C) needs a human re-pair too —
        // must NOT fall through to the connection-based .reconnecting/.hostOffline
        // branch, since nothing about it recovers on its own.
        #expect(ConnectionStateStore.derive(pairingUsable: true, pairing: .codeExpired, connection: .connected) == S.pairingInvalid)
        #expect(ConnectionStateStore.derive(pairingUsable: true, pairing: .codeExpired, connection: .disconnected) == S.pairingInvalid)
        // An unusable stored pairing (2026-07-03 missing-Keychain-key bug) is
        // pairingInvalid no matter what the socket reports.
        #expect(ConnectionStateStore.derive(pairingUsable: false, pairing: .unpaired, connection: .disconnected) == S.pairingInvalid)
        // On the relay but the daemon peer hasn't joined → the host is offline,
        // not the pairing.
        #expect(ConnectionStateStore.derive(pairingUsable: true, pairing: .waitingForPeer, connection: .connected) == S.hostOffline)
        // Dialing / backing off / momentarily dropped → actively retrying.
        #expect(ConnectionStateStore.derive(pairingUsable: true, pairing: .unpaired, connection: .connecting) == S.reconnecting)
        #expect(ConnectionStateStore.derive(pairingUsable: true, pairing: .unpaired, connection: .reconnecting(attempt: 2)) == S.reconnecting)
        #expect(ConnectionStateStore.derive(pairingUsable: true, pairing: .unpaired, connection: .disconnected) == S.reconnecting)
    }

    @Test("tracked machine's state follows the client's published states")
    func trackFollowsClient() {
        let store = ConnectionStateStore()
        let client = makeClient()
        store.track(machineID: client.machineID, client: client, pairingUsable: true)

        #expect(store.state(for: client.machineID) == .reconnecting)
        #expect(!store.anyConnected)

        client.setStateForTesting(pairing: .paired, connection: .connected)
        #expect(store.state(for: client.machineID) == .connected)
        #expect(store.isConnected(client.machineID))
        #expect(store.firstConnectedMachineID == client.machineID)

        client.setStateForTesting(pairing: .waitingForPeer, connection: .connected)
        #expect(store.state(for: client.machineID) == .hostOffline)

        store.untrack(machineID: client.machineID)
        #expect(store.state(for: client.machineID) == nil)
    }

    @Test("lastConnectedAt refreshes on every transition into connected")
    func lastConnectedAtRefreshes() async throws {
        let store = ConnectionStateStore()
        let client = makeClient()
        store.track(machineID: client.machineID, client: client, pairingUsable: true)

        client.setStateForTesting(pairing: .paired, connection: .connected)
        let first = try #require(store.lastConnectedAt[client.machineID])

        client.setStateForTesting(pairing: .unpaired, connection: .disconnected)
        try await Task.sleep(nanoseconds: 20_000_000)
        client.setStateForTesting(pairing: .paired, connection: .connected)
        let second = try #require(store.lastConnectedAt[client.machineID])

        #expect(first < second)
    }

    @Test("observers fire only on real transitions")
    func observersFireOnTransitions() {
        let store = ConnectionStateStore()
        let client = makeClient()
        var transitions: [ConnectionStateStore.MachineState] = []
        store.addObserver { _, state in transitions.append(state) }
        store.track(machineID: client.machineID, client: client, pairingUsable: true)

        client.setStateForTesting(pairing: .paired, connection: .connected)
        // Same effective state again — must not re-fire: @Published re-emits on
        // every set, so this exercises the store's `old != new` dedup.
        client.setStateForTesting(pairing: .paired, connection: .connected)
        client.setStateForTesting(pairing: .unpaired, connection: .reconnecting(attempt: 1))

        // The two client states are separate publishers set in sequence, so a
        // combined transition passes through one momentary intermediate — here
        // `.hostOffline` from (unpaired, connected) while pairing catches up.
        // That intermediate is real (production writes the same sequence) and
        // harmless; what this test pins is that duplicates never re-fire.
        #expect(transitions == [.reconnecting, .hostOffline, .connected, .reconnecting])
    }

    @Test("waitForAnyConnected bails immediately when every pairing is known-bad")
    func waitFailsFastOnPairingInvalid() async {
        let store = ConnectionStateStore()
        let client = makeClient()
        store.track(machineID: client.machineID, client: client, pairingUsable: false)

        let start = Date()
        let result = await store.waitForAnyConnected(timeout: 5.0)
        #expect(result == nil)
        // Known-bad must not burn the timeout — the whole point of the enum.
        #expect(Date().timeIntervalSince(start) < 1.0)
    }

    @Test("waitForAnyConnected returns once a mid-reconnect machine pairs")
    func waitToleratesReconnectRace() async throws {
        let store = ConnectionStateStore()
        let client = makeClient()
        store.track(machineID: client.machineID, client: client, pairingUsable: true)
        #expect(store.state(for: client.machineID) == .reconnecting)

        // Root cause of the 2026-07-08 CI flake (run 28977613741): this test
        // used to race two wall-clock durations against each other — a fixed
        // `Task.sleep(200ms)` here vs. `waitForAnyConnected`'s own 3.0s
        // deadline — on the SAME cooperative-thread-pool clock. Both are
        // computed from roughly the same start time, so a 15x margin sounds
        // safe but isn't: under a sufficiently overloaded/throttled runner,
        // `Task.sleep(200ms)` itself can stall for several real seconds
        // (thread-pool contention, CPU throttling), eating past the waiter's
        // 3.0s budget before this test ever calls `setStateForTesting` —
        // timing the waiter out even though the state transition it's
        // waiting for hasn't happened yet. Two independent fixes:
        //
        // 1. `Task.yield()` instead of a timed sleep to hand control to the
        //    waiter task. This only depends on the scheduler actually
        //    running ready work, not on a real-time duration, so it can't
        //    itself become the thing that blows the budget. (It's also not
        //    load-bearing for correctness: `waitForAnyConnected` checks
        //    `firstConnectedMachineID` before anything else, so even if the
        //    waiter's first poll happens strictly after the mutation below,
        //    it still returns immediately — the yields just make the
        //    "mid-reconnect" race the test name describes actually happen
        //    most of the time instead of degenerating to "already connected
        //    when checked".)
        // 2. A far more generous timeout (15s vs. the old 3.0s). This is
        //    free on the fast path — the loop returns the instant the
        //    machine connects, real test runtime is unaffected — and only
        //    matters when the runner is so overloaded that scheduling stalls
        //    for seconds; that's exactly the regime this flake came from.
        let waiter = Task { await store.waitForAnyConnected(timeout: 15.0) }
        for _ in 0..<10 {
            await Task.yield()
        }
        client.setStateForTesting(pairing: .paired, connection: .connected)

        let result = await waiter.value
        #expect(result == client.machineID)
    }
}
#endif
