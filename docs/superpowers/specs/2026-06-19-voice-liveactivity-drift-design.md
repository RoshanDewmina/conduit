# Design — Voice cockpit, Live-Activity/Watch reach, and Drift detection

**Date:** 2026-06-19 · **Status:** approved design (revised after Codex review 2026-06-19), pre-implementation-plan
**Scope:** one combined design covering three independent competitive features (gaps #2, #4, #1 from
the 2026-06-19 competitive review). Each ships independently but shares the relay/APNs plumbing.
**Platform note:** the dev environment is on **iOS / macOS / watchOS 27 beta**. APIs named here are
verified against current Apple docs (2026-06-19), but every load-bearing API gets a fresh
`apple-docs` pass at plan/implementation time — especially the watchOS-27 background/entitlement
details flagged below.

> Context this builds on (read first): `ARCHITECTURE.md` §0.1/§4.1 (current state + IA),
> `docs/PRODUCT_RESEARCH.md` §3.1 (competitor snapshot). **V1 transport is the E2E relay, not SSH**
> — these features ride the relay + APNs path, never a phone-held SSH session.

## 0. Why these three

From the corrected competitive picture:
- **#2 Voice** — market table-stakes. Happy & Omnara ship *two-way voice*; Claude Code ships push-to-talk `/voice`. Lancer has **legacy push-to-talk dictation only** (`DictationEngine`/`SFSpeechRecognizer`) — no governed two-way cockpit. The work is to *upgrade*, not start from zero.
- **#4 Watch / Live Activity / Dynamic Island** — **~80% built already** (full Live Activity + Dynamic Island with interactive Approve/Reject AppIntents; Watch app with 6 views + WCSession sync). The gap is that it doesn't work **while the app is closed / phone is away** — exactly when it matters.
- **#1 Drift detection** — *offense*. Blume (blume.codes) is staking out agent-config oversight; `lancerd` already sits in the hook path and sees policy + every tool call, so Lancer can do drift detection **better** and on the phone.

**Non-goal:** connection-resilience / Mosh / cloud-migration — a *non-gap* given the resident-daemon + relay model (the phone never holds the session). Do not build for it.

## 1. Sequencing (approved 2026-06-19, revised after Codex review)

Rationale for the revision: config/policy **drift is the governance moat**; full two-way voice is
**parity**. So the deterministic drift MVP leapfrogs the full voice cockpit. Watch-away independence is
demoted from a phase to a **verification spike** (its watchOS-27 feasibility is unproven — §2.4).

| Phase | Feature | Why here | Rough size |
|---|---|---|---|
| **1** | #4 **Track A** — Live Activity push-update reliability | Smallest, rides the in-flight Phase-5c APNs/relay work, highest daily payoff (makes what's built actually work away from the app). Includes the cold-decision acceptance gate (§2.2) and APNs payload-privacy policy (§2.6). | S–M |
| **2** | #4 **Track C** — Watch polish/wiring | Small; tighten the 6 existing Watch views (live updates + decision round-trip) over the current WCSession path before adding independence | S |
| **3** | #1 **Drift MVP** — deterministic config inventory + policy coverage | The governance differentiator; deterministic (no false-positive risk); `lancerd` already sees config + policy. Ships ahead of voice. | M |
| **4** | #2 **Voice cockpit** | Market parity; migrates the existing `DictationEngine` into a governed `VoiceKit` (§3); new `VoiceFeature` UI | M–L |
| **5** | #1 **Behavioral drift** + #4 **Track B spike** | Behavioral drift is gated on an audit-schema expansion (§4) and stays **advisory** until false-positives are measured; Track B watch-away is a feasibility spike (§2.4) before any commitment | L |

Phases are independently shippable. Track B (Phase 5) is a **spike, not a committed build** — it only
graduates to a phase if the watchOS-27 verification in §2.4 comes back favorable.

---

## 2. #4 — Live Activity push reliability + Watch reach

