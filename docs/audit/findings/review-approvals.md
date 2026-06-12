# Governed Approvals v1 — Approval/Decision Flow Review (app side)

Branch: `feat/governed-approvals` · Reviewer pass: pre-submission correctness/security audit
Scope: `AppFeature/{ApprovalIngest,FleetStore,AppRoot}`, `SessionFeature/{ApprovalRelay,ApprovalActionIntent,RecentPatch}`, `InboxFeature/*`, `ConduitCore/{WatchApprovalTransfer,AuditEvent,AgentStatusProtocol,ConduitDProtocol,Approval}`, `PersistenceKit/ApprovalRepository`, `SecurityKit/BiometricGate`, `AgentKit/Redactor`, `SSHTransport/DaemonChannel`, `NotificationsKit/Notifications`, `Conduit/ConduitApp` (AppDelegate + notification delegate), `DesignSystem/Components/InboxCards`. Cross-referenced the backend relay (`daemon/push-backend/{decisions,relay_security,main}.go`) only to determine the Swift call-site contract.

No source was modified. No build was run.

---

## DECISION-PATH TRACE (tap → delivery)

1. **conduitd → app (ingest):** `DaemonChannel` (actor) frames JSON-RPC over the SSH exec channel; `agent.approval.pending` decodes to `ApprovalPendingParams` → `DaemonEvent.approvalPending`. `ApprovalIngest` (actor) consumes `channel.events`, builds an `Approval`, `repository.upsert(...)`, then fires a local `UNNotification` (category `approval`, actions `approval.approve`/`approval.reject`).
2. **Inbox-card path (foreground):** tap on `DSApprovalCard`/`DSMCPCallCard` → `InboxView` closures → `LiveInboxViewModel.decide` → `super.decide` (in-memory) + `Task { repository.decide(...); onDecision(id,decision,edited) }`. `onDecision` (wired in `AppRoot.startSession`) writes an audit row and calls `channel.respond(...)` → JSON-RPC `agent.approval.response` over SSH.
3. **Lock-screen banner path:** `ConduitNotificationDelegate.didReceive` (in `ConduitApp.swift`) maps the action id to `approve`/`reject` and `NotificationCenter.post(.conduitApprovalAction,…)`. `AppRoot.onReceive` → `handleApprovalAction` → `slot.inboxVM.decide` (or `activeInboxViewModel.decide`) → same path as (2).
4. **Live Activity / Dynamic Island path:** `ApprovalActionIntent.perform` (in-process) → `ApprovalRelay.shared.enqueue(...)`: persists to DB + audit, then if a `DaemonChannel` is attached `channel.respond`, **else** `postDecisionToBackend(...)` AND `queue.append(...)`.
5. **Relay fallback (no live SSH):** `ApprovalRelay.postDecisionToBackend` → `POST {backend}/approval/decision` `{approvalId,decision,sessionId}`. conduitd polls `GET /decisions?sessionId=…` and applies; an un-delivered decision fails safe via conduitd's ~120 s wait → auto-deny.
6. **Watch path:** `PhoneWatchConnector` `onDecision` → audit + `channel.respond`.

Two transports (live SSH `channel.respond` and the backend relay) and ≥3 UI surfaces (card, banner, Live Activity, Watch) all converge on the **same `approvalId`** with **no app-side de-duplication or first-decision-wins guard** (see BLOCKER-2).

---

## BLOCKER

### [BLOCKER] ApprovalRelay.swift:112–123 — relay decision POST sends no authentication; the backend gate it must satisfy is never populated, so the relay is either spoofable (open) or silently dropped (secured)
`postDecisionToBackend` builds the request with only `Content-Type: application/json` and discards the result: `_ = try? await URLSession.shared.data(for: req)` (L122). The backend's own guard `relayAuthorized` (`daemon/push-backend/relay_security.go:46`) is an **optional** `Authorization: Bearer <APPROVAL_RELAY_SECRET>` check on `POST /approval/decision` (`decisions.go:76`).
- If `APPROVAL_RELAY_SECRET` is **set** (the secure config): the app's header-less POST returns `401`, the app ignores the status, the decision is silently lost, and conduitd auto-denies at 120 s. The relay fallback is **dead in the hardened config** and the app cannot tell.
- If it is **unset** (the only config in which the relay works): the endpoint is fully anonymous — any caller who reaches the backend with a known `approvalId` (it surfaces in audit metadata and notification `userInfo`) + `sessionId` (= `identifierForVendor`) can resolve a gate, with no nonce/replay binding and no proof the caller is the device that owns the session.

