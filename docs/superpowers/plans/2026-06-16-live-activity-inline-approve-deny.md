# Inline Approve/Deny inside Live Activity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user Approve/Deny a pending agent approval directly from the Live Activity (Lock Screen + Dynamic Island) without unlocking into the app for low-risk gates, with a biometric gate for high-risk gates, and have the Live Activity start/update remotely via APNs push (hosted-relay tier).

**Architecture:** The widget extension, the `ApprovalActionIntent`, and the lock-screen/Dynamic-Island buttons **already exist and ship**. This plan closes the two real gaps: (1) push delivery — register an ActivityKit push-to-start token, add a `liveactivity` APNs path in the push-backend, and switch `Activity.request(pushType:)` from `nil` to `.token`; (2) inline decisioning — keep the decision running in-process but add a system auth gate for high-risk approvals and make the no-foreground path reliable.

**Tech Stack:** Swift 6 (LancerKit + `LancerLiveActivityWidget` app-extension target), ActivityKit, AppIntents, APNs (`.p8` key), Go push-backend (`daemon/push-backend/`).

## Global Constraints

- **iOS 17.2+** required for ActivityKit push-to-start (research: fine for the Fall-2026 floor).
- **The decision intent must run in the app process** (`openAppWhenRun` stays effectively true for self-host) so the governance chain — audit log, blast-radius, relay verification — stays intact. The Live Activity is a *remote trigger*, never a bypass (verbatim, `docs/audit/live-activity-decision.md:24`).
- **Apple does NOT require biometric for Live Activity buttons** — Lancer MUST add `authenticationPolicy = .requiresAuthentication` on the high-risk Approve path (`live-activity-decision.md:24`).
- **Hybrid A+B tier:** hosted-relay paid tier gets full push Live Activities; self-host tier gets app-foreground updates + `UNNotification` fallback only. Do not promise remote push on self-host.
- **First-decision-wins** is enforced in SQL (`ApprovalRepository.decide` — `WHERE decision IS NULL`); a stale Live Activity tap on a resolved gate is already a safe no-op. Do not weaken it.
- **APNs `.p8` secret never printed/committed.** Push-backend reads it from env/secret store, same as today's `pushApproval`.
- **Do NOT `git commit` unless the user explicitly asks.**

---

## File Structure

| File | New/Mod | Responsibility |
|---|---|---|
| `Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift` | Mod (`:114-117`) | `start()` requests `pushType: .token`; expose the push-to-start token + per-activity update token. |
| `Packages/LancerKit/Sources/SessionFeature/LiveActivityPushManager.swift` | New | Observe `Activity.pushToStartTokenUpdates` + per-activity `pushTokenUpdates`; register both with the push-backend. |
| `Packages/LancerKit/Sources/SessionFeature/ApprovalActionIntent.swift` | Mod (`:20-60`) | Add `authenticationPolicy` for high-risk; keep `ApprovalRelay.enqueue` routing. |
| `Packages/LancerKit/Sources/NotificationsKit/Notifications.swift` | Mod (`:230`) | Add `registerLiveActivityToken(pushToStart:update:sessionID:)` → `POST /register-liveactivity`. |
| `daemon/push-backend/main.go` | Mod (`:350`) | Add `POST /register-liveactivity` + a `pushLiveActivity()` sender (`apns-push-type: liveactivity`). |
| `daemon/push-backend/main_test.go` | Mod | Tests for the new endpoint + payload shape. |
| `Packages/LancerKit/Tests/LancerKitTests/LiveActivityPushTests.swift` | New | Token-registration payload tests (entitlement-independent). |

---

## Task 1: push-backend `liveactivity` endpoint + sender

**Files:**
- Modify: `daemon/push-backend/main.go`, `daemon/push-backend/main_test.go`

**Interfaces:**
- Produces:
  - `POST /register-liveactivity` body `{sessionId, pushToStartToken, updateToken?, apnsToken}` → stores tokens on the session record.
  - `func (s *server) pushLiveActivity(sessionID string, state liveActivityState) error` sending `apns-push-type: liveactivity`, `apns-priority: 10`, topic `<bundle>.push-type.liveactivity`, payload `{aps:{timestamp, event:"start"|"update", "content-state":{…}, "attributes-type":"LancerSessionAttributes", attributes:{…}, alert:{…}}}`.