### 2.1 Problem
`SessionFeature/LiveActivityManager.swift` requests activities with **`pushType: nil`** and updates them
only via in-process `activity.update(...)`. So the Live Activity / Dynamic Island only refresh **while
the app has execution time**. When the phone is pocketed and the app is suspended, the surface goes
stale — the agent can be blocked on an approval and the lock screen won't reflect it. The Watch syncs
via **WCSession**, which requires the phone to be reachable, so there is no true wrist-only control.

### 2.2 Track A — push-driven Live Activity (Phase 1)
**Approach:** move the Live Activity from local-update to **APNs push-update**, driven by `push-backend`
(the same service that already relays approvals + sends APNs alerts).

- Request with **`pushType: .token`**; consume **`Activity.pushTokenUpdates`** (async sequence) to obtain/refresh the per-activity push token. Register `{activityToken, sessionId}` with `push-backend`.
- When an approval/status/cost change occurs, `push-backend` sends an **ActivityKit push** (APNs `content-state` payload) to that token instead of relying on the app to be alive.
- **`Activity.pushToStartToken` / `pushToStartTokenUpdates`** — register a push-to-start token so an incoming approval can **start** a Live Activity remotely even when none is running (app fully closed). Backend sends a push-to-start payload.
- **`ActivityAuthorizationInfo.frequentPushesEnabled`** — observe + request frequent-update capability for rapidly-changing runs (streaming/cost). Degrade gracefully when off.
- Keep the existing local `update(...)` path as a foreground fast-path; push is the away path. The two must converge on the same `ContentState` (single source of truth in `LancerLiveActivityManager`).

**Backend — strict ActivityKit push contract (do not hand-wave this).** ActivityKit push is unforgiving;
"send the content-state" is insufficient and updates fail **silently** if the contract is off. `push-backend`'s
ActivityKit sender MUST:
- Set `apns-topic` to **`<bundleID>.push-type.liveactivity`** (not the bare bundle id used for alert pushes).
- Set `apns-push-type: liveactivity` and an appropriate `apns-priority` (10 for user-facing approval
  changes — but priority-10 liveactivity pushes are **budgeted/throttled** by iOS; see §6.2).
- Send a payload with **`aps.timestamp`** (unix seconds), **`aps.event`** (`update` or `end`), and
  **`aps.content-state`** that decodes **exactly** into `LancerSessionAttributes.ContentState`.
- Encode `ContentState.lastUpdate` (a Swift `Date`, `LiveActivityManager.swift:39`) **the way ActivityKit's
  default `JSONDecoder` expects** — i.e. matching the default `Date` strategy ActivityKit uses to decode the
  content-state. A mismatched date encoding silently drops the whole update. Pin and unit-test this encoding.
- Optionally `aps.dismissal-date` / `aps.stale-date` to bound the surface lifetime.

Reuses the existing `.p8`/APNs config. New endpoint to register/refresh activity + push-to-start tokens,
keyed by the same `sessionId` used for the alert-push token (the MAJOR-8 parity rule applies — same
session identity).

**Cold-decision acceptance gate (Track A acceptance criterion, not optional).** Today the Live Activity
Approve/Reject `AppIntent` sets `openAppWhenRun = true` (`ApprovalActionIntent.swift:22`) and forwards via
`ApprovalRelay.shared`, whose `backendURL`/`sessionID`/`relayToken` are **runtime-populated instance vars**
(`ApprovalRelay.swift:73-77`, default empty) sourced from the live `DaemonChannel` handshake. The file
itself documents the cold-launch drain gap (`ApprovalRelay.swift:56-59`): if the app is killed, the queued
decision is never drained and lancerd's 120 s timeout auto-denies. That is a real correctness hole for the
away path this phase exists to fix. Track A must therefore prove and satisfy:
> **App fully killed → tap Live Activity Approve → the decision reaches `lancerd` over the relay → audit
> log shows `approve`** — without depending on a pre-warmed singleton.

