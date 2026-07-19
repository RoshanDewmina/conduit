#if os(iOS)
import Foundation
import LancerCore
import NotificationsKit
import os
import SessionFeature

/// Closes the gap where an APNs device token
/// (`LancerApp.AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`)
/// or a Live Activity push token (`LancerLiveActivityManager.tokenRegistration`)
/// is captured but never forwarded to any paired daemon. `E2ERelayBridge
/// .registerDevice` / `.registerActivityToken` exist specifically for this —
/// their own doc comments say so — but had zero call sites anywhere in the
/// app, so a relay-only pairing's daemon never learned the phone's push token
/// and app-CLOSED approvals never reached the device (live-reproduced
/// 2026-07-18: a real escalation while locked produced no push in 4+ minutes,
/// only surfacing once the app was foregrounded and re-fetched over the live
/// relay connection).
///
/// Registers with EVERY currently-connected machine, not just one: push
/// delivery is per-daemon (`daemon/lancerd/e2e_router.go`'s `deviceRegister`
/// case populates that daemon's own in-memory `s.device`), so each paired
/// daemon needs its own copy of the token to be able to push an approval that
/// happens on ITS host. push-backend's session→token mapping is shared across
/// every daemon paired to the same phone (they all send the same
/// `DeviceIdentity.sessionID()`), so re-sending the same token to several
/// daemons is idempotent, not wasteful duplication.
///
/// Two independent triggers converge on the same registration path so both
/// orderings work, plus reconnect:
///   1. `ConnectionStateStore` transition to `.connected` for a machine —
///      covers "pairing exists, token arrives later" AND "reconnect after
///      background / relay drop / daemon restart". The daemon does not
///      persist the actual APNs token itself, only session+relayToken (see
///      `server.go savePersistedDevice` / `loadPersistedDevice`) — on a
///      daemon restart it re-registers session+relayToken with push-backend
///      but never re-sends a token it never stored, so a phone-side resend on
///      every reconnect is what actually keeps push-backend's copy correct,
///      not an optional nicety.
///   2. A new token notification (`.lancerAPNSTokenReceived` /
///      `.lancerLiveActivityTokenReady`) — covers "token arrives after
///      pairing already exists".
///
/// `bridge.registerDevice` / `.registerActivityToken` both internally no-op
/// when `bridge.isActive` is false, so an attempt that loses either race is
/// silently skipped, never a crash or a hang — the next trigger (a later
/// token, or the next reconnect) tries again.
@MainActor
public final class DevicePushRegistrationCoordinator {
    /// This path was completely silent when it shipped broken (2026-07-18):
    /// nothing distinguished "never ran" from "ran and lost a race" without a
    /// rebuild. Keep the registration outcomes observable.
    private static let logger = Logger(subsystem: "dev.lancer.mobile", category: "DevicePushRegistration")
    private let fleetStore: RelayFleetStore
    private var listenTask: Task<Void, Never>?
    /// Block-based NotificationCenter observers, registered SYNCHRONOUSLY in
    /// `start()`. The original `for await NotificationCenter.notifications`
    /// listeners only subscribed once their Task began iterating — at cold
    /// launch the AppDelegate's token post consistently beat that (live-
    /// reproduced 2026-07-18) and the token was missed forever.
    /// `nonisolated(unsafe)`: written only from MainActor `start()`, read only
    /// in `deinit` (exclusive access) — safe by construction.
    nonisolated(unsafe) private var observerTokens: [NSObjectProtocol] = []

