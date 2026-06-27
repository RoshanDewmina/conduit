# Parallel handoff prompts — voice/Live-Activity/drift + opencode gating

**Date:** 2026-06-19 · For dispatch to 5 parallel Sonnet agents.
**Source spec:** `docs/superpowers/specs/2026-06-19-voice-liveactivity-drift-design.md` (read it first).
**Merge owner / verifier:** Claude (me). I own `AppRoot.swift` wiring and the final app-target build.

---

## Parallel-safety map (READ BEFORE DISPATCHING)

The one hard rule: **no two agents write the same file.** Ownership is partitioned so all five can run
at once. Three coordination points:

1. **`AppRoot.swift` is OFF-LIMITS to every lane.** Lanes B, C, D each need a one-time wiring hook into it.
   Instead of editing it, each lane **exposes its entry point and reports the exact wiring needed**; I do the
   `AppRoot.swift` integration as merge owner after lanes land. This avoids the worst collision.
2. **`daemon/lancerd` is shared by lanes C and E**, but on **different files**: C touches `server.go` /
   router registration only; E touches `dispatch.go` only. Neither may touch the other's file. Both report
   any shared-routing-file lines they changed.
3. **`Package.swift` + `project.yml` are owned by lane D only** (it adds the new targets). No other lane
   edits build manifests.

| Lane | Phase | Write scope (exclusive) | Shared/hot — coordinate |
|---|---|---|---|
| **A** | 1 — Track A | `SessionFeature/LiveActivityManager.swift`, `SessionFeature/ApprovalRelay.swift`, `Lancer/LancerApp.swift`, `daemon/push-backend/*` (new ActivityKit sender + token store; edit `main.go` push path) | none with other lanes |
| **B** | 2 — Track C | `LancerWatch/*`, `AppFeature/PhoneWatchConnector.swift` | report AppRoot wiring; do NOT edit AppRoot |
| **C** | 3 — Drift MVP | `daemon/lancerd/drift/*` (new), lancerd RPC registration, new iOS drift-card view | `lancerd/server.go` (vs E uses dispatch.go); report AppRoot wiring |
| **D** | 4 — Voice | new `Packages/LancerKit/Sources/VoiceKit/*` + `VoiceFeature/*`, `Package.swift`, `project.yml`, migrate `SessionFeature/DictationEngine.swift` + its uses in `SessionView.swift` | report AppRoot wiring |
| **E** | — opencode gating | `daemon/lancerd/dispatch.go`, new opencode plugin file | `lancerd` shared with C (different file) |

**Deferred — do NOT dispatch yet:** Phase 5 (behavioral drift + Track B watch-away spike). Behavioral drift
is blocked on the audit-schema expansion; Track B is a watchOS-27 feasibility spike. Both wait until A/B/C land.

Every lane gets these constraints (from `docs/agent-contract.md` + CLAUDE.md):
- Other agents are editing this repo concurrently. **Never revert unrelated changes.** If you hit a
  conflicting local edit, adapt or report it — do not overwrite.
- Preserve module boundaries (`docs/agent-contract.md` §5). Engines have no UI; features route through `AppFeature`.
- V1 transport is the **E2E relay**, not SSH. These features ride the relay + APNs path.
- Build explicit argv arrays for any daemon agent launch — never `sh -c` with an interpolated prompt.
- Final response must list: files changed, checks run (with output), and the AppRoot wiring you need from the merge owner.

---

## LANE A — Phase 1, Track A: Live Activity push reliability + cold-decision gate + APNs privacy