To get there, `ApprovalRelay` must **hydrate its relay credentials (`backendURL`/`sessionID`/`relayToken`)
from durable storage** (Keychain/`AppDatabase`) at intent-perform time, not from in-memory singleton state
that only exists after a foreground connect. The persisted DB write + audit already happen unconditionally;
the missing piece is durable relay-credential hydration so the forward succeeds cold.

**Components touched:** `SessionFeature/LiveActivityManager.swift` (request with token, stream tokens),
`SessionFeature/ApprovalRelay.swift` (durable credential hydration for cold forward),
`LancerLiveActivityWidget` (unchanged rendering; it already renders `ContentState`),
`Lancer/LancerApp.swift` (token registration alongside the existing APNs device-token path),
`daemon/push-backend` (ActivityKit APNs sender with the strict contract above + token store).

**Error handling:** push disabled / token absent → fall back to the current local-update behavior (no regression). Stale-date already set (30 min); keep it as the safety net.

### 2.3 Track C — Watch polish/wiring (Phase 2)
Make the existing Watch views (`LancerWatch/`: `InboxListView`, `ApprovalDetailView`, `SessionStatusView`,
`ActivityFeedView`, `SnippetRunnerView`) fully live over the current WCSession bridge
(`PhoneWatchConnector` ↔ `WatchConnector`/`WatchStore`):
- Verify the decision round-trip (watch Approve/Reject → `onDecision` → `ApprovalRelay.forwardDecisionOnly` → relay) actually resolves the gate and reflects back on the watch.
- Live status/approval count updates (not just on-open).
- Tighten `InboxCountWidget` (watch complication-style count).

No new surfaces. This de-risks Track B by proving the watch decision path before adding independence.

### 2.4 Track B — Watch-away approval (Phase 5 **spike**, not a committed build)
**Goal:** approve/reject from the wrist with **no phone nearby**.
**Why a spike, not a phase:** today `WatchConnector.send(...)` only delivers a decision
`if WCSession.default.isReachable` and **drops it silently otherwise** (`WatchConnector.swift:42-45`) — so
there is no wrist-only path at all right now. Apple *does* support independent watch apps with their own
APNs + watch `URLSession`, but every load-bearing piece below is unverified on watchOS 27. Treat this as a
time-boxed feasibility spike whose **exit criterion is a real test with the phone unavailable**; it only
graduates to a committed phase if the spike passes.

**Spike must verify, each independently:**
- Independent **watch APNs token registration** (watch app gets + registers its own device token).
- The correct **watch-bundle APNs topic** for the watch extension (distinct from the phone's).
- **Watch-scoped relay auth** — the watch posts decisions to `push-backend` over `URLSession`; how it
  authenticates without the phone's `DaemonChannel` handshake (durable watch-side credential, mirroring the
  cold-decision hydration in §2.2).
- **Dedupe** between watch pushes and phone pushes for the same approval (first-decision-wins already holds
  in `ApprovalRelay`, but the watch path must not double-resolve or race).
- A **real device test with the paired phone powered off / in airplane mode** — the actual gap this closes.

**Fallback (if the spike passes):** when the phone *is* reachable, prefer the WCSession path (Track C) for
latency; use the independent watch path only when the phone is absent.

### 2.5 Testing (#4)
- Unit: `ContentState` push-payload encode/decode incl. the **`Date` encoding pin** (extend
  `LiveActivityContentStateTests`).
- Backend: ActivityKit APNs payload shape (topic/`event`/`timestamp`/content-state) + token store + the
  **payload-redaction policy** from §2.6 (Go tests, `daemon/push-backend`).
- Manual/device: **cold-decision acceptance** (app killed → Live Activity Approve → audit shows approve);
  app-closed Live Activity update on real device (extends the Phase-5c device runbook); watch-away decision
  with phone in airplane mode (Track B spike exit test).