There is no per-session capability token (this is exactly `review-backend.md` BLOCKER-1, whose fix requires the *iOS* change that has not shipped). The decision is not bound to a secret known only to the device, and the HTTP response/status is never inspected.
**Reachability:** Every approval decided while no `DaemonChannel` is attached (app cold-launched from a push, session disconnected, Live Activity tap) flows through this POST; production builds set `CONDUIT_PUSH_BACKEND_URL`, so the relay is live at submission.
**Proposed fix:** Establish a per-session capability token over the already-authenticated SSH channel (conduitd → app) and send it as `Authorization: Bearer <token>` on the decision POST (and on `/register`/poll); the backend binds `sessionId→token` at first register and constant-time-compares. Until then, at minimum (a) send the configured secret as `Authorization`, and (b) inspect the `HTTPURLResponse` status — on non-2xx do not treat the decision as delivered (keep the queued SSH drain and surface a retry), instead of swallowing the error.

### [BLOCKER] PersistenceKit/ApprovalRepository.swift:90–97 + InboxView.swift / AppRoot.swift:318–333 — no first-decision-wins / idempotency guard; a lingering notification can re-resolve (and flip) an already-decided gate
`ApprovalRepository.decide` runs an unconditional `UPDATE approvals SET decision=?, decidedAt=? WHERE id=?` — no `AND decision IS NULL`. `InboxViewModel.decide`/`LiveInboxViewModel.decide` (`InboxView.swift:18`, `InboxViewModel+Live.swift:44`) and `AppRoot.handleApprovalAction` (`AppRoot.swift:318`) never check `isPending`. Delivered notifications are **never cleared** after an in-app decision (no `removeDeliveredNotifications` anywhere). So: deny a dangerous command on the card → conduitd told `deny`; the lock-screen notification for that same `approvalId` is still present → tapping **Approve** on it calls `decide(.approved)`, overwrites the DB row to `approved`, and sends `channel.respond(approve)` to conduitd. Two conflicting decisions reach conduitd for one gate; whichever it honors last can flip a deny into an approve (or double-resolve an approve). Because each `decide` spawns an independent `Task` (`InboxViewModel+Live.swift:51`), even rapid double-taps race with non-deterministic send order.
**Reachability:** Any approval where the user decides in-app while the local/APNs notification is still on the lock screen (the common case — nothing dismisses it), or a double-tap on the card.
**Proposed fix:** Make the first decision authoritative: `UPDATE … WHERE id=? AND decision IS NULL` and have `decide` return whether a row actually changed; only fire `onDecision`/`channel.respond` when it did. Guard the VM/`handleApprovalAction` on `approval.isPending`. On decide, call `UNUserNotificationCenter.removeDeliveredNotifications(withIdentifiers:[approvalId])`.

---

## MAJOR

### [MAJOR] SecurityKit/BiometricGate.swift:31–32 — `.biometryLockout` silently resolves as success (auth bypass)
`case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout: cont.resume()` treats biometric **lockout** the same as "no biometrics configured" and returns success without authenticating. This is the prior-audit LOW item that was supposed to be closed — it is **not**. `BiometricGate.shared.unlock` gates both the app lock (`AppRoot.attemptUnlock`, L337) and SSH Ed25519 key use (`AppRoot.openSession`, L819). An attacker holding the device who deliberately fails Face/Touch ID five times forces lockout, after which the gate grants access (app unlock + key load) with no biometric or passcode.
**Reachability:** Device in biometry lockout (5 failed attempts) → app lock and key-auth both pass silently.
**Proposed fix:** Treat `.biometryLockout` as a fallback to device passcode (evaluate `.deviceOwnerAuthentication`) — or, if degrade is intended only for *absent* biometrics, resume successfully solely for `.biometryNotAvailable`/`.biometryNotEnrolled` and throw on `.biometryLockout`.

