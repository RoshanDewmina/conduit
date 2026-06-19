# Design — Voice cockpit, Live-Activity/Watch reach, and Drift detection

**Date:** 2026-06-19 · **Status:** approved design, pre-implementation-plan
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
- **#2 Voice** — market table-stakes. Happy & Omnara ship *two-way voice*; Claude Code ships push-to-talk `/voice`. Conduit has none.
- **#4 Watch / Live Activity / Dynamic Island** — **~80% built already** (full Live Activity + Dynamic Island with interactive Approve/Reject AppIntents; Watch app with 6 views + WCSession sync). The gap is that it doesn't work **while the app is closed / phone is away** — exactly when it matters.
- **#1 Drift detection** — *offense*. Blume (blume.codes) is staking out agent-config oversight; `conduitd` already sits in the hook path and sees policy + every tool call, so Conduit can do drift detection **better** and on the phone.

**Non-goal:** connection-resilience / Mosh / cloud-migration — a *non-gap* given the resident-daemon + relay model (the phone never holds the session). Do not build for it.

## 1. Sequencing (approved)

| Phase | Feature | Why here | Rough size |
|---|---|---|---|
| **1** | #4 **Track A** — Live Activity push-update reliability | Smallest, rides the in-flight Phase-5c APNs/relay work, highest daily payoff (makes what's built actually work away from the app) | S–M |
| **2** | #4 **Track C** — Watch polish/wiring | Small; tighten the 6 existing Watch views (live updates + decision round-trip) over the current WCSession path before adding independence | S |
| **3** | #2 **Voice cockpit** | Market parity; medium build; new `VoiceKit` engine + `VoiceFeature` UI | M–L |
| **4** | #4 **Track B** — Watch-away approval | Heavier (independent watch APNs + URLSession to the relay; watchOS-27 entitlement/background verification); do after the WCSession path is solid | M |
| **5** | #1 **Drift detection** (config → policy → behavioral) | Largest + most novel; itself internally phased | L |

Phases are independently shippable. Order is movable — lead with Phase 5 instead if pressing the governance moat becomes the priority.

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
- Keep the existing local `update(...)` path as a foreground fast-path; push is the away path. The two must converge on the same `ContentState` (single source of truth in `ConduitLiveActivityManager`).

