# Handoff — Lock-screen approval journey (shipped) + Governance panel (to design)

**Date:** 2026-06-19
**Author:** Claude (Opus) session
**For:** the next agent picking up frontend work on Conduit
**Repo:** `/Users/roshansilva/Documents/command-center` · GitHub `RoshanDewmina/conduit`

---

## 0. TL;DR

This session shipped the **lock-screen approval journey** (an expressive push-driven Live Activity +
an in-app reveal flow) and **wired the Live Activity push token registration** that the prior V1 work had
left dangling. Two PRs are open against `master`: **#5** (the journey) and **#6** (the token wiring).
Everything is app-target-build-green; the only unverified surface is on-device behavior (a simulator can't
issue ActivityKit push tokens or fire APNs).

The next piece of frontend work the owner wants is a **Governance / vendor-trust panel** — an in-app surface
that makes Conduit's now-complete "one policy engine governs every vendor (Claude/Codex/Kimi/opencode)" story
**legible**. It has been scoped but **not designed**: the one open decision is its *primary job*
(reassurance vs. control vs. audit). Section 5 below is the full brief to start it.

**Read first to get oriented:** `ARCHITECTURE.md` §0.1 (current-state snapshot) + §4.1 (sidebar IA).
The app home is a **sidebar / New Chat shell**, not a tab bar. V1 transport is the **blind E2E relay + APNs**,
never a phone-held SSH session.

---

## 1. What shipped this session

There were two layers of work: the **V1 reach work** (already merged to `origin/master`) and the
**lock-screen journey + token wiring** (open in PRs #5/#6). Listed oldest→newest.

### 1.1 V1 reach work — already on `origin/master` (pushed, commit `320952e1`)

These landed earlier in the session and were pushed to GitHub. They are the *substrate* the new frontend
work builds on. Each was implemented by a file-isolated Sonnet subagent, then merge-reviewed and
app-target-built.

| Feature | What it does | Key files |
|---|---|---|
| **opencode approval gating** | conduitd-dispatched `opencode` runs now gate every tool call through the policy engine (via a `CONDUIT_GATE=1`-guarded PreToolUse hook). Closes the prior bypass where only Claude Code gated. The owner's *interactive* opencode sessions stay ungated (no env var). **Live-verified** against `~/.conduit/audit.log` (auto-allow + auto-deny, hash-chain intact). | `daemon/conduitd/dispatch.go`, `docs/opencode-conduit-hook.sh` |
| **Push-driven Live Activity** | `LiveActivityManager` requests `pushType: .token`, streams `pushTokenUpdates` + `pushToStartTokenUpdates`, so the lock-screen / Dynamic Island update **while the app is closed** (was local-update-only → stale when backgrounded). New ActivityKit APNs sender on the backend with the strict contract (`<bundle>.push-type.liveactivity` topic, pinned `Date` encoding). | `Packages/ConduitKit/Sources/SessionFeature/LiveActivityManager.swift`, `daemon/push-backend/liveactivity.go` |
| **APNs payload privacy** | The alert body no longer carries the raw command (`body := ev.Command` removed). Redacted risk/tool summary only; full detail fetched in-app post-unlock. | `daemon/push-backend/main.go`, `liveactivity.go` (`redactSummary`) |
| **Cold-decision gate** | `ApprovalRelay` hydrates relay credentials from Keychain at decision time so an Approve tapped from a **killed-app** Live Activity forwards to conduitd (previously the singleton creds were empty cold → decision dropped → 120s auto-deny). | `Packages/ConduitKit/Sources/SessionFeature/ApprovalRelay.swift` |
| **Watch WCSession polish** | `PhoneWatchConnector` pushes live `agentActive`/`pendingCount`/uptime (were hardcoded stubs); `InboxCountWidget` gained `.accessoryRectangular` + VoiceOver labels. | `ConduitWatchWidget/InboxCountWidget.swift`, `Packages/ConduitKit/Sources/AppFeature/PhoneWatchConnector.swift` |
| **Secure activity-token RPC** | `DaemonChannel.registerActivityToken` → conduitd RPC `conduit.device.register.activity` → push-backend. conduitd holds `APPROVAL_RELAY_SECRET`; the app never does. (The *subscriber* that calls this was the dangling end — see §1.3.) | `Packages/ConduitKit/Sources/SSHTransport/DaemonChannel.swift`, `daemon/conduitd/server.go:975` |

### 1.2 Lock-screen approval journey — **PR #5** (`feat/lockscreen-approval-journey`, OPEN)

The first deliberate *frontend cycle* for the push work. Designed via brainstorming → spec → plan, then
implemented as 7 tasks via subagent-driven development (a fresh Sonnet implementer + a Sonnet spec/quality
reviewer per task, then an Opus whole-branch review). 9 commits.

**Spec:** `docs/superpowers/specs/2026-06-19-lockscreen-approval-journey-design.md`
**Plan:** `docs/superpowers/plans/2026-06-19-lockscreen-approval-journey.md`

The journey: **glance** (redacted, stateful Live Activity) → **tap** → **in-app reveal** of the full
command/diff. Pieces:

1. **`lastDecision` transient on `ContentState`** (Swift + Go mirror). A server-resolved decision —
   including a killed-app Approve — can be confirmed with a ✓ on the lock screen. A client-side flash
   couldn't, because the app is asleep; only a *pushed* state can. (`LiveActivityManager.swift`,
   `daemon/push-backend/liveactivity.go`)