### 2.6 APNs / Live-Activity payload privacy (Track A, ships with Phase 1)
The current alert push sets the APNs body to the **raw command** (`push-backend/main.go:371
body := ev.Command`). That puts agent command text — potentially file paths, source snippets, or secrets —
on the **lock screen**, directly undercutting the "your code stays on your host" promise. Track A adds an
explicit payload policy applied to **both** the alert push and the Live Activity `content-state`:
- **Redact/truncate** the command in any pushed payload — send a short, non-sensitive summary (e.g.
  `"Bash · write to 3 files"` or a risk + tool-category label), never the full command line.
- **Never** put source snippets, file contents, env values, or anything secret-shaped in an APNs alert
  body or in `ContentState`.
- Sensitive detail is revealed **only after device unlock** in-app — the push/Live Activity carries an
  identifier + safe summary; the app fetches the full request over the relay once unlocked.
- Applies to push-to-start payloads too (a remotely-started Live Activity must start with the redacted
  summary, not the raw command).

---

## 3. #2 — Voice cockpit

### 3.0 Starting point — legacy dictation exists; no governed cockpit
Voice is **not** a greenfield. `SessionFeature/DictationEngine.swift` already ships a working
`SFSpeechRecognizer` + `AVAudioEngine` push-to-talk transcriber (`DictationEngine.swift:11`), with mic/speech
permission strings and composer UI. What's missing is a **governed, two-way voice cockpit** — not basic
dictation. So this phase **migrates `DictationEngine` into `VoiceKit`** and builds on top of it; it does
**not** stand up a second, parallel voice stack. The legacy engine becomes the iOS-recognizer fallback path
inside `VoiceKit` (§3.2).

### 3.1 Three layers (market parity + governance-unique)
1. **Push-to-talk dictation** (Claude `/voice` parity) — already mostly present via `DictationEngine`; hold-to-talk mic in the New Chat composer; on-device transcription drops text into the prompt/follow-up. Feeds existing `performDispatch` / `continueRun`.
2. **Two-way conversational voice** (Omnara/Happy parity) — a `VoiceSession`: speak → dispatch/continue → the run's streamed output is read back via TTS → speak the next turn. Hands-free loop over the existing run/transcript stream.
3. **Voice approve/reject** (Lancer-unique, **constrained**) — when a governance gate fires, voice may **read the request aloud**, accept a spoken **reject**, or **open the approval UI**. Voice **must never resolve a `critical`-risk gate** — see §3.4. Off by default; an ambiguous/low-confidence transcription never resolves any gate (fails to manual).

### 3.2 APIs (verified 2026-06-19) + platform fallback
- **STT (on-device, primary):** `SpeechAnalyzer` + `SpeechTranscriber` (modern stack, strong for live/long-form). Manage models via `AssetInventory` / `AssetInstallationRequest`.
- **STT fallback / platform caveat:** per Apple's WWDC25 material `SpeechTranscriber` is **iOS-focused and not available on watchOS**, and model availability varies. `VoiceKit` must define a fallback chain: `SpeechAnalyzer`/`SpeechTranscriber` on iOS → `DictationTranscriber` / the legacy `SFSpeechRecognizer` path (the migrated `DictationEngine`) where the modern stack is unavailable. **No standalone watch voice** unless separately verified on watchOS 27 (it is out of scope for this phase).
- **TTS:** `AVSpeechSynthesizer` (AVFoundation).
- **Differentiator:** audio is transcribed **on-device — it never leaves the phone**, unlike Claude `/voice` (streams audio to Anthropic). Reinforces the "your data stays put" moat; state this in marketing.

