#if os(iOS)
import Foundation
import Combine
import Observation
import LancerCore
import SSHTransport

/// The single authoritative source of per-relay-machine liveness.
///
/// Before this existed, at least four surfaces (RelayFleetStore, Siri's
/// CommandGateway, AppRoot's observed-session import, and assorted views)
/// each derived their own connectivity answer from `E2ERelayBridge.isActive`
/// — a lossy Bool — with their own polling workarounds for the cold-launch
/// reconnect race. Each derivation had its own edge cases and they could
/// disagree with each other (found live repeatedly, 2026-07-02 → 07-04).
/// This store is now the sole writer of that state; every other surface
/// reads it and none re-derives liveness from a bridge or client directly.
///
/// The state is an enum, not a Bool, because collapsing "actively retrying"
/// into "known bad, needs a human" is exactly what caused several of those
/// bugs: a machine mid-reconnect and a machine whose stored pairing is
/// unusable both read `isActive == false`, but only the former is worth
/// waiting on and only the latter needs a re-pair.
///
/// Combine → Observation bridging: `E2ERelayClient`'s states are `@Published`
/// (Combine), but SwiftUI consumers here are `@Observable`-tracked. The store
/// subscribes once per machine and republishes into its own `@Observable`
/// `states` dictionary — the same mechanism RelayFleetStore.observeBridge used
/// for the c9b86283 staleness fix, centralized. It subscribes to the client's
/// `$pairingState`/`$connectionState` pair rather than the bridge's derived
/// `$isActive` because the Bool cannot express the enum; `bridge.isActive` is
/// itself just `pairingState == .paired`, so nothing is lost and the store
/// updates strictly before the bridge's own async `$isActive` mirror does.
@MainActor @Observable
public final class ConnectionStateStore {

    /// The app-wide instance. AppFeature's RelayFleetStore and Siri's
    /// CommandGateway both default to this so they can never disagree;
    /// tests inject fresh instances instead.
    public static let shared = ConnectionStateStore()

    public enum MachineState: Equatable, Sendable, CustomStringConvertible {
        /// Paired and live end-to-end: RPCs will go through right now.
        case connected
        /// Not currently usable, but the client is actively dialing/backing
        /// off and can become `.connected` with no human involved. Callers
        /// with a small latency budget (Siri, observed-session import) should
        /// wait briefly on this state instead of failing immediately.
        case reconnecting
        /// The stored pairing is missing, invalid, or rejected — retrying can
        /// never fix this; the machine needs a human re-pair. (The 2026-07-03
        /// empty-code/missing-Keychain-key bug lives here.)
        case pairingInvalid
        /// The phone reached the relay but the daemon peer isn't there —
        /// pairing state is fine, the host itself is down or its daemon
        /// stopped. Could recover without phone-side action.
        case hostOffline

        public var description: String {
            switch self {
            case .connected: return "connected"
            case .reconnecting: return "reconnecting"
            case .pairingInvalid: return "pairing invalid"
            case .hostOffline: return "host offline"
            }
        }
    }

    public private(set) var states: [RelayMachineID: MachineState] = [:]
    /// Refreshed on EVERY transition into `.connected`, not just initial
    /// pairing — the staleness of this timestamp was itself a bug (PR #18).
    public private(set) var lastConnectedAt: [RelayMachineID: Date] = [:]

    @ObservationIgnored private var subscriptions: [RelayMachineID: AnyCancellable] = [:]
    @ObservationIgnored private var pairingUsable: [RelayMachineID: Bool] = [:]
    @ObservationIgnored private var observers: [(RelayMachineID, MachineState) -> Void] = []

    public init() {}

    /// Begin tracking a machine's liveness off its relay client. `pairingUsable`
    /// is false when hydration found the persisted pairing incomplete/invalid
    /// (the machine stays listed but can never connect without a re-pair).
    public func track(machineID: RelayMachineID, client: E2ERelayClient, pairingUsable usable: Bool) {
        pairingUsable[machineID] = usable
        // combineLatest delivers the latest value of BOTH publishers on every
        // change of either, so state is derived purely from delivered values —
        // never by reading client properties mid-`willSet`, where the other
        // property may not be updated yet.
        subscriptions[machineID] = client.$pairingState
            .combineLatest(client.$connectionState)
            .sink { [weak self] pairing, connection in
                self?.apply(machineID: machineID, pairing: pairing, connection: connection)
            }
    }