### [MAJOR] SSHTransport/DaemonChannel.swift:121 + ApprovalRelay.swift:67–68 / AppRoot.swift:868 — decision silently dropped when the channel is dead; no relay fallback on the live path
`respond` does `guard let writer = stdinWriter else { return }` — if the channel was `stop()`-ed (writer niled, `DaemonChannel.swift:267`) it returns **success** without sending. All callers use `try? await channel.respond(...)`, swallowing both the no-op and any write error. On the live path (`onDecision` in `startSession`, and `ApprovalRelay.enqueue`'s `if let ch = channel` branch) there is **no fallback to the backend relay** when the attached channel is dead/stale — only the `channel == nil` branch posts to the backend. Result: the DB row + audit say "approved" and the UI shows decided, but conduitd never receives it; it auto-denies at 120 s.
**Reachability:** Decide during a disconnect/reconnect window, or via `ApprovalRelay` holding a stale non-nil `weak channel` that has been stopped but not yet `clearChannel()`-ed.
**Proposed fix:** Have `respond` throw (e.g. `DaemonChannelError.notRunning`) when `stdinWriter == nil` instead of returning; in `onDecision`/`enqueue`, on a thrown/failed `respond` fall through to `postDecisionToBackend` + queue rather than `try?`-swallowing, and reflect the failure in the UI.

### [MAJOR] Conduit/ConduitApp.swift:167–207 ↔ AppRoot.swift:299–301 — cold-launch banner Approve/Reject is lost (post races the in-app subscriber)
`ConduitNotificationDelegate.didReceive` posts `.conduitApprovalAction` to `NotificationCenter` synchronously during launch. `AppRoot` only subscribes via `.onReceive` once `mainBody` is evaluated (and, with `appLockEnabled`, while the lock view is shown the subscription still races first-render). `NotificationCenter` does not buffer, so a decision tapped from a **killed** app's lock-screen banner is delivered before any subscriber exists and is dropped — never persisted, never sent → 120 s auto-deny. (The Live Activity `ApprovalActionIntent` path is robust because `perform()` persists synchronously; the plain banner-action path is not.)
**Reachability:** App not running (backgrounded-then-evicted is common), user taps Approve on the approval banner.
**Proposed fix:** Don't rely on a live `NotificationCenter` subscriber. Handle the action authoritatively in `didReceive` itself (persist + enqueue via `ApprovalRelay`, the same as `ApprovalActionIntent.perform`), or stash the pending action and replay it after the root view subscribes.

### [MAJOR] ConduitCore/Approval.swift:42–58 + PersistenceKit/ApprovalRepository.swift:7–36 — `blastRadius`/`question`/`choices`/`answeredChoice` are dropped on DB round-trip, so the governance banner never renders
`Approval.encode(to:)` does not persist `blastRadius`, `question`, `choices`, or `answeredChoice`, and `init(row:)` does not read them. `ApprovalIngest` builds the approval *with* `blastRadius` and `upsert`s it, but `LiveInboxViewModel` replaces its array from `repository.observe()` (`InboxViewModel+Live.swift:31`), which re-reads from the DB → `blastRadius == nil`. So `InboxView`'s `if let br = approval.blastRadius { DSBlastRadiusBanner(...) }` (`InboxView.swift:188`) is effectively dead — the files/git/network/matched-rule context the "governed" approval is meant to show is silently absent at decision time. (`toolName/toolUseID/agentSessionID/toolInput` survive — they have columns; these four do not.)
**Reachability:** Any approval carrying blast-radius escalation metadata (the WS-B policy path) — banner never appears.
**Proposed fix:** Persist and decode the blast-radius fields (and ask-question fields) — add columns + encode/decode — or have the live VM merge the in-memory ingest object's `blastRadius` onto the observed rows.

### [MAJOR] AppRoot.swift:798 & 836, Conduit/ConduitApp.swift:123 — divergent `identifierForVendor ?? UUID()` fallback can mis-route push + relay decisions
The session id is computed independently at four sites as `UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString`: APNs device-token register (`ConduitApp.swift:123`), `ApprovalRelay.configureBackend` (`AppRoot.swift:798`), and `startSession`'s `deviceSessionID` used for `channel.registerDevice` + relay reconfigure (`AppRoot.swift:836`, 951/957). When `identifierForVendor` is `nil` (before first unlock after reboot — and APNs registration can fire that early) each site invents a *different* random UUID. conduitd then registers/polls under one id while the relay POSTs decisions under another → the decision is stored under a session key conduitd never polls → silent 120 s timeout-deny, and APNs approvals never reach the device. This is the doc-conflict #3 (identifierForVendor mismatch) — still present.
**Reachability:** Low-probability but real (IDFV-nil window at boot); silent when it hits.
**Proposed fix:** Resolve one stable session id once (persist a UUID in Keychain/UserDefaults the first time, reuse everywhere) instead of re-deriving with a per-call random fallback.

### [MAJOR] ApprovalRelay.swift:67–75 & 125–132 — offline decision is double-delivered (backend relay + queued SSH drain), relying on unverified conduitd dedup
In the `channel == nil` branch, `enqueue` both `postDecisionToBackend(...)` (L73) **and** `queue.append(...)` (L74). On the next connect, `setChannel` → `drainQueue` re-sends the same `approvalId` via `channel.respond` (L130). conduitd therefore receives the decision twice through two independent transports. The backend relay is itself idempotent by `approvalId` (`decisions.go:107`), but that does not cover the second SSH delivery — exactly-once across the two transports rests entirely on conduitd de-duplicating by `approvalId`, which is outside the app and unverified here.
**Reachability:** Decide while offline, then reconnect the same session.
**Proposed fix:** Pick one transport per decision: if the backend POST is attempted (and confirmed 2xx), don't also queue for SSH drain; or tag drained items so a re-send is skipped once the backend acknowledged. Track per-`approvalId` delivery state.

---

## MINOR

### [MINOR] AgentKit/Redactor.swift:17–26 — no PEM / Bearer / JWT patterns (prior LOW not closed)
`builtInPatterns` covers AWS/GitHub/Anthropic/OpenRouter/OpenAI/`ghs_` keys but not PEM private-key blocks (`-----BEGIN … PRIVATE KEY-----`), `Bearer <token>`, or JWTs (`eyJ…`) — the exact gaps called out in `docs/SECURITY-REVIEW.md:73` and `review-core-kits.md:89`. Approval `command`/`toolInput` and terminal context passed to redaction can leak these.
**Reachability:** A pasted PEM key or `Authorization: Bearer …`/JWT in command/tool input or session context routed through `Redactor`.
**Proposed fix:** Add patterns: PEM block (`-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----`), `Bearer\s+[A-Za-z0-9\-._~+/]+=*`, and JWT (`eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+`).

### [MINOR] Conduit/ConduitApp.swift:142–146 + NotificationsKit/Notifications.swift:17 — `.conduitRemoteApprovalReceived` is posted but never observed
`application(_:didReceiveRemoteNotification:)` broadcasts `.conduitRemoteApprovalReceived` "so the Inbox can refresh," but no one subscribes (AppRoot observes only `.conduitApprovalAction` and `.conduitRunCompleteAction`). A background APNs approval thus does not refresh inbox state; since the push doesn't write the DB, a push-only approval (app killed, no live SSH) won't surface in-app until an SSH reconnect runs `ApprovalIngest`.
**Reachability:** Remote approval push delivered while backgrounded with no live channel.
**Proposed fix:** Either remove the dead broadcast or add an observer that fetches/upserts the approval (e.g. via the relay/poll) into the DB so the inbox updates.

### [MINOR] AppRoot.swift:318–333 — `handleApprovalAction` ignores `sessionId`, and decides on the static `InboxViewModel` before the live VM is wired
The handler routes purely by `approvalId` (fine, it's unique) but discards `sessionId`, and if it fires before `configureGlobalInbox`/`startSession` set `liveInboxVM`, `activeInboxViewModel` is the base `InboxViewModel` whose `decide` only mutates memory (no persistence, no `channel.respond`) — a silent no-op.
**Reachability:** Notification action handled in the brief window before the live inbox VM is installed.
**Proposed fix:** If no live VM/repository is available yet, route through `ApprovalRelay.shared.enqueue` (which persists) rather than the static VM.

---

## NIT

- **[NIT] SSHTransport/DaemonChannel.swift:14 — single `AsyncStream` shared by multiple consumers (latent).** `events` returns one stored stream; `ApprovalIngest` (`ApprovalIngest.swift:22`), `RecentPatch` (`RecentPatch.swift:26`) and `SSHHostRuntime` (`SSHHostRuntime.swift:294`) all iterate `channel.events`. `AsyncStream` delivers each element to only one iterator, so if a second consumer is ever attached to the *approval* channel, `approvalPending` events would be split and silently dropped. Currently safe (`RecentPatch` is never instantiated; `SSHHostRuntime` uses its own channel). Fix: make `events` a broadcast/multiplexed stream, or assert a single subscriber.
- **[NIT] DaemonChannel.swift:81–84 vs 135 — concurrent writes to one `TTYStdinWriter`.** `sendRPC` writes inside a detached `Task` while `respond` awaits a write directly; across actor suspension two frames can hit the same writer concurrently, relying on Citadel to serialize. Consider funneling all writes through one serialized path.
- **[NIT] ApprovalActionIntent.swift:42–44 — invalid `approvalID` returns `.result()` (success).** A malformed id makes the Live Activity button a silent no-op. Prefer surfacing/logging the failure.
- **[NIT] ApprovalRelay.swift:114 — DEBUG `CONDUIT_PUSH_BACKEND_URL` may be `http://`.** Release ATS blocks cleartext, but a debug http base would POST decisions in cleartext. Pin to https or assert scheme.

---

## Verified RESOLVED / holds (adversarial pass — no issue)

- **`.approvedAlways` not collapsed (doc-conflict #1):** `DaemonChannel.decisionWireValue(.approvedAlways) == "approveAlways"` (`DaemonChannel.swift:111`), preserved through `respond`, the relay body (`ApprovalRelay.swift:103`), and `DSMCPCallCard`/`DSApprovalCard` "always" buttons. Confirmed by `ApprovalDecisionWireTests` and `ApprovalRelayBackendTests`.
- **Structured tool_use wire protocol (doc-conflict #2):** `ApprovalPendingParams` carries `toolName`/`toolUseID`/`agentSessionID`/`toolInput` as discrete fields (`ConduitDProtocol.swift:59–62`), persisted/restored, and sent full via `respond(editedToolInput:)`. The 240-char truncation in `summarizedToolInput` (`InboxView.swift:282`) is display-only; the wire payload is not flattened/truncated. Confirmed by `ApprovalToolUseTests`.
- **TOFU intact / no debug auto-trust leak (#4):** `autoTrustHostKey` defaults to `false` and is set `true` only in `DebugTerminalHarness` (`#if DEBUG && os(iOS)`) and `LiveTerminalView` defaults. The approval channel rides the `SSHSession` whose host key is verified via the real TOFU sheet (`AppRoot` `pendingHostKeyFingerprint` → `trustHostKey`/`rejectHostKey`); no `CONDUIT_TEST_*`/gallery path feeds the approval connection.
- **Notification action wiring is live (not dead):** `ConduitNotificationDelegate` is installed (`ConduitApp.swift:110`) and posts `.conduitApprovalAction` for `approval.approve`/`approval.reject`; the Approve action carries `.authenticationRequired`. (The cold-launch race is BLOCKER/MAJOR-5 above, not a dead-wire issue.)
- **Fail-safe default-deny holds at the conduitd layer:** every silent-drop path above ends in conduitd's ~120 s wait → auto-deny (`decisions.go:24`), so uncertain delivery never auto-*approves*. The findings above are about silent failure + UI/state inconsistency + the relay's missing authentication, not a default-approve hole.