### 3.3 Components
- **`VoiceKit`** — new engine module (no UIKit/SwiftUI, per module discipline) that **absorbs the existing `DictationEngine`**: a `SpeechAnalyzer` wrapper with the §3.2 fallback chain, an `AVSpeechSynthesizer` wrapper, and a `VoiceSession` state machine (idle → listening → transcribing → dispatched → speaking → listening). Sendable, cancellable. Unit-testable with a transcript fixture (no live mic).
- **`VoiceFeature`** — thin UI: a composer mic button + a full-screen voice mode; routes transcripts into the existing dispatch path and reads back run output. Depends on `VoiceKit` + `AgentKit` types only; routes through `AppFeature` like every other feature.
- **Wiring:** reuse `performDispatch` / `continueRun` (`AppRoot`) and the inbox decision path; voice-approve calls the same `ApprovalRelay.forwardDecisionOnly` chokepoint.

### 3.4 Safety / error handling — voice-approve is constrained, critical is hard-blocked
- Mic + speech permission prompts; degrade to text silently if denied.
- **`critical`-risk gates: voice approve is DISALLOWED entirely.** No spoken phrase — and no re-confirmation — can resolve a `critical` gate. For critical, voice may only read the card aloud, accept a spoken **reject**, or **open the approval UI**; the actual approval requires **visual review + biometric/passcode** in-app. This is the trust posture Lancer owns; it is non-negotiable and enforced in the gate path, not just the UI.
- **Non-critical gates:** voice-approve is a Settings opt-in (Security section), default off; low STT confidence → no decision, surface in Inbox.
- All decisions still flow through the normal gate/audit path (voice is an input method, not a bypass).

### 3.5 Testing (#2)
- `VoiceKit` unit tests: `VoiceSession` transitions; transcript→intent mapping; confidence gating (a low-confidence "approve" must NOT resolve a gate); the §3.2 fallback chain selection.
- **Critical hard-block test:** a high-confidence spoken "approve" against a `critical` gate must NOT resolve it (must route to visual+biometric). This is a security invariant, not a UI nicety.
- No real mic/network (per testing rules).

---

## 4. #1 — Drift detection (deterministic MVP ships; behavioral is advisory + gated)

Daemon-side, leveraging `lancerd`'s existing position: it already sees each agent's config surface and
records tool calls in the audit log. **Split deliberately by confidence:** the deterministic detectors
(config inventory + policy coverage) ship as the **Phase-3 Drift MVP** — they have no false-positive risk
and are the governance moat. The behavioral / natural-language-contradiction detector is **deferred to
Phase 5, stays advisory, and is blocked on an audit-schema expansion** (§4.3). Do not overclaim behavioral
drift on the current data.

### 4.1 Drift MVP — deterministic (Phase 3)
1. **Config inventory + consistency (Blume parity).** Parse each agent's config surface — `CLAUDE.md`, `AGENTS.md`, cursor rules, hook `settings.json`, installed skills, MCP config — into a normalized model. Snapshot it (hash + stored prior). Flag (a) **deterministic** internal contradictions and (b) unexpected changes since the last snapshot. Natural-language "this instruction contradicts that one" detection is **advisory only** and lives in Phase 5 — the MVP flags structural/diffable facts, not NL semantics.
2. **Policy-coverage (Lancer-unique).** Cross-check that config against `policy.yaml` + `policy-always.yaml`: warn when a dangerous tool category would auto-run **ungated**, when an allow-always rule is broader than intended, or when a hook that should gate is missing/disabled. Fully deterministic. This is the governance-aware layer Blume structurally can't do.

### 4.2 Behavioral drift (Phase 5, advisory) — blocked on audit-schema expansion
**Blocker (verified):** behavioral drift wants to compare *actual tool calls* (paths, tool input, network
destinations) against *declared scope*. The current audit schema **does not persist those fields** —
`AuditEntry` (`daemon/lancerd/audit.go:15`) records only `timestamp/action/agent/kind/command/effect/rule/
approvalId/hash/prevHash`. There is no `path`, no structured `toolInput`, no `networkDest`. So behavioral
drift requires an **audit-schema expansion first** (add the fields, preserve the hash-chain compatibility,
migrate the reader). Until that lands and false-positives are measured against real audit data, behavioral
contradiction detection ships **advisory only** (surfaces a soft signal, never a hard gate, never auto-acts).