```text
You are working in /Users/roshansilva/Documents/command-center, one of several agents editing this repo
in parallel. Do not revert changes you didn't make.

Read first:
- docs/superpowers/specs/2026-06-19-voice-liveactivity-drift-design.md  (sections 2.1, 2.2, 2.5, 2.6 — your scope)
- docs/agent-contract.md (module boundaries; §5 single-byte-source rule)
- /Users/roshansilva/.hermes/knowledge-base/AGENTS.md
- The current code you are changing (read fully before editing):
    Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift
    Packages/LancerKit/Sources/SessionFeature/ApprovalRelay.swift
    Lancer/LancerApp.swift
    daemon/push-backend/main.go  (pushApproval, around line 350-400)

Objective: make the Live Activity update reliably while the app is closed/away, satisfy a cold-decision
acceptance gate, and stop leaking command text to the lock screen. Three pieces:

1. Push-driven Live Activity (LiveActivityManager.swift):
   - Request the activity with pushType: .token (not nil). Consume Activity.pushTokenUpdates to get/refresh
     the per-activity push token; register {activityToken, sessionId} with push-backend.
   - Register a push-to-start token via Activity.pushToStartToken / pushToStartTokenUpdates so an approval can
     remotely START an activity when none is running.
   - Observe ActivityAuthorizationInfo.frequentPushesEnabled; degrade gracefully when off.
   - Keep the existing local update(...) path as the foreground fast-path. Both paths converge on the same
     ContentState. Token registration in Lancer/LancerApp.swift alongside the existing APNs device-token flow.

2. push-backend ActivityKit sender (new file daemon/push-backend/liveactivity.go + token store; edit main.go
   only to route approval/status changes through it). STRICT contract — updates fail SILENTLY if wrong:
   - apns-topic = "<bundleID>.push-type.liveactivity"  (NOT the bare bundle id).
   - apns-push-type: liveactivity, apns-priority 10.
   - Payload has aps.timestamp (unix secs), aps.event ("update"|"end"), aps.content-state decoding EXACTLY
     into LancerSessionAttributes.ContentState.
   - ContentState.lastUpdate is a Swift Date — encode it the way ActivityKit's default JSONDecoder expects.
     A date-format mismatch drops the whole update. Pin this and add a Go unit test asserting the exact bytes.

3. APNs payload privacy (push-backend main.go pushApproval + the new sender):
   - main.go currently sets the alert body to the raw command (body := ev.Command). Replace with a REDACTED
     summary (risk + tool/category label, e.g. "Bash · writes 3 files") — never the full command line.
   - Never put source snippets, file contents, env values, or secrets in any APNs alert body or in
     ContentState. Push carries an identifier + safe summary only; full detail is fetched in-app post-unlock.
   - Apply the same redaction to push-to-start payloads.

4. Cold-decision acceptance gate (ApprovalRelay.swift):
   - Today backendURL/sessionID/relayToken are runtime-populated instance vars (default empty), set only after
     a foreground connect — so a decision tapped from a killed-app Live Activity can't forward (see the
     documented gap at ApprovalRelay.swift:56-59). Make ApprovalRelay HYDRATE these credentials from durable
     storage (Keychain / AppDatabase) at enqueue/forward time, so a cold forward succeeds. Do not change the
     DB-write-first / first-decision-wins semantics.

Owned files (edit only these): LiveActivityManager.swift, ApprovalRelay.swift, Lancer/LancerApp.swift,
daemon/push-backend/* (new liveactivity.go + token store + minimal main.go push-path edits).
Do NOT edit: AppRoot.swift, any lancerd file, any Watch/Voice/drift file, Package.swift, project.yml.

Acceptance checks (run and paste output):
- cd Packages/LancerKit && swift build   (zero errors)
- cd daemon/push-backend && go build ./... && go test ./...   (incl. your new Date-encoding test)
- Extend Packages/LancerKit/Tests for ContentState push-payload encode/decode incl. the Date pin.
Device-only items I (merge owner) will verify, just flag them: app-killed Live Activity update on a real
device, and the cold-decision gate (kill app → tap Approve → audit shows approve).

Final response: files changed; check output; confirm no command text remains in any pushed payload; and the
exact LancerApp/AppRoot token-registration wiring you need.
```

---

## LANE B — Phase 2, Track C: Watch polish / wiring (WCSession path)