**Backend:** `push-backend` gains an APNs path for ActivityKit (`apns-push-type: liveactivity`, the activity's content-state JSON). Reuses the existing `.p8`/APNs config. New endpoint to register/refresh activity + push-to-start tokens, keyed by the same `sessionId` used for the alert-push token (the MAJOR-8 parity rule applies — same session identity).

**Components touched:** `SessionFeature/LiveActivityManager.swift` (request with token, stream tokens), `ConduitLiveActivityWidget` (unchanged rendering; it already renders `ContentState`), `Conduit/ConduitApp.swift` (token registration alongside the existing APNs device-token path), `daemon/push-backend` (ActivityKit APNs sender + token store).

**Error handling:** push disabled / token absent → fall back to the current local-update behavior (no regression). Stale-date already set (30 min); keep it as the safety net.

### 2.3 Track C — Watch polish/wiring (Phase 2)
Make the existing Watch views (`ConduitWatch/`: `InboxListView`, `ApprovalDetailView`, `SessionStatusView`,
`ActivityFeedView`, `SnippetRunnerView`) fully live over the current WCSession bridge
(`PhoneWatchConnector` ↔ `WatchConnector`/`WatchStore`):
- Verify the decision round-trip (watch Approve/Reject → `onDecision` → `ApprovalRelay.forwardDecisionOnly` → relay) actually resolves the gate and reflects back on the watch.
- Live status/approval count updates (not just on-open).
- Tighten `InboxCountWidget` (watch complication-style count).

No new surfaces. This de-risks Track B by proving the watch decision path before adding independence.

### 2.4 Track B — Watch-away approval (Phase 4)
**Goal:** approve/reject from the wrist with **no phone nearby**.
**Approach:** the Watch app registers its **own** APNs token with the relay and posts decisions back over
**`URLSession`** directly to `push-backend`, independent of WCSession.
- Watch receives an approval as a push (or fetches pending from the relay on activation).
- Watch posts the decision to the relay; relay forwards to `conduitd` (same chokepoint as the phone).
- ⚠️ **watchOS 27 verification required at plan time:** independent watch APNs entitlement, background
  URLSession on watch, reachability when the paired phone is offline, and relay-auth from the watch.
  These gate the design — confirm via `apple-docs` + a device test before committing the plan.

**Fallback:** when the phone *is* reachable, prefer the WCSession path (Track C) for latency; use the
independent path only when the phone is absent.

### 2.5 Testing (#4)
- Unit: `ContentState` push-payload encode/decode (mirror existing `LiveActivityContentStateTests`).
- Backend: ActivityKit APNs payload shape + token store (Go tests, `daemon/push-backend`).
- Manual/device: app-closed Live Activity update on real device (extends the Phase-5c device runbook); watch-away decision with phone in airplane mode.

---

## 3. #2 — Voice cockpit

### 3.1 Three layers (market parity + governance-unique)
1. **Push-to-talk dictation** (Claude `/voice` parity) — hold-to-talk mic in the New Chat composer; on-device transcription drops text into the prompt/follow-up. Feeds existing `performDispatch` / `continueRun`.
2. **Two-way conversational voice** (Omnara/Happy parity) — a `VoiceSession`: speak → dispatch/continue → the run's streamed output is read back via TTS → speak the next turn. Hands-free loop over the existing run/transcript stream.
3. **Voice approve/reject** (Conduit-unique) — when a governance gate fires, optionally read the request aloud and accept a spoken "approve/reject". **Off by default**; **critical-risk actions always require explicit re-confirmation**; an ambiguous/low-confidence transcription never resolves a gate (fails to manual).

### 3.2 APIs (verified 2026-06-19)
- **STT (on-device):** `SpeechAnalyzer` + `SpeechTranscriber` (modern stack; `DictationTranscriber` / `SpeechDetector` available). Manage models via `AssetInventory` / `AssetInstallationRequest`.
- **TTS:** `AVSpeechSynthesizer` (AVFoundation).
- **Differentiator:** audio is transcribed **on-device — it never leaves the phone**, unlike Claude `/voice` (streams audio to Anthropic). Reinforces the "your data stays put" moat; state this in marketing.

### 3.3 Components
- **`VoiceKit`** — new engine module (no UIKit/SwiftUI, per module discipline): a `SpeechAnalyzer` wrapper, an `AVSpeechSynthesizer` wrapper, and a `VoiceSession` state machine (idle → listening → transcribing → dispatched → speaking → listening). Sendable, cancellable. Unit-testable with a transcript fixture (no live mic).
- **`VoiceFeature`** — thin UI: a composer mic button + a full-screen voice mode; routes transcripts into the existing dispatch path and reads back run output. Depends on `VoiceKit` + `AgentKit` types only; routes through `AppFeature` like every other feature.
- **Wiring:** reuse `performDispatch` / `continueRun` (`AppRoot`) and the inbox decision path; voice-approve calls the same `ApprovalRelay.forwardDecisionOnly` chokepoint.

### 3.4 Safety / error handling
- Mic + speech permission prompts; degrade to text silently if denied.
- Voice-approve is a Settings opt-in (Security section), default off; critical-risk → spoken confirmation required ("Say 'confirm reject' to proceed"); low STT confidence → no decision, surface in Inbox.
- All decisions still flow through the normal gate/audit path (voice is an input method, not a bypass).

### 3.5 Testing (#2)
- `VoiceKit` unit tests: `VoiceSession` transitions; transcript→intent mapping; confidence gating (a low-confidence "approve" must NOT resolve a gate). No real mic/network (per testing rules).

---

## 4. #1 — Drift detection (config + policy + behavioral)

### 4.1 Approach
Daemon-side, leveraging `conduitd`'s existing position: it already sees each agent's config surface and
records every tool call + effect in the audit log. Three detectors, internally phased.

1. **Config-consistency (Blume parity).** Parse each agent's config surface — `CLAUDE.md`, `AGENTS.md`, cursor rules, hook `settings.json`, installed skills, MCP config — into a normalized model. Snapshot it (hash + stored prior). Flag (a) internal contradictions (e.g. a rule that contradicts `CLAUDE.md`), and (b) unexpected changes since the last snapshot.
2. **Policy-coverage (Conduit-unique).** Cross-check that config against `policy.yaml` + `policy-always.yaml`: warn when a dangerous tool category would auto-run **ungated**, when an allow-always rule is broader than intended, or when a hook that should gate is missing/disabled. This is the governance-aware layer Blume structurally can't do.
3. **Behavioral.** Mine `audit.log` (already JSONL of every tool call + effect): flag when actual tool calls diverge from declared scope — paths/network/commands outside what the agent's config implies. Heuristic + thresholded; surfaces "this agent did X, which its config didn't anticipate."

### 4.2 Components
- **`drift` package in `conduitd`** — config parsers, the three detectors, and a snapshot store (`~/.conduit/drift/`). Pure Go, unit-tested with config fixtures.
- **RPC + push** — `agent.drift.scan` (on demand / scheduled) and an unsolicited `agent.drift.alert` over the relay (same transport as `agent.approval.pending`).
- **Phone surface** — a "drift" finding card (severity-tagged, like approvals) in an alerts/inbox surface; tap → detail (what drifted, the diff, suggested fix). Reuses the existing relay→inbox plumbing.

### 4.3 Testing (#1)
- Go unit tests per detector with config + audit-log fixtures (conduitd test pattern). A known-contradiction fixture must flag; a clean config must not (no false positives).

---

## 5. Cross-cutting / shared

- **Transport:** all three surface to the phone over the **E2E relay** (+ APNs for #4 and the away-paths). None introduce an SSH dependency.
- **Module discipline:** `VoiceKit` is an engine (no UI); `VoiceFeature` is UI-only and routes through `AppFeature`. The `drift` package stays inside `conduitd`. No feature-to-feature deps.
- **Security:** voice is on-device; voice-approve is opt-in + re-confirmed for critical; drift findings are read-only signals (never auto-modify config); watch-away decisions flow through the same gate/audit chokepoint.
- **Verification gate (per `conduit-verification-gate`):** ConduitKit changes → `swift build` + app-target XcodeBuildMCP build; conduitd changes → `go test ./...` from `daemon/conduitd`; device-only paths (Live Activity push, watch-away, mic) → real-device test, not simulator.

## 6. Open questions / risks (resolve at plan time)
1. **watchOS 27 independent connectivity** (Track B) — entitlements, background URLSession, push without phone. **Must verify before committing the Track B plan** (apple-docs + device test).
2. **ActivityKit frequent-push budget** — APNs rate limits for liveactivity pushes; confirm `frequentPushesEnabled` UX and throttling.
3. **Behavioral-drift false-positive rate** (#1.3) — needs a tuning pass; ship config + policy layers first, gate behavioral behind them.
4. **Voice-approve liability** — confirm the default-off + critical-reconfirm policy is sufficient; consider disallowing voice-approve for `critical` entirely.