### 4.3 Components
- **`drift` package in `lancerd`** — config parsers, the deterministic detectors (MVP), the snapshot store (`~/.lancer/drift/`), and later the behavioral detector. Pure Go, unit-tested with config fixtures.
- **Audit-schema expansion** (Phase 5 prerequisite) — new `path`/`toolInput`/`networkDest` fields on `AuditEntry` + payload, hash-chain-compatible, with reader migration. Lands before behavioral drift.
- **RPC + push** — `agent.drift.scan` (on demand / scheduled) and an unsolicited `agent.drift.alert` over the relay (same transport as `agent.approval.pending`).
- **Phone surface** — a "drift" finding card (severity-tagged, like approvals) in an alerts/inbox surface; tap → detail (what drifted, the diff, suggested fix). Reuses the existing relay→inbox plumbing.

### 4.4 Testing (#1)
- Go unit tests per deterministic detector with config fixtures (lancerd test pattern). A known config-vs-policy gap fixture must flag; a clean config must not (zero false positives — deterministic).
- Behavioral detector (Phase 5): tested against audit-log fixtures **after** the schema expansion; a measured false-positive rate is an acceptance gate before it leaves advisory mode.

---

## 5. Cross-cutting / shared

- **Transport:** all three surface to the phone over the **E2E relay** (+ APNs for #4 and the away-paths). None introduce an SSH dependency.
- **Module discipline:** `VoiceKit` is an engine (no UI); `VoiceFeature` is UI-only and routes through `AppFeature`. The `drift` package stays inside `lancerd`. No feature-to-feature deps.
- **Security:** voice is on-device; **voice-approve is DISALLOWED for `critical` gates entirely** (visual + biometric required) and opt-in/default-off for non-critical; pushed payloads are **redacted** (no command text/snippets/secrets on the lock screen — §2.6); drift findings are read-only signals (never auto-modify config); cold + watch-away decisions hydrate relay credentials from durable storage and flow through the same gate/audit chokepoint.
- **Verification gate (per `lancer-verification-gate`):** LancerKit changes → `swift build` + app-target XcodeBuildMCP build; lancerd changes → `go test ./...` from `daemon/lancerd`; device-only paths (Live Activity push, watch-away, mic) → real-device test, not simulator.

## 6. Open questions / risks (resolve at plan time)
1. **watchOS 27 independent connectivity** (Track B **spike**, §2.4) — independent watch APNs token, watch-bundle topic, background URLSession, watch-scoped relay auth, dedupe, reachability without the phone. **Spike exit = a real test with the phone powered off.** Track B does not become a committed phase until this passes.
2. **ActivityKit push contract + frequent-push budget** (§2.2, §2.6) — pin the `content-state` `Date` encoding (a mismatch drops updates silently); confirm `apns-topic = <bundle>.push-type.liveactivity`, the `timestamp`/`event` payload shape, priority-10 liveactivity throttling, and the `frequentPushesEnabled` UX.
3. **Behavioral-drift prerequisite + false-positive rate** (§4.2) — requires the audit-schema expansion (`path`/`toolInput`/`networkDest`) **before** it can run at all; stays advisory until a false-positive rate is measured on real audit data. Ship the deterministic config+policy MVP (Phase 3) first.
4. **Voice-approve liability — RESOLVED 2026-06-19:** voice-approve is **disallowed for `critical` gates entirely** (visual + biometric required), opt-in/default-off for non-critical. Enforce in the gate path, not just UI (§3.4).
5. **APNs payload privacy — RESOLVED 2026-06-19 (§2.6):** no raw command/snippets/secrets in any pushed payload; redacted summary + post-unlock fetch. Replaces the current `body := ev.Command` behavior.