    public func untrack(machineID: RelayMachineID) {
        subscriptions.removeValue(forKey: machineID)
        pairingUsable.removeValue(forKey: machineID)
        states.removeValue(forKey: machineID)
        lastConnectedAt.removeValue(forKey: machineID)
    }

    /// Edge-triggered transition callbacks (persistence, push registration,
    /// aggregate mirrors). Fired only on actual state changes.
    public func addObserver(_ observer: @escaping (RelayMachineID, MachineState) -> Void) {
        observers.append(observer)
    }

    public func state(for machineID: RelayMachineID) -> MachineState? {
        states[machineID]
    }

    public func isConnected(_ machineID: RelayMachineID) -> Bool {
        states[machineID] == .connected
    }

    public var anyConnected: Bool {
        states.values.contains(.connected)
    }

    public var firstConnectedMachineID: RelayMachineID? {
        states.first(where: { $0.value == .connected })?.key
    }

    /// Bounded wait for any machine to become `.connected`, tolerating the
    /// cold-launch reconnect race that every caller used to hand-roll a poll
    /// for (`AppRoot.activeRelayBridge`, Siri's `pollBridgeActive`). Waits only
    /// while some machine could still connect without a human (`.reconnecting`
    /// or `.hostOffline` — the latter covers the connected-to-relay,
    /// waiting-for-daemon-peer window during launch); a store that is empty or
    /// all-`.pairingInvalid` fails immediately instead of burning the timeout.
    public func waitForAnyConnected(timeout: TimeInterval = 2.0) async -> RelayMachineID? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let id = firstConnectedMachineID { return id }
            let couldRecover = states.values.contains { $0 == .reconnecting || $0 == .hostOffline }
            guard couldRecover, Date() < deadline else { return nil }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Per-machine variant of `waitForAnyConnected`, same semantics.
    public func waitForConnected(machineID: RelayMachineID, timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            switch states[machineID] {
            case .connected: return true
            case .reconnecting, .hostOffline:
                guard Date() < deadline else { return false }
                try? await Task.sleep(nanoseconds: 100_000_000)
            case .pairingInvalid, nil:
                return false
            }
        }
    }

    /// The one place machine liveness is derived. Pure so it can be pinned by
    /// unit tests without a live relay.
    static func derive(
        pairingUsable: Bool,
        pairing: E2ERelayClient.PairingState,
        connection: E2ERelayClient.ConnectionState
    ) -> MachineState {
        if case .pairingFailed = pairing { return .pairingInvalid }
        // A code the relay rejected as expired can never succeed again
        // without a human re-pairing — same bucket as pairingFailed, not
        // "actively retrying" (the connection-state switch below would say
        // .reconnecting/.hostOffline, which is wrong: nothing here recovers
        // on its own).
        if pairing == .codeExpired { return .pairingInvalid }
        guard pairingUsable else { return .pairingInvalid }
        if pairing == .paired { return .connected }
        switch connection {
        case .connected:
            // On the relay but the daemon peer hasn't joined the code.
            return .hostOffline
        case .connecting, .reconnecting, .disconnected:
            // `.disconnected` counts as retrying: E2ERelayClient always
            // schedules a reconnect after a drop (it sits `.disconnected`
            // during the backoff delay), and the only paths that park a
            // client in `.disconnected` for good — explicit `disconnect()`
            // on machine removal, or a never-dialed unusable pairing — are
            // handled by `untrack` and `pairingUsable` respectively.
            return .reconnecting
        }
    }

    private func apply(
        machineID: RelayMachineID,
        pairing: E2ERelayClient.PairingState,
        connection: E2ERelayClient.ConnectionState
    ) {
        let next = Self.derive(
            pairingUsable: pairingUsable[machineID] ?? true,
            pairing: pairing,
            connection: connection
        )
        guard states[machineID] != next else { return }
        states[machineID] = next
        if next == .connected {
            lastConnectedAt[machineID] = Date()
        }
        for observer in observers {
            observer(machineID, next)
        }
    }
}
#endif