```text
You are working in /Users/roshansilva/Documents/command-center, one of several agents editing this repo
in parallel. Do not revert changes you didn't make.

Read first:
- docs/superpowers/specs/2026-06-19-voice-liveactivity-drift-design.md  (section 2.3 — your scope; 2.4 is NOT
  your scope, it's a deferred spike)
- docs/agent-contract.md
- The current code (read fully): LancerWatch/ (all views + WatchConnector + WatchStore),
  Packages/LancerKit/Sources/AppFeature/PhoneWatchConnector.swift

Objective: make the 6 existing Watch views fully live over the CURRENT WCSession bridge — no independent
watch APNs (that's the deferred Track B spike). Specifically:
- Verify and fix the decision round-trip: watch Approve/Reject → WatchConnector.sendDecision →
  PhoneWatchConnector → ApprovalRelay.forwardDecisionOnly → relay → lancerd → result reflects back on the
  watch. (Note WatchConnector.send() currently drops a message silently if !isReachable — that's expected for
  this WCSession-only phase; just ensure reachable-path correctness, do NOT add an independent APNs path.)
- Live status + pending-approval-count updates pushed to the watch (not only on-open).
- Tighten InboxCountWidget (the watch count complication/surface).

Owned files (edit only these): LancerWatch/*, AppFeature/PhoneWatchConnector.swift.
Do NOT edit: AppRoot.swift (report any wiring you need), ApprovalRelay.swift (lane A owns it — if you need a
new method on it, describe the signature and let the merge owner add it), any push-backend/lancerd/Voice/
drift file, Package.swift, project.yml.

Acceptance checks (run and paste output):
- cd Packages/LancerKit && swift build   (zero errors)
- Add/extend WatchStore/connector unit tests for the decision encode/decode + count update.
Device/paired-sim items I will verify, just flag: live watch round-trip with the phone reachable.

Final response: files changed; check output; the AppRoot/PhoneWatchConnector wiring you need; and any
ApprovalRelay method signature you need lane A to add.
```

---

## LANE C — Phase 3: Drift MVP (deterministic config inventory + policy coverage)

```text
You are working in /Users/roshansilva/Documents/command-center, one of several agents editing this repo
in parallel. Do not revert changes you didn't make.

Read first:
- docs/superpowers/specs/2026-06-19-voice-liveactivity-drift-design.md  (section 4 — your scope is 4.1 + the
  deterministic parts of 4.3/4.4. Do NOT build behavioral drift (4.2) — it's deferred and needs an
  audit-schema expansion.)
- docs/agent-contract.md
- The current code (read fully): daemon/lancerd/server.go, daemon/lancerd/e2e_router.go,
  daemon/lancerd/approval.go (for how agent.approval.pending is pushed over the relay — mirror that),
  daemon/lancerd/policy*.go and the policy.yaml / policy-always.yaml format.

Objective: a deterministic drift detector in lancerd plus a phone card. ONLY the two zero-false-positive
detectors:
1. Config inventory + consistency: parse each agent's config surface (CLAUDE.md, AGENTS.md, cursor rules,
   hook settings.json, installed skills, MCP config) into a normalized model; snapshot (hash + prior) in
   ~/.lancer/drift/. Flag deterministic/structural changes since last snapshot. NO natural-language
   contradiction detection (that's deferred/advisory).
2. Policy-coverage: cross-check that config against policy.yaml + policy-always.yaml. Warn when a dangerous
   tool category would auto-run ungated, when an allow-always rule is broader than intended, or when a hook
   that should gate is missing/disabled. Fully deterministic.

Wiring:
- New package: daemon/lancerd/drift/ (pure Go; config parsers + the two detectors + snapshot store).
- RPC agent.drift.scan (on demand) and an unsolicited agent.drift.alert over the relay — register it the same
  way agent.approval.pending is. Make this registration edit MINIMAL and confined to server.go (lane E is in
  dispatch.go — do not touch dispatch.go). Report the exact lines you add to any shared routing file.
- New iOS drift-card view (new file under an existing alerts/inbox feature module): a severity-tagged finding
  card reusing the existing relay→inbox plumbing; tap → detail (what drifted, the diff, suggested fix).

Owned files (edit only these): daemon/lancerd/drift/* (new), minimal server.go RPC registration, one new
iOS view file for the drift card.
Do NOT edit: daemon/lancerd/dispatch.go (lane E), audit.go (behavioral is deferred), AppRoot.swift (report
wiring), any push-backend/Watch/Voice file, Package.swift, project.yml.

Acceptance checks (run and paste output):
- cd daemon/lancerd && go build ./... && go test ./...
- Add Go unit tests per detector with config fixtures: a known config-vs-policy gap must flag; a clean config
  must NOT flag (zero false positives — it's deterministic).
- cd Packages/LancerKit && swift build  (for the new card view).

Final response: files changed; check output; exact shared-routing-file lines you touched; the AppRoot/inbox
wiring you need.
```