2. **Pure state-precedence resolver** `LiveActivityPresentation.resolve(_:budget:)` — keeps precedence
   logic out of the widget and unit-testable without a device.
   (`Packages/ConduitKit/Sources/SessionFeature/LiveActivityPresentation.swift`)
3. **Four widget states** — needs-you (amber + Approve/Reject) > decision-landed (green ✓ / red ✗) >
   running (blue) > idle; **cost** is a secondary overlay that escalates amber→red near a budget. The widget
   stays pure presentation (every state from the resolver). (`ConduitLiveActivityWidget/ConduitLiveActivityWidget.swift`)
4. **Backend decision push** `pushLiveActivityDecision` fires after a decision resolves in
   `handlePostDecision` — closes the cold ✓ loop. (`daemon/push-backend/liveactivity.go`, `decisions.go`)
5. **Reveal deep-link** — a notification / Live-Activity **body** tap opens the existing un-redacted
   `InboxApprovalDetail` sheet. Warm (app alive) + cold (killed → relaunch) via a new `OpenApprovalBuffer`
   that mirrors the existing `ApprovalActionBuffer`. Gate = **respect app-lock** (no new biometric step for
   *viewing*; critical *approve* stays biometric-gated, unchanged). REVIEW intent is strictly separated from
   the DECIDE path — opening detail never resolves an approval.
   (`Packages/ConduitKit/Sources/NotificationsKit/Notifications.swift`, `Conduit/ConduitApp.swift`,
   `Packages/ConduitKit/Sources/InboxFeature/InboxView.swift`, `AppFeature/AppRoot.swift`)
6. **Patch diff render** — `.patch`-kind approvals show a real `DiffView` in the detail sheet, composed in
   `InboxFeature` (which already depends on DiffKit/DiffFeature) so `DesignSystem` gains no new dependency.
   (`InboxView.swift`)

**One fix during review:** the whole-branch Opus review flagged that the cold reveal deep-link could
silently no-op if `InboxView.vm.approvals` hadn't loaded when the open signal fired (the sync engine streams
approvals in *after* AppRoot drains the buffer). Fixed by holding the deep-linked id in
`@State pendingOpenApprovalID` and resolving it via `.onChange(of: vm.approvals.count)` once the list loads.
Re-reviewed clean. (commits `a2d57115`, `51f910fc`)

### 1.3 Activity push-token subscriber — **PR #6** (`feat/activity-token-registration`, OPEN)

The dangling end of the push work. The token was *produced* (`ConduitApp.configureLiveActivityTokens` posts
`.conduitLiveActivityTokenReady`) and the secure RPC *existed* (§1.1), but **nothing subscribed** — so the
token never reached push-backend and the Live Activity could not receive a push on device. A
`// merge owner must wire this` comment at `ConduitApp.swift:124` marked it.

This PR adds:
- A `.conduitLiveActivityTokenReady` subscriber in `AppRoot.configureE2ERelayBridge` mirroring the existing
  `.conduitAPNSTokenReceived` one — forwards `{sessionID, activityToken, isPushToStart}` via
  `channel.registerActivityToken`.
- `startPushToStartMonitor(sessionID:)` (iOS 17.2+) in `AppRoot.configureCloudServices`, so push-backend can
  remotely **start** a Live Activity when an approval arrives and none is running (app fully closed).

Without this PR, the away-updates and the cold ✓ from PR #5 are dark. It's a ~25-line change, single file
(`AppRoot.swift`).

### 1.4 Design specs written (not yet implemented)