    /// Last known APNs device token (hex). Re-sent to every machine that
    /// (re)connects after this is set.
    private(set) var apnsTokenHex: String?
    /// Last known Live Activity per-session update token and push-to-start
    /// token, in SEPARATE slots (2026-07-18 review finding): both flow through
    /// the same `.lancerLiveActivityTokenReady` notification distinguished
    /// only by `isPushToStart`, so a single slot let a later per-activity
    /// token silently overwrite an earlier push-to-start token — meaning the
    /// resend-on-reconnect trigger (the whole reason this class re-sends
    /// everything on every `.connected`) stopped covering push-to-start after
    /// any session's activity token arrived, breaking the remote-start-while-
    /// fully-closed path after a daemon restart.
    private(set) var lastActivityToken: ActivityTokenInfo?
    private(set) var lastPushToStartToken: ActivityTokenInfo?
    /// What each machine has already been sent in its CURRENT connect epoch —
    /// cleared on any transition away from `.connected` so a reconnect still
    /// re-registers (the daemon forgets the token on restart), but the token-
    /// notification trigger and the connect trigger racing each other within
    /// one epoch no longer produce duplicate `deviceRegister` sends.
    private var sentAPNSByMachine: [RelayMachineID: String] = [:]
    private var sentActivityByMachine: [RelayMachineID: ActivityTokenInfo] = [:]
    private var sentPushToStartByMachine: [RelayMachineID: ActivityTokenInfo] = [:]

    struct ActivityTokenInfo: Equatable {
        let sessionID: String
        let activityToken: String
        let isPushToStart: Bool
    }

    public init(fleetStore: RelayFleetStore) {
        self.fleetStore = fleetStore
    }

