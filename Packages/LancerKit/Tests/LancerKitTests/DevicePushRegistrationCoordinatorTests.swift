#if os(iOS)
import Foundation
import Testing
@testable import AppFeature
@testable import SessionFeature
@testable import SSHTransport
@testable import SecurityKit
@testable import NotificationsKit
@testable import LancerCore

/// `DevicePushRegistrationCoordinator` is the missing glue between a captured
/// APNs/Live-Activity push token and `E2ERelayBridge.registerDevice` /
/// `.registerActivityToken` — both existed with zero call sites before this
/// (live-reproduced 2026-07-18: a real approval escalation while the phone
/// was locked produced no push in 4+ minutes). These tests pin the two
/// orderings the coordinator must handle (token-then-pairing and
/// pairing-then-token), reconnect re-registration, and the no-op cases.
///
/// Uses the same real-object-with-a-seam pattern as `E2ERelayBridgeFirstSendTests`
/// / `RelayFleetStoreTests`: a real `E2ERelayClient` with `bypassSendForTesting`
/// so no network I/O happens, driven through `setStateForTesting`.
///
/// `.serialized`: every test reads/writes `Notifications.shared`'s
/// `pendingAPNSTokenHex` (a true process-wide actor singleton — it cannot be
/// constructed fresh per test). Swift Testing parallelizes tests within a
/// suite by default, and two tests racing to set that shared value would make
/// each other flaky; run them one at a time instead.
@MainActor
@Suite(.serialized) struct DevicePushRegistrationCoordinatorTests {

    private func makeMachine(displayName: String = "Test Machine") -> (machine: RelayFleetStore.Machine, client: E2ERelayClient, bridge: E2ERelayBridge) {
        let relayURL = URL(string: "https://relay.example.com")!
        let client = E2ERelayClient(relayURL: relayURL, pairingCode: "111222")
        client.bypassSendForTesting = true
        let bridge = E2ERelayBridge(relayClient: client, approvalRelay: ApprovalRelay(), machineID: client.machineID)
        bridge.start()
        let record = RelayMachineRecord(id: client.machineID, displayName: displayName)
        let machine = RelayFleetStore.Machine(record: record, client: client, bridge: bridge)
        return (machine, client, bridge)
    }

    private func connect(_ client: E2ERelayClient, _ bridge: E2ERelayBridge) async {
        client.setStateForTesting(pairing: .paired, connection: .connected)
        for _ in 0..<40 where !bridge.isActive {
            await Task.yield()
        }
        #expect(bridge.isActive)
    }

    private func disconnect(_ client: E2ERelayClient, _ bridge: E2ERelayBridge) async {
        client.setStateForTesting(pairing: .unpaired, connection: .disconnected)
        for _ in 0..<40 where bridge.isActive {
            await Task.yield()
        }
        #expect(!bridge.isActive)
    }