**Background (verified):** `pushApproval()` (`main.go:350-413`) already sends `apns-push-type: alert` via `.p8` auth and stores `apnsToken` per session. The Live Activity sender mirrors this with a different push type, topic suffix, and payload schema. No `liveactivity` code exists yet.

- [ ] **Step 1: Write the failing test for the registration endpoint**

```go
func TestRegisterLiveActivityStoresTokens(t *testing.T) {
	s := newTestServer(t)
	body := `{"sessionId":"s1","pushToStartToken":"P","updateToken":"U","apnsToken":"A"}`
	rec := s.do(t, "POST", "/register-liveactivity", body)
	if rec.Code != 200 {
		t.Fatalf("code = %d", rec.Code)
	}
	sess := s.session("s1")
	if sess.PushToStartToken != "P" || sess.LiveActivityUpdateToken != "U" {
		t.Fatalf("tokens not stored: %+v", sess)
	}
}
```
(Adapt `newTestServer`/`s.do`/`s.session` to the existing test harness in `main_test.go`.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd daemon/push-backend && go test -run TestRegisterLiveActivity ./...`
Expected: FAIL — handler/route missing.

- [ ] **Step 3: Add token fields, route, and `pushLiveActivity`**

Add `PushToStartToken` and `LiveActivityUpdateToken` fields to the session record struct. Register the route next to `/register`. Implement the handler (decode → upsert tokens) and `pushLiveActivity()` modeled on `pushApproval()` (`main.go:350`), changing:
- header `apns-push-type: liveactivity`
- topic `apnsTopic + ".push-type.liveactivity"`
- payload uses `aps.event` + `aps."content-state"` + `aps.attributes` (start event) per ActivityKit remote push schema; include a minimal `alert` (Apple requires it for `start`).

- [ ] **Step 4: Run to verify it passes**

Run: `cd daemon/push-backend && go test ./...`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add daemon/push-backend/main.go daemon/push-backend/main_test.go
git commit -m "feat(push-backend): liveactivity push-to-start registration + sender"
```

---

## Task 2: iOS push-to-start token registration

**Files:**
- Create: `Packages/LancerKit/Sources/SessionFeature/LiveActivityPushManager.swift`
- Modify: `Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift:114-117`, `Packages/LancerKit/Sources/NotificationsKit/Notifications.swift:230`
- Test: `Packages/LancerKit/Tests/LancerKitTests/LiveActivityPushTests.swift`

**Interfaces:**
- Consumes: `Notifications.registerDeviceToken()` pattern (`Notifications.swift:230`), `LancerLiveActivityManager` (`LiveActivityManager.swift`).
- Produces:
  - `Notifications.registerLiveActivityToken(pushToStart: String?, update: String?, sessionID: String) async`
  - `LiveActivityPushManager.start()` — spawns tasks observing `Activity<LancerSessionAttributes>.pushToStartTokenUpdates` and each activity's `pushTokenUpdates`, forwarding hex token strings to `registerLiveActivityToken`.

- [ ] **Step 1: Write the failing token-encoding test**

```swift
func testTokenHexEncoding() {
    let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
    XCTAssertEqual(LiveActivityPushManager.hex(data), "deadbeef")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/LancerKit && swift test --filter LiveActivityPushTests`
Expected: FAIL — `LiveActivityPushManager` undefined.

- [ ] **Step 3: Implement `LiveActivityPushManager` + `start()` token request**

In `LiveActivityManager.swift:114`, change `Activity.request(... pushType: nil)` → `pushType: .token`. Implement `LiveActivityPushManager` with the static `hex(_:)` helper and async observation of `pushToStartTokenUpdates`/`pushTokenUpdates`, calling `Notifications.registerLiveActivityToken(...)`. Add `registerLiveActivityToken` in `Notifications.swift` (mirror `registerDeviceToken` → `POST /register-liveactivity`).

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/LancerKit && swift test --filter LiveActivityPushTests`
Expected: PASS.

- [ ] **Step 5: Authoritative app-target build**

`mcp__XcodeBuildMCP__build_sim` (Lancer / iPhone 17 Pro). Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit (stage only)**

```bash
git add Packages/LancerKit/Sources/SessionFeature/LiveActivityPushManager.swift \
        Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift \
        Packages/LancerKit/Sources/NotificationsKit/Notifications.swift \
        Packages/LancerKit/Tests/LancerKitTests/LiveActivityPushTests.swift
git commit -m "feat(ios): register Live Activity push-to-start + update tokens"
```

---

## Task 3: biometric gate on the high-risk Approve intent

**Files:**
- Modify: `Packages/LancerKit/Sources/SessionFeature/ApprovalActionIntent.swift:20-60`

**Interfaces:**
- Consumes: `ApprovalRelay.shared.enqueue` (`ApprovalRelay.swift:88`), `AppDatabase.openShared()`.
- Produces: high-risk Approve requires system auth before `perform()` proceeds; Deny never requires auth (denial is always safe).

**Background (verified):** `ApprovalActionIntent` is a `LiveActivityIntent` already routing through `ApprovalRelay`. Apple does not auto-gate Live Activity buttons; add `authenticationPolicy`. Gate only on high risk to avoid friction (research mitigation).

- [ ] **Step 1: Add an authenticated variant + risk lookup**

Add `static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }` to a new `ApprovalApproveHighRiskIntent` (or branch in `perform()` reading the approval's `risk` from the shared DB before forwarding, and throwing `.needsToContinueInForegroundError()` when `risk >= high` and the device is locked). Keep the existing `ApprovalActionIntent` for Deny + low-risk Approve.

- [ ] **Step 2: Wire the widget buttons to the right intent by risk**

In `LancerLiveActivityWidget/LancerLiveActivityWidget.swift` (the 4 `Button(intent:)` sites at `:60,71,115,125`), choose the high-risk Approve intent when `context.state` indicates a high-risk pending approval; Deny + low-risk use the existing intent.

- [ ] **Step 3: Authoritative app-target build**

`mcp__XcodeBuildMCP__build_sim`. Expected: BUILD SUCCEEDED. (ActivityKit entitlement limits unit testing; build + a manual device check is the gate.)

- [ ] **Step 4: Commit (stage only)**

```bash
git add Packages/LancerKit/Sources/SessionFeature/ApprovalActionIntent.swift \
        LancerLiveActivityWidget/LancerLiveActivityWidget.swift