---

## LANE D — Phase 4: Voice cockpit (migrate DictationEngine into VoiceKit + VoiceFeature)

```text
You are working in /Users/roshansilva/Documents/command-center, one of several agents editing this repo
in parallel. Do not revert changes you didn't make.

Read first:
- docs/superpowers/specs/2026-06-19-voice-liveactivity-drift-design.md  (section 3 — your scope)
- docs/agent-contract.md  (module boundaries: engines have NO UI; features route through AppFeature)
- The current code (read fully): Packages/LancerKit/Sources/SessionFeature/DictationEngine.swift,
  its use in SessionFeature/SessionView.swift, Packages/LancerKit/Package.swift, project.yml
- Use the apple-docs MCP before using any Speech API — verify current signatures for SpeechAnalyzer,
  SpeechTranscriber, DictationTranscriber, AVSpeechSynthesizer. Do NOT guess these APIs.

Objective: build a governed two-way voice cockpit by MIGRATING the existing DictationEngine into a new
VoiceKit engine — do NOT stand up a second parallel voice stack.

1. New module VoiceKit (engine, no UIKit/SwiftUI): absorb DictationEngine; wrap SpeechAnalyzer/
   SpeechTranscriber with a fallback chain (SpeechAnalyzer on iOS → DictationTranscriber / the legacy
   SFSpeechRecognizer path where unavailable; NO watchOS voice); wrap AVSpeechSynthesizer; a VoiceSession
   state machine (idle→listening→transcribing→dispatched→speaking→listening). Sendable, cancellable,
   unit-testable with a transcript fixture (no live mic).
2. New module VoiceFeature (UI-only, routes through AppFeature): composer mic button + full-screen voice
   mode; transcripts route into the existing dispatch path; run output read back via TTS.
3. Voice-approve SAFETY — non-negotiable, enforce in the gate path not just UI:
   - critical-risk gates: voice approve is DISALLOWED ENTIRELY. Voice may read the card, accept a spoken
     REJECT, or OPEN the approval UI — but NO spoken phrase (and no re-confirmation) resolves a critical
     gate. Critical approval requires visual review + biometric/passcode in-app.
   - non-critical gates: voice-approve is a Settings opt-in, default OFF. Low STT confidence → no decision,
     surface in Inbox. All decisions still flow through ApprovalRelay.forwardDecisionOnly (voice is an input
     method, never a bypass).

Build-manifest changes are YOURS exclusively: add the VoiceKit + VoiceFeature targets to
Packages/LancerKit/Package.swift AND to project.yml (run xcodegen if needed). No other lane edits these.

Owned files (edit only these): new Sources/VoiceKit/*, new Sources/VoiceFeature/*, Package.swift, project.yml,
SessionFeature/DictationEngine.swift (migrate/remove), SessionFeature/SessionView.swift (repoint to VoiceKit).
Do NOT edit: AppRoot.swift (report the routing wiring you need), ApprovalRelay.swift (lane A owns it — request
any new method by signature), any push-backend/lancerd/Watch/drift file.

Acceptance checks (run and paste output):
- cd Packages/LancerKit && swift build   (zero errors)
- VoiceKit unit tests: VoiceSession transitions; transcript→intent mapping; confidence gating; fallback-chain
  selection; and the CRITICAL HARD-BLOCK test — a HIGH-confidence spoken "approve" against a critical gate
  must NOT resolve it (routes to visual+biometric). This is a security invariant.
Device-only (mic) items I will verify, just flag them.

Final response: files changed; check output; the AppRoot routing wiring you need; any ApprovalRelay method
signature you need from lane A.
```

---