    /// Begin observing connection transitions and token-ready notifications.
    /// Idempotent — a second call while already listening is a no-op.
    public func start() {
        guard listenTask == nil else { return }
        // Nothing else in the app calls this (`LiveActivityManager.swift`'s
        // own doc comment already names AppRoot as the intended caller,
        // "once the stable session ID is available" — `DeviceIdentity
        // .sessionID()` is synchronous/always-available, so there is no wait
        // to gate on). Without this, `Activity.pushToStartTokenUpdates` is
        // never observed and an `isPushToStart` token can never reach
        // `observeLiveActivityTokens()` below, regardless of the rest of this
        // type — push-backend could never start a new Live Activity via APNs
        // for a fully-closed app. Idempotent: `startPushToStartMonitor` no-ops
        // past its first call.
        if #available(iOS 17.2, *) {
            LancerLiveActivityManager.shared.startPushToStartMonitor(sessionID: DeviceIdentity.sessionID())
        }
        // Align Home Screen Agents widget with any already-running Live
        // Activities (push-to-start while the app was closed). Also starts the
        // activityUpdates monitor (deferred re-sync) so a cold-launch race
        // against an empty Activity.activities list does not stick at 0.
        if #available(iOS 16.2, *) {
            LancerLiveActivityManager.shared.syncRunningAgentsWidget()
        }
        fleetStore.connectionStates.addObserver { [weak self] machineID, state in
            guard let self else { return }
            guard state == .connected else {
                sentAPNSByMachine[machineID] = nil
                sentActivityByMachine[machineID] = nil
                sentPushToStartByMachine[machineID] = nil
                return
            }
            Task { @MainActor in
                await self.registerKnownTokens(onMachineID: machineID)
            }
        }
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .lancerAPNSTokenReceived, object: nil, queue: .main
        ) { [weak self] note in
            guard let token = note.userInfo?["token"] as? String, !token.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.apnsTokenHex = token
                await self.registerAPNSOnAllConnected()
            }
        })
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .lancerLiveActivityTokenReady, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let sessionID = note.userInfo?["sessionID"] as? String, !sessionID.isEmpty,
                let activityToken = note.userInfo?["activityToken"] as? String, !activityToken.isEmpty,
                let isPushToStart = note.userInfo?["isPushToStart"] as? Bool
            else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let info = ActivityTokenInfo(sessionID: sessionID, activityToken: activityToken, isPushToStart: isPushToStart)
                if isPushToStart {
                    self.lastPushToStartToken = info
                } else {
                    self.lastActivityToken = info
                }
                await self.registerActivityOnAllConnected()
            }
        })
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .lancerLiveActivityTokenClear, object: nil, queue: .main
        ) { [weak self] note in
            guard let sessionID = note.userInfo?["sessionID"] as? String, !sessionID.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // The activity is gone; drop it from the per-activity dedup
                // tracker too, so a NEW activity for the same session on the
                // same machine can register its (different) token without the
                // stale-value guard in sendActivity silently skipping it.
                for machine in self.connectedMachines() {
                    self.sentActivityByMachine[machine.id] = nil
                }
                await self.clearActivityOnAllConnected(sessionID: sessionID)
            }
        })
        listenTask = Task { [weak self] in
            guard let self else { return }
            // A token captured before the observers above were registered is
            // covered by the cache the AppDelegate writes BEFORE posting —
            // hydrate from it (belt to the observers' braces; `currentAPNSToken`
            // re-checks it on every later registration attempt too).
            let cached = await Notifications.shared.pendingAPNSTokenHex
            if let existing = cached, !existing.isEmpty {
                self.apnsTokenHex = existing
                await self.registerAPNSOnAllConnected()
            }
        }
    }

    /// Removes only the NotificationCenter observers. The `ConnectionStateStore
    /// .addObserver` closure registered in `start()` has no matching removal
    /// API (append-only by design) and `listenTask` is not explicitly
    /// cancelled — harmless for the single AppRoot-lifetime instance this
    /// class is actually used as, but a second `DevicePushRegistrationCoordinator`
    /// construction against the same shared `ConnectionStateStore` would leave
    /// this instance's stale closure still firing registration attempts
    /// against its now-unused fleet store (2026-07-18 review finding).
    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func registerKnownTokens(onMachineID machineID: RelayMachineID) async {
        guard let machine = fleetStore.machine(machineID) else { return }
        let token = await currentAPNSToken()
        if token == nil, lastActivityToken == nil, lastPushToStartToken == nil {
            Self.logger.info("machine connected before any push token exists — nothing to register yet")
        }
        if let token {
            await sendAPNS(token: token, to: machine)
        }
        if let activity = lastActivityToken {
            await sendActivity(activity, to: machine, sentTracker: \.sentActivityByMachine)
        }
        if let pushToStart = lastPushToStartToken {
            await sendActivity(pushToStart, to: machine, sentTracker: \.sentPushToStartByMachine)
        }
    }

    /// The local copy can be nil even though a token exists: at cold launch the
    /// AppDelegate's token callback races both the cache-hydration read in
    /// `start()` and the notification listener's subscription (live-reproduced
    /// 2026-07-18 — the token beat both, so `apnsTokenHex` stayed nil and the
    /// `.connected` trigger sent nothing). Every registration attempt therefore
    /// re-checks the durable cache instead of trusting the local copy.
    private func currentAPNSToken() async -> String? {
        if let token = apnsTokenHex, !token.isEmpty { return token }
        if let cached = await Notifications.shared.pendingAPNSTokenHex, !cached.isEmpty {
            apnsTokenHex = cached
            return cached
        }
        return nil
    }

    private func registerAPNSOnAllConnected() async {
        guard let token = await currentAPNSToken() else { return }
        let machines = connectedMachines()
        for machine in machines {
            await sendAPNS(token: token, to: machine)
        }
    }

    private func registerActivityOnAllConnected() async {
        let machines = connectedMachines()
        if let activity = lastActivityToken {
            for machine in machines {
                await sendActivity(activity, to: machine, sentTracker: \.sentActivityByMachine)
            }
        }
        if let pushToStart = lastPushToStartToken {
            for machine in machines {
                await sendActivity(pushToStart, to: machine, sentTracker: \.sentPushToStartByMachine)
            }
        }
    }

    /// Sends the per-activity token clear to every currently-connected
    /// machine — best-effort, fire-and-forget, matching `sendActivity`'s own
    /// no-ack contract. Not deduped by dictionary the way registration is:
    /// a clear that loses its race (bridge not yet active) has no further
    /// trigger to retry it, but `sendActivity`'s own registration attempts
    /// for the SAME (now ended) session won't fire again either, so no future
    /// registration for that session is at risk of being skipped by this.
    private func clearActivityOnAllConnected(sessionID: String) async {
        for machine in connectedMachines() {
            guard await waitForBridgeActive(machine) else { continue }
            _ = await machine.bridge.registerActivityToken(
                sessionID: sessionID,
                activityToken: "",
                isPushToStart: false,
                pushBackendURL: Self.pushBackendURLString(),
                clear: true
            )
        }
    }

    private func connectedMachines() -> [RelayFleetStore.Machine] {
        fleetStore.pairedMachines.filter { fleetStore.isConnected($0.id) }
    }

    /// `ConnectionStateStore` (which every caller above filters on) reports
    /// `.connected` strictly before the bridge's own async `$isActive` mirror
    /// catches up (see class doc + `ConnectionStateStore`'s own doc comment).
    /// `registerDevice`/`registerActivityToken` both gate on `bridge.isActive`,
    /// so wait a few scheduler turns rather than silently losing that race —
    /// mirrors the same tolerance `E2ERelayBridgeFirstSendTests.makePairedBridge`
    /// needs against the identical skew.
    private func waitForBridgeActive(_ machine: RelayFleetStore.Machine) async -> Bool {
        // Real deadline, not scheduler turns: the Combine hop that mirrors
        // `$isActive` can take longer than any number of same-actor yields.
        let deadline = Date().addingTimeInterval(3)
        while !machine.bridge.isActive, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if !machine.bridge.isActive {
            Self.logger.error("bridge never became active within 3s — dropping this registration attempt (next reconnect retries)")
        }
        return machine.bridge.isActive
    }

    private func sendAPNS(token: String, to machine: RelayFleetStore.Machine) async {
        guard sentAPNSByMachine[machine.id] != token else { return }
        // Claim BEFORE the first suspension: the token-notification trigger and
        // the connect trigger can both pass the guard above between each
        // other's awaits, and a post-send mark lets both through (seen as a
        // duplicate deviceRegister in the idempotence test). Rolled back on
        // any failure so the next trigger retries.
        sentAPNSByMachine[machine.id] = token
        guard await waitForBridgeActive(machine) else {
            sentAPNSByMachine[machine.id] = nil
            return
        }
        let sessionID = DeviceIdentity.sessionID()
        let backendURL = Self.pushBackendURLString()
        // `ApprovalRelay`'s own backend-POST fallback (`postDecisionToBackend`)
        // is fail-closed on an empty sessionID/backendURL, and nothing else in
        // the app ever calls `configureBackend` — wire it here, alongside the
        // token, using the exact values push registration itself needs to be
        // correct, so that fallback path actually activates for relay-only
        // pairings instead of being permanently dead.
        ApprovalRelay.shared.configureBackend(url: backendURL, sessionID: sessionID)
        let ok = await machine.bridge.registerDevice(apnsToken: token, sessionID: sessionID, pushBackendURL: backendURL)
        if !ok {
            sentAPNSByMachine[machine.id] = nil
        }
        Self.logger.info("registerDevice → \(machine.record.displayName, privacy: .public): \(ok ? "sent" : "FAILED")")
    }

    /// `sentTracker` selects which per-machine dedup dictionary applies —
    /// push-to-start and per-activity tokens are tracked (and can each be
    /// re-sent) independently.
    private func sendActivity(
        _ activity: ActivityTokenInfo,
        to machine: RelayFleetStore.Machine,
        sentTracker: ReferenceWritableKeyPath<DevicePushRegistrationCoordinator, [RelayMachineID: ActivityTokenInfo]>
    ) async {
        guard self[keyPath: sentTracker][machine.id] != activity else { return }
        self[keyPath: sentTracker][machine.id] = activity
        guard await waitForBridgeActive(machine) else {
            self[keyPath: sentTracker][machine.id] = nil
            return
        }
        let ok = await machine.bridge.registerActivityToken(
            sessionID: activity.sessionID,
            activityToken: activity.activityToken,
            isPushToStart: activity.isPushToStart,
            pushBackendURL: Self.pushBackendURLString()
        )
        if !ok {
            self[keyPath: sentTracker][machine.id] = nil
        }
    }

    /// HTTPS REST base for push-backend, matching the form the daemon itself
    /// expects (`daemon/lancerd/server.go` `postRelayRegistration` /
    /// `postDeviceTokenRegistration` POST to `<pushBackendURL>/register`) —
    /// reuses `FeedbackClient`'s existing wss→https conversion rather than a
    /// new one.
    private static func pushBackendURLString() -> String {
        FeedbackClient.resolveBackendBaseURL().absoluteString
    }
}
#endif