git commit -m "feat(ios): require auth for high-risk Approve from Live Activity"
```

---

## Task 4: hosted-relay push trigger + end-to-end verification

**Files:**
- Modify: `daemon/lancerd/` (the relay/approval emit path that already forwards approvals) to additionally request a `liveactivity` push from the push-backend on `approvalPending` for hosted-tier hosts.

- [ ] **Step 1: Forward approval-pending → push-backend liveactivity push (hosted tier only)**

Where lancerd already forwards an approval to the phone/relay, add (gated on hosted tier) a call to the push-backend's liveactivity sender so a locked phone gets a push-to-start. Self-host tier skips this (foreground-only + UNNotification fallback already exist).

- [ ] **Step 2: Daemon + backend test pass**

Run: `cd daemon/push-backend && go test ./...` and `cd daemon/lancerd && go test ./...`
Expected: PASS.

- [ ] **Step 3: Manual device verification (documented in PR)**

1. Pair a real device (hosted-relay tier); lock it.
2. Trigger an agent approval on the host.
3. Confirm a Live Activity *starts* on the Lock Screen via push (no app open).
4. Tap Deny → confirm the gate resolves (audit shows `source: liveActivityIntent`) without unlocking.
5. Tap Approve on a high-risk gate → confirm Face ID/passcode is required first.
6. Self-host tier: confirm the Live Activity updates only while the app is foregrounded and the `UNNotification` fallback still fires.

---

## Spec coverage check

| Requirement | Task |
|---|---|
| Push-to-start + push-update (hosted tier) | Tasks 1, 2, 4 |
| Inline Approve/Deny buttons (already shipped) | reused; risk-gated in Task 3 |
| `UserAuthenticationRequired` for high-risk | Task 3 |
| Self-host foreground-only + UNNotification fallback | reused (no remote push) — Task 4 step 3 |
| Governance chain intact (in-process decision) | Global Constraints + reused `ApprovalRelay` |

## Placeholder scan

- Each code step names exact files/lines and shows the concrete change. Two ActivityKit specifics (remote-push payload schema, `IntentAuthenticationPolicy` exact API) are cited to Apple docs — implementer should confirm via `mcp__apple-docs__*` before finalizing, not guess from memory.