    private func waitUntil(timeout: TimeInterval = 2.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
        }
    }

    private func freshStore() -> RelayFleetStore {
        RelayMachineMigration.indexKeychain = Keychain(service: "dev.lancer.relay.test.\(UUID().uuidString)", inMemory: true)
        return RelayFleetStore(connectionStates: ConnectionStateStore())
    }

    @Test("no-op when no APNs token has ever arrived")
    func noOpWithoutToken() async throws {
        await Notifications.shared.setPendingAPNSToken("")
        let store = freshStore()
        let coordinator = DevicePushRegistrationCoordinator(fleetStore: store)
        coordinator.start()

        let (machine, client, bridge) = makeMachine()
        store.add(machine)
        await connect(client, bridge)

        // Give the coordinator's observer a fair chance to (wrongly) fire.
        try await Task.sleep(for: .milliseconds(50))
        #expect(client.bypassedSendCountForTesting == 0)
    }

    @Test("no-op when a token exists but no machine is connected yet, then registers once one connects")
    func noOpWithoutActiveMachine() async throws {
        await Notifications.shared.setPendingAPNSToken("")
        let store = freshStore()
        let coordinator = DevicePushRegistrationCoordinator(fleetStore: store)
        coordinator.start()

        NotificationCenter.default.post(
            name: .lancerAPNSTokenReceived, object: nil, userInfo: ["token": "no-machine-token"]
        )
        await waitUntil { coordinator.apnsTokenHex == "no-machine-token" }
        #expect(coordinator.apnsTokenHex == "no-machine-token")
        #expect(store.machines.isEmpty, "nothing to send to — no machine has ever been added")

        // Only once a machine actually connects does the cached token get used.
        let (machine, client, bridge) = makeMachine()
        var sentTypes: [String] = []
        client.onBypassSendForTesting = { sentTypes.append($0) }
        store.add(machine)
        await connect(client, bridge)

        await waitUntil { sentTypes.contains("deviceRegister") }
        #expect(sentTypes.contains("deviceRegister"))
    }

    @Test("token known before pairing: registers once the machine connects")
    func tokenBeforePairing() async throws {
        await Notifications.shared.setPendingAPNSToken("token-before-pairing")
        let store = freshStore()
        let coordinator = DevicePushRegistrationCoordinator(fleetStore: store)
        coordinator.start()
        // Coordinator hydrates from Notifications.shared at start() — give its
        // internal Task a turn to read it before pairing.
        await waitUntil { coordinator.apnsTokenHex == "token-before-pairing" }
        #expect(coordinator.apnsTokenHex == "token-before-pairing")

        let (machine, client, bridge) = makeMachine()
        var sentTypes: [String] = []
        client.onBypassSendForTesting = { sentTypes.append($0) }
        store.add(machine)
        await connect(client, bridge)

        await waitUntil { sentTypes.contains("deviceRegister") }
        #expect(sentTypes.contains("deviceRegister"))
    }

    @Test("pairing before token: registers once the token notification arrives")
    func pairingBeforeToken() async throws {
        await Notifications.shared.setPendingAPNSToken("")
        let store = freshStore()
        let coordinator = DevicePushRegistrationCoordinator(fleetStore: store)
        coordinator.start()

        let (machine, client, bridge) = makeMachine()
        var sentTypes: [String] = []
        client.onBypassSendForTesting = { sentTypes.append($0) }
        store.add(machine)
        await connect(client, bridge)

        try await Task.sleep(for: .milliseconds(50))
        #expect(!sentTypes.contains("deviceRegister"), "must not register before a token exists")

        NotificationCenter.default.post(
            name: .lancerAPNSTokenReceived, object: nil, userInfo: ["token": "token-after-pairing"]
        )

        await waitUntil { sentTypes.contains("deviceRegister") }
        #expect(sentTypes.contains("deviceRegister"))
        #expect(coordinator.apnsTokenHex == "token-after-pairing")
    }

    @Test("re-registers the known token on every reconnect")
    func reregistersOnReconnect() async throws {
        await Notifications.shared.setPendingAPNSToken("reconnect-token")
        let store = freshStore()
        let coordinator = DevicePushRegistrationCoordinator(fleetStore: store)
        coordinator.start()
        await waitUntil { coordinator.apnsTokenHex == "reconnect-token" }

        let (machine, client, bridge) = makeMachine()
        var registerCount = 0
        client.onBypassSendForTesting = { if $0 == "deviceRegister" { registerCount += 1 } }
        store.add(machine)

        await connect(client, bridge)
        await waitUntil { registerCount >= 1 }
        #expect(registerCount == 1)

        await disconnect(client, bridge)
        await connect(client, bridge)
        await waitUntil { registerCount >= 2 }
        #expect(registerCount == 2, "a reconnect must re-send, not rely on the daemon having kept the old token")
    }

    @Test("Live Activity token notification registers on the connected machine")
    func liveActivityTokenRegisters() async throws {
        await Notifications.shared.setPendingAPNSToken("")
        let store = freshStore()
        let coordinator = DevicePushRegistrationCoordinator(fleetStore: store)
        coordinator.start()

        let (machine, client, bridge) = makeMachine()
        var sentTypes: [String] = []
        client.onBypassSendForTesting = { sentTypes.append($0) }
        store.add(machine)
        await connect(client, bridge)

        NotificationCenter.default.post(
            name: .lancerLiveActivityTokenReady,
            object: nil,
            userInfo: ["sessionID": "device-session-1", "activityToken": "activity-tok-1", "isPushToStart": false]
        )

        await waitUntil { sentTypes.contains("activityTokenRegister") }
        #expect(sentTypes.contains("activityTokenRegister"))
    }

    @Test("a second start() call is a no-op (idempotent)")
    func secondStartIsNoOp() async throws {
        await Notifications.shared.setPendingAPNSToken("")
        let store = freshStore()
        let coordinator = DevicePushRegistrationCoordinator(fleetStore: store)
        coordinator.start()
        coordinator.start()
        coordinator.start()
        // No crash, no duplicate observer registration blowing up — a real
        // machine still registers exactly once per connect, not 3x.
        let (machine, client, bridge) = makeMachine()
        var registerCount = 0
        client.onBypassSendForTesting = { if $0 == "deviceRegister" { registerCount += 1 } }
        NotificationCenter.default.post(
            name: .lancerAPNSTokenReceived, object: nil, userInfo: ["token": "idempotent-token"]
        )
        store.add(machine)
        await connect(client, bridge)
        await waitUntil { registerCount >= 1 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(registerCount == 1)
    }
}
#endif