## LANE E — opencode approval-gating fix (env-gated plugin)

```text
You are working in /Users/roshansilva/Documents/command-center, one of several agents editing this repo
in parallel. Do not revert changes you didn't make.

Read first:
- CLAUDE.md (the "Claude plans & verifies / opencode executes" section + the opencode 1.17.7 notes)
- .claude/skills/vendor-cli-adapter-audit/ (INVOKE this skill's checks; CLI flags drift — verify the
  installed version, don't trust docs)
- daemon/lancerd/dispatch.go  (read fully: agentArgv/continueArgv, realLauncher, how the opencode argv is
  built and launched — opencode is run as {"opencode","run","--format","json", ...})
- daemon/lancerd/hook.go + hook_install.go + opencode_hook.go  (opencode_hook.go is DEAD CODE built on a
  false premise — opencode 1.17.7 has NO hooks.json mechanism. Do not extend it.)
- daemon/lancerd/approval.go (how the agent-hook contract decides allow/deny)

Context / root cause (already diagnosed — verify, don't re-litigate): Claude Code dispatches gate through a
PreToolUse hook → lancerd policy engine. opencode dispatches do NOT — opencode 1.17.7 has no Claude-style
hooks; it uses PLUGINS (@opencode-ai/plugin) + a permission model. The installed opencode_hook.go is dead.

Objective: make opencode dispatches launched by lancerd gate their tool calls through lancerd approval,
WITHOUT gating the owner's own interactive opencode/Claude sessions.

Approach (verify each step against the installed opencode CLI before shipping):
1. Author an opencode plugin (JS, @opencode-ai/plugin) that implements tool.execute.before(input, output):
   it calls lancerd's agent-hook (the same agent-hook binary/contract Claude's PreToolUse uses — flags
   --agent --kind --command --cwd --risk --tool-name --session-id --tool-input; exit 0 = allow, non-zero =
   deny) and THROWS to block the tool when denied. Build explicit args — never sh -c with an interpolated
   prompt.
2. Gate it by env so it ONLY activates for lancerd-launched runs: the plugin no-ops unless an env var like
   LANCER_GATE=1 is set. In dispatch.go's realLauncher, set that env var (and point opencode at the plugin
   via an opencode.json whose `plugin: [...]` array has the ABSOLUTE plugin path — directory auto-discovery
   does NOT work in 1.17.7) ONLY on the lancerd-spawned opencode argv. The owner's interactive sessions,
   which don't set LANCER_GATE, are unaffected.
3. Do NOT regress the claudeCode or codex approval paths, and do NOT change continue/resume identity (Lancer
   gets a new runId; vendor session continuity lives underneath).

VERIFICATION IS THE POINT — the prior attempt shipped a dead hook. You MUST live-prove it:
- In a temp dir, run a lancerd-launched opencode dispatch with a harmless tool call and confirm an approval
  event appears in ~/.lancer/audit.log AND the tool blocks pending decision.
- Confirm an opencode run WITHOUT LANCER_GATE does NOT gate (owner session unaffected).
- If the openrouter model rate-limits your live test, STOP and report — do NOT ship unverified. Use
  openrouter/deepseek/deepseek-v4-flash if you need an executor, never the free tier.

Owned files (edit only these): daemon/lancerd/dispatch.go (realLauncher env + argv for opencode), new
opencode plugin file (place under the repo, e.g. tools/opencode-gate-plugin/, not the owner's
~/.config/opencode), and an opencode.json template if needed.
Do NOT edit: daemon/lancerd/server.go (lane C), any iOS/push-backend/Watch/Voice/drift file. Do not modify
the owner's ~/.config/opencode/opencode.json — if a config change is needed there, describe it and let the
owner apply it.

Acceptance checks (run and paste output):
- cd daemon/lancerd && go build ./... && go test ./...
- The live gating proof above (audit.log event + block, and the no-gate-without-env case).
- which opencode; opencode --version; and the targeted help output proving the flags/plugin-load you rely on.

Final response: files changed; the LIVE verification output (audit.log lines + the no-env case); any
~/.config/opencode change the owner must apply; risks.
```