- `docs/superpowers/specs/2026-06-19-voice-liveactivity-drift-design.md` — a combined design for three
  competitive features: **#2 voice cockpit**, **#4 watch/Live-Activity/Dynamic-Island reach**, **#1 drift
  detection**. Revised after a Codex review. The lock-screen journey (PRs #5/#6) is the first slice of #4.
  The rest (voice, watch-away spike, drift) are **not started**.
- `docs/superpowers/specs/2026-06-19-parallel-handoff-prompts.md` — the original 5-lane dispatch prompts.

---

## 2. Git / PR state (exact, as of handoff)

| Branch / ref | State | Notes |
|---|---|---|
| `origin/master` (`320952e1`) | pushed | Has all the §1.1 V1 reach work + the owner's sidebar/UI redesign commits. |
| `master` (local) | **2 commits ahead of origin** | The 2 ahead are the lock-screen **spec** (`d4fd39c8`) + **plan** (`fa2c3ca3`) doc commits. Harmless; they're also carried into PR #5's branch, so they land when #5 merges. Push master if you want origin current, but it's not required. |
| `feat/lockscreen-approval-journey` | **PR #5, OPEN** | 9 commits past master. App-target build green. Awaiting review/merge. |
| `feat/activity-token-registration` | **PR #6, OPEN** | 1 commit past master. App-target build green. Independent of #5 — either can merge first. **Current checked-out branch.** |
| PR #3 `feat/governed-approvals` | OPEN (older, 2026-06-11) | "Cross-vendor Governed Approvals (decide-from-anywhere + governance IA)" — **relevant prior art for the governance panel**; review its IA before designing. |

There are many stale `agent/*`, `worktree-agent-*`, `oc/*`, `cursor/*` branches in the repo — ignore them;
they're from prior multi-agent runs. The SDD scratch ledger for PR #5 is at
`.superpowers/sdd/progress.md` (git-ignored).

**Recommended merge order:** #6 then #5 (token wiring is independent and unblocks device QA of #5), but
either order is fine. Neither has merge conflicts with master as of this writing.

---

## 3. Verification status

**Green (machine-verified this session):**
- XcodeBuildMCP **app-target** build (`build_sim`, scheme `Conduit`, sim `iPhone 17 Pro`) — SUCCEEDED, 0
  warnings, on both PR branch tips. This is the authoritative gate (plain `swift build` skips `#if os(iOS)`
  code and strict-concurrency breaks — a known footgun; always run the app-target build for iOS changes).
- `cd Packages/ConduitKit && swift build` — clean.
- `cd daemon/push-backend && go build ./... && go test ./...` — pass (incl. the pinned-`Date` encoding test,
  the payload-privacy assertion, and the new decision-push test).
- `cd daemon/conduitd && go build ./...` — pass.
- opencode gating was **live-verified** earlier against `~/.conduit/audit.log` (auto-allow + auto-deny, hash
  chain intact, no-gate-without-env confirmed).

**Device-only — NOT verified (a simulator cannot do these). Hand to device QA:**
1. **Cold ✓** — killed-app Approve from the Live Activity → green ✓ appears on the lock screen.
2. **Cold reveal deep-link** — killed-app tap on the Live Activity body → app launches to the Inbox detail
   sheet for that approval.
3. **Warm Live-Activity body tap** → detail sheet opens.
4. **App-closed Live Activity update** — agent hits an approval while the app is backgrounded → lock screen
   updates within seconds without opening the app (this needs PR #6 merged so the token is registered).
5. **Token registration round-trip** — confirm `register-activity-token` reaches push-backend (its logs) and
   APNs returns 200; a 400 `BadDeviceToken`/`TopicDisallowed` means the `apns-topic` is wrong.

There is a step-by-step device-verification prompt from earlier in the session (covers opencode gating, the
app-closed update, APNs privacy, and the cold-decision tap). Reuse/extend it. Device QA needs: a physical
iPhone (iOS 17.2+ for push-to-start), the resident `conduitd` running, push-backend reachable
(`CONDUIT_PUSH_BACKEND_URL`), and APNs keys configured backend-side.

---

## 4. How to work in this repo (conventions the next agent must follow)

- **Source of truth:** `ARCHITECTURE.md` §0.1/§4.1, `docs/KNOWN_ISSUES.md`, `docs/agent-contract.md`. The
  old `CONDUIT_PROJECT_DOSSIER.md` is archived — don't cite it.
- **Build gate:** always run the XcodeBuildMCP **app-target** build for iOS changes (`mcp__XcodeBuildMCP__build_sim`,
  scheme `Conduit`). SPM `swift build` is fast for ConduitKit-only loops but misses `#if os(iOS)` breaks.
- **Go tests** run from `daemon/conduitd` and `daemon/push-backend` (not repo root).
- **Module boundaries** (`docs/agent-contract.md` §5): engines have no UI; features route through
  `AppFeature`. Don't add a dependency edge from a low-level module (e.g. `DesignSystem`) to a feature lib.
- **Project skills** live in `.claude/skills/` — `conduit-context-onboarding` to get up to speed,
  `conduit-verification-gate` before claiming done, `vendor-cli-adapter-audit` before touching
  `dispatch.go`. Invoke via the Skill tool.
- **Known test-debt:** four `ConduitUITests/TapInjectionProofTests` are `XCTSkip`-quarantined (tracked as
  `UI-IA-1` in `KNOWN_ISSUES.md`) because they assert the superseded tab-bar IA. The `ConduitKitTests`
  scheme is wired to the UI-test target, so `#if os(iOS)`-gated unit tests *compile* but don't *run* under it
  — a harness quirk, not a defect.

---

## 5. The Governance / vendor-trust panel — design brief (NOT STARTED)

This is the next frontend surface the owner wants. **It has been scoped but not designed.** The single
blocking decision is its *primary job*; once that's picked, run it through the normal brainstorming → spec →
plan → subagent-driven-development flow (the same process that produced PRs #5/#6).

### 5.1 Why this surface exists (the problem)

The opencode-gating work (§1.1) completed Conduit's governance moat: **one policy engine now governs every
vendor it can launch — Claude Code, Codex, Kimi, and opencode.** That is the single strongest pre-launch
differentiator (no competitor combines a real policy engine + tamper-evident audit + on-host execution).
**But nothing in the app makes it legible.** A user cannot see that their agents are governed, that opencode
is now covered, or what the active policy is at a glance. The panel closes that legibility gap.

### 5.2 The one decision to make first — the panel's primary job

I asked the owner this and they paused to think; it's still open. Pick ONE as the spine (the others can be
secondary affordances):

- **(A) Proof / reassurance** *(my recommendation)* — a glanceable "you are protected" surface: all four
  vendors shown as governed by one engine, the active policy summarized in plain language, a live "last
  gated N seconds ago" pulse. Read-mostly. Lightest build, strongest pre-launch story, least overlap with
  existing screens. There's even a `ProofCardView` component
  (`Packages/ConduitKit/Sources/DesignSystem/Components/ProofCardView.swift`) that could anchor the visual
  language.
- **(B) Control surface** — view + edit the active policy from here (default effect, rules, the
  always-allow list), jump to the autonomy preset. More powerful, **but overlaps existing Settings screens**
  (`SettingsFeature/PolicyEditorView.swift`, `PolicySimulatorView.swift`, the autonomy-preset screen in
  `SettingsView.swift`). If you choose B, the design must *consolidate* those, not duplicate them.
- **(C) Audit / transparency lens** — per-vendor activity from the audit log: "opencode — 3 gated, 1 denied
  today," drill into the hash-chained trail. Strongest trust story but **heaviest**: needs audit aggregation
  surfaced over the relay (the data exists — see §5.3 — but there's no read path/RPC for a summary yet).

A reasonable hybrid: **ship A first** (cheap, high story value), leave hooks for C later. Don't try to build
all three at once — decompose.

### 5.3 What already exists to build on (verified file paths)

The panel is NOT greenfield. Inventory:

- **Policy model + engine** (conduitd, Go): policy is **global, not per-vendor** — rules match on
  `kind`/`risk`/`pattern` with strictest-wins (`deny > ask > allow`), default `ask`, fail-closed. Example
  config: `docs/policy.example.yaml`. Engine: `daemon/conduitd/policy/` + `rules.go`. **Important framing:**
  opencode gating wasn't "add opencode to a list" — it brought opencode under the *same* uniform engine. So
  the panel's story is "one engine covers everything you run," NOT "configure each vendor separately."
- **Read path already exists:** conduitd RPC **`agent.policy.get`** (`daemon/conduitd/server.go:560` →
  `getPolicyDocuments(cwd)`) returns the active policy documents. The panel can read the live policy over the
  relay without new backend work. There is also **`agent.status`** (`server.go:613`).
- **Per-vendor activity is derivable:** `AuditEntry` carries an **`Agent`** field
  (`daemon/conduitd/audit.go:18`). So "what has opencode done / been gated on" is computable from the audit
  log — but note (per the drift spec) the audit schema does **not** yet persist `path`/`toolInput`/
  `networkDest`, so option-C aggregation is limited to action/kind/effect/agent for now.
- **Autonomy model:** `Packages/ConduitKit/Sources/ConduitCore/AutonomySettings.swift` (`AutonomyPreset`),
  surfaced today via the autonomy-preset screen in `SettingsFeature/SettingsView.swift`.
- **Per-vendor identity UI:** `AgentIdentityBadge` (used in
  `DesignSystem/Components/InboxApprovalCard.swift`) already renders a vendor's icon+label — reuse it for the
  "4 vendors governed" row.
- **Existing policy UI to consolidate-or-avoid-duplicating:** `SettingsFeature/PolicyEditorView.swift`,
  `PolicySimulatorView.swift`, `OnboardingFeature/OnboardingPolicy.swift` (the onboarding policy-preset
  step). The `PolicySimulator` lets a user dry-run a command against the policy — a strong asset for a
  control or proof panel.
- **Prior art — read before designing:** **PR #3 `feat/governed-approvals`** ("Cross-vendor Governed
  Approvals + governance IA") is open and may already stake out IA decisions for this space. Check whether it
  conflicts with or seeds the panel before drawing new IA.

### 5.4 Where it lives in the IA

The app is a **sidebar / New Chat shell** (`ConduitSidebarView` + `SidebarShellState`, destinations via
`SidebarDestination`; see `ARCHITECTURE.md` §4.1). A governance panel would most naturally be a **new
sidebar destination** (peer to Inbox/Fleet/Settings) or a prominent card on the Inbox home dashboard. Do NOT
reintroduce a tab bar. Decide placement during brainstorming; it interacts with PR #3's IA.

### 5.5 Suggested process for the next agent

1. **Get context:** invoke the `conduit-context-onboarding` skill; read `ARCHITECTURE.md` §0.1/§4.1,
   `docs/agent-contract.md`, and **diff PR #3** to see what governance IA already exists.
2. **Invoke `superpowers:brainstorming`.** First question to the owner: confirm the **primary job**
   (A/B/C from §5.2). That single answer shapes everything.
3. Resolve secondary questions one at a time: placement in the sidebar IA; whether to consolidate the
   existing Settings policy screens (only if job = B); how much audit data to surface (only if job = C);
   whether to reuse `ProofCardView`/`AgentIdentityBadge`/`PolicySimulator`.
4. Write the spec to `docs/superpowers/specs/`, get owner sign-off, then `superpowers:writing-plans`, then
   `superpowers:subagent-driven-development` with **Sonnet** implementer/reviewer subagents (the owner's
   standing preference this session). Gate every task with the app-target build.
5. **Don't over-build.** YAGNI: if job = A, a read-mostly panel that reuses existing components and the
   `agent.policy.get` RPC is a small, high-value surface. Resist folding B and C in.

### 5.6 Open risks / watch-outs for the panel

- **Overlap with Settings policy screens** is the biggest design risk (job B). Decide consolidate vs.
  complement up front.
- **Policy is global, not per-vendor** — don't design a UI that implies per-vendor *configuration*; the
  vendors share one engine. Per-vendor *activity* (audit) is fine to show.
- **PR #3 may already own some of this IA** — reconcile before drawing new structure.
- **Audit summary has no RPC yet** (job C) — option C needs a new conduitd read path + relay plumbing;
  budget for it or defer C.

---

## 6. Other open threads (lower priority, for awareness)

- **Voice cockpit (#2)** and **drift detection (#1)** — designed in
  `docs/superpowers/specs/2026-06-19-voice-liveactivity-drift-design.md`, **not implemented.** Voice = market
  parity (migrate the existing `DictationEngine` into a `VoiceKit` engine; voice-approve **disallowed for
  critical** entirely). Drift = the governance-offense feature (deterministic config+policy inventory ships
  first; behavioral drift is gated on an audit-schema expansion). Either is a future cycle.
- **Watch-away (Track B)** — independent watch APNs when the phone is absent; designed as a *feasibility
  spike* (watchOS-27 entitlements unverified), not a committed build.
- **`master` is 2 commits ahead of origin** — the lock-screen spec/plan docs. Push if you want origin
  current; not required.
- **`UI-IA-1`** — the quarantined tab-bar UITests need rewriting against the sidebar shell once that IA
  fully settles (`KNOWN_ISSUES.md`).

---

## 7. Quick-start commands for the next agent

```bash
# Orient
cat ARCHITECTURE.md         # read §0.1 + §4.1
gh pr view 5 ; gh pr view 6 ; gh pr view 3

# Build gate (authoritative for iOS)
#   mcp__XcodeBuildMCP__build_sim  scheme=Conduit  sim="iPhone 17 Pro"
cd Packages/ConduitKit && swift build           # fast inner loop
cd daemon/push-backend && go build ./... && go test ./...
cd daemon/conduitd     && go build ./... && go test ./...

# Governance panel — read the prior art first
git diff master...feat/governed-approvals -- '*.swift' | less
```
