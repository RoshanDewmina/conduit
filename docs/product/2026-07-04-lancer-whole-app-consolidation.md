# Lancer — Whole-App Consolidation

Prepared: 2026-07-04
Status: consolidated reference, not a decision document — extends the Away Mode consolidation to
cover the rest of the app, per owner correction that this brainstorm had narrowed to one area

> **Superseded 2026-07-05** by `docs/product/2026-07-05-lancer-feature-master-plan.md` — kept for
> historical record only. That doc is now the canonical feature source of truth.
>
> **Away Mode pivot descoped 2026-07-06:** Sections below that discuss "Away Mode" as product
> positioning or pricing are historical only. See `docs/_archive/away-mode-2026-07/README.md`.

Companion doc: `docs/_archive/away-mode-2026-07/2026-07-04-away-mode-master-consolidation.md` (Away Mode area, same
rigor, done first and not repeated here)
Method: 9 areas researched via parallel background workflow — competitor cross-check against 6
cloned repos (Omnara, OpenCode, Vibe Kanban, Happy, Happier, Orca), iOS 27/WWDC 2026 platform
grounding, and existing-state verification against `ARCHITECTURE.md` and prior audits, all with
file-path or URL citations.

## Why this doc exists

The Away Mode consolidation, exhaustive as it was, only covered one slice of Lancer. This doc
completes the picture across the other structural areas: Governance & Policy, Fleet & Machines,
Terminal & SSH, Settings/Trust Center/Security, LancerMac, Watch app, Cross-device sync, Billing &
packaging, and the remainder of the 24-pillar "mobile-primary cockpit" inventory not already folded
into Away Mode.

## Coverage status

| Area | Status |
|---|---|
| Governance & Policy | ✅ complete |
| Fleet & Machines | ✅ complete |
| Terminal & SSH | ✅ complete |
| Watch app | ✅ complete |
| Cross-device sync | ✅ complete |
| Billing & packaging | ✅ complete |
| Settings, Trust Center & Security | ✅ complete (retry pass) |
| LancerMac | ✅ complete (retry pass) |
| Mobile-Primary Cockpit remainder | ✅ complete (retry pass) |

All 9 areas complete. The first pass hit a session token limit partway through (3 areas failed with
no valid output, not a partial/wrong result); a retry pass completed those 3 with the same research
context and citation standard as the first 6.

## Headline correction — read this first

**A claim repeated throughout this whole session (in the Away Mode consolidation doc, in this doc's
own earlier draft, and in conversation) is stale: "biometric gate removed for V1" is no longer true.**
Commit `695d2440` — "Merge fable/approval-security-hardening: BiometricGate + App Attest device
binding" — landed on `master` the same day as this research, and is visible at the top of the very
first `git log` shown at the start of this conversation. It reinstates a risk-tiered biometric gate
(`ApprovalDecisionAuth`) for high/critical and unknown-risk approval decisions, wired into every live
decision path (inbox, notification actions, Live Activity/Dynamic Island, `ApprovalRelay`). Low/medium
decisions deliberately stay one-tap by design. Full detail in §7 below.

This means: `ARCHITECTURE.md` §0.1/§10.2 and `docs/competitive-intelligence/reports/
current-product-baseline.md` §4/§7/§9 all currently assert the old, now-false claim as unqualified
current truth. Both are stale and should be corrected — flagging for the owner rather than editing
them here, since that's outside this consolidation's scope. Anywhere this session cited "no lock
screen, approvals commit on tap" as a real security weakness, treat that as superseded by §7 below.

---

## 1. Governance & Policy

**The moat is real, and this pass reconfirms it against four more competitors than the prior audit
checked.**

### Existing state (verified against real code)

`daemon/lancerd/policy/{evaluate,match,load,simulate,migrate,types}.go` is a genuine rule-based
engine: YAML `Document{Default, Rules[]}`, deny>ask>allow strictest-wins merge across repo + global +
always-allow docs, risk scoring (0=low..3=critical) where a client-supplied risk band can only
*raise* never lower the score (an explicit anti-lie design), a no-client-grace fast path gated below
high risk, and scoped allow-always rules with expiry/time-windows. `Policy.Simulate()` replays real
audit-log entries against a *proposed* policy and reports auto-approved/asked/denied counts and
per-rule hit counts — a real "what-if" tool, not a toggle.

`daemon/lancerd/audit.go` is a genuine SHA-256 hash chain with secret redaction and JSONL export.

**Correction to prior framing**: `drift.go` does **not** do host/fleet configuration drift (differing
CLI versions or policy rules across machines) — it's a documentation/instruction-file drift scanner
(dead `@import`s and dead markdown links in `CLAUDE.md`/`AGENTS.md`/etc.). Real and well-built, but
"agent-instruction doc rot detection," not fleet drift as the name implies. Worth renaming the
internal framing or building the actual cross-host policy-consistency check described below.

**Emergency stop is not atomic.** iOS-side `performEmergencyStop()` (`AppRoot.swift:~1593`) loops
client-side over every session/run and sends individual stop messages; daemon-side `applyRunControl`
(`server.go:~457`) cancels one run at a time. If the phone/relay link drops mid-loop, some runs never
receive the stop. For a feature literally marketed as "the panic button," this is a real gap.

### Competitor findings

- **Happy**: E2E encryption is real code — `tweetnacl.secretbox` (XSalsa20-Poly1305) legacy variant
  and real `node:crypto` AES-256-GCM for the newer data-key variant (`packages/happy-cli/src/api/
  encryption.ts`). But **zero governance layer** — its entire "permission" system just picks which
  of Claude Code's own permission modes to launch with; its own `CLAUDE.md` states "permission
  checking not implemented yet." Confirms no analog to Lancer's policy depth.
- **Orca**: only governance-adjacent code is a one-time trust-on-first-use hash check for a repo's
  setup script (`mobile/src/tasks/setup-hook-trust.ts`) — no rule engine, no risk tiers, no audit
  chain, no drift detection, no emergency stop.
- **Vibe Kanban**: has a real per-tool-call approve/deny/timeout mechanism
  (`crates/utils/src/approvals.rs`) — the closest analog to Lancer's inbox — but no policy document,
  no hash-chained audit (only analytics telemetry on decisions), no drift detection.
- **OpenCode**: its own v2 policy spec explicitly scopes out "conditions, principals, approval
  prompts, or enforced configuration values" (`specs/v2/provider-policy.md`) — confirms it supplies
  no governance depth to compete with, consistent with why Lancer gates it via an external plugin.

**None of the 4 competitor repos checked has anything close to the policy-engine + audit-chain +
simulate combination.** This reconfirms the 2026-07-03 audit's original conclusion, now against a
wider competitor set.

### Platform findings

- **Foundation Models `tokenCount`/`transcript` APIs** (shipped iOS 26.4, works under the project's
  actual 26.0 target): usable for an on-device, privacy-preserving "what happened while you were
  away" digest built specifically from audit-log data — distinct from the general Away Mode digest.
  [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- **App Intents `authenticationPolicy`**: any Siri/Lock-Screen-reachable intent fires with no
  unlock required unless explicitly set to `.requiresAuthentication` — directly relevant if an
  Emergency Stop Shortcut/Siri intent is ever built, especially given the biometric gate was already
  removed for V1 approvals.

### Feature ideas

- **NEW — Atomic server-side emergency-stop RPC**: a single `agent.emergencyStop` daemon RPC that
  cancels every non-terminal run in one local pass, independent of the phone/relay link, with one
  dedicated audit entry for the stop-all event itself (today there's no record an emergency stop was
  ever invoked, only per-run stop entries).
- **NEW — Cross-host policy-consistency check** ("policy drift," distinct from the existing doc-drift
  scanner): compare policy rule sets across paired machines and flag divergence (host A denies
  `rm -rf`, host B has no such rule). Reuses the existing scan/report/remediate pattern.
- **NEW — On-device audit-log digest** via the verified Foundation Models token/transcript APIs —
  a privacy-preserving governance-specific summary, coordinate with (don't duplicate) the Away Mode
  digest workstream.
- **NEW — External checkpoint anchoring for the audit chain**: periodically push just the chain's
  tip hash somewhere outside host-local storage (push-backend, iCloud, phone Keychain) so `Verify()`
  proves more than internal self-consistency — today a root-compromised host could regenerate a
  fully self-consistent fake chain from scratch.

### Flags

- Emergency stop is 100% client-orchestrated, not atomic — a real robustness gap for the feature's
  own marketing framing.
- "Fleet drift" as currently implemented is doc-rot detection, not fleet/policy drift — a naming or
  scope-truth gap worth an explicit owner call.
- iOS 27/26 deployment-target discrepancy noted but doesn't block the on-device digest idea either way.

---

## 2. Fleet & Machines

### Existing state

Two independent, currently hardcoded caps of 3: `FleetSlotManager.maxSlots` (legacy SSH-path,
deferred-to-V2) and `RelayMachineRecord.relayFleetMaxMachines` (the one that actually matters for V1,
since relay is the V1 transport). `HostHealthStore` polls each connected SSH-path slot every 60s for
health/drift — **this poll loop doesn't cover `RelayFleetStore` machines at all.** The existing
widget (`LancerStatusWidget.swift`) is single-host only, purely display, no interactive elements.

**A more fundamental ceiling, already filed as a P1 in `docs/KNOWN_ISSUES.md` (2026-07-04)**:
`lancerd` persists exactly **one** relay pairing system-wide — every new pairing entry point silently
overwrites it, orphaning any previously-paired phone within ~5 seconds. This is a deeper architectural
constraint than the phone-side 3-machine cap.

### Competitor findings

- **Orca**: no enforced numeric cap on parallel agents/worktrees/paired hosts anywhere in the code
  (`mobile/src/transport/host-store.ts` stores an unbounded array). The audit's "25+ agents in
  parallel" framing is looser than the README's actual claim ("fan one prompt across five agents" —
  a marketing example, not a hard limit). Its mobile fleet view is a two-level host list → per-host
  repo-grouped worktree list with live status dots, built on its desktop app doing the actual
  orchestration (mobile only monitors/steers). Its only governance concept is a single three-way
  setup-hook policy (ask/run-by-default/skip-by-default) — confirming it trades governance depth for
  raw parallelism, the opposite bet from Lancer.

### Platform findings

- **`LongRunningIntent`** (App Intents, iOS 27): runs past the 30-second background limit — directly
  applicable to a background fleet-health-refresh intent that doesn't need the app foregrounded.
- **`SyncableEntity`** (App Intents, iOS 27): stable entity identity across a user's devices —
  relevant to a future cross-device (iPhone/iPad/Watch) consistent paired-machine identity.
- **`ExecutionTargets`** (App Intents, iOS 27): lets an intent declare where it runs (main app vs.
  widget extension) — relevant to a widget's tap-to-act buttons executing without a full app launch.

### Feature ideas

- **NEW — Fleet-wide status widget**: extend the widget beyond single-host to a multi-machine
  aggregate with per-machine health + pending-approval count, backed by `LongRunningIntent` so it
  doesn't go stale between foregrounds.
- **NEW — Interactive widget actions** (stop/approve from the widget) via `ExecutionTargets` — with
  an explicit caution: any tap-to-approve-from-widget must still go through the same risk-tier gate
  as in-app, or it directly undercuts the governance wedge. Scope to low-risk pre-cleared items, or
  omit approve entirely and keep only fail-closed stop/deny actions.
- **RECONSIDER — Decouple "paired and monitored" from "actively steered with live approval attention"**
  rather than just raising the 3-cap. Orca's uncapped model works *because* it's lightly governed;
  Lancer's differentiator is a human reviewing every risky action, and that doesn't scale past a
  handful of concurrent approval streams regardless of backend parallelism. Any cap change should be
  a monitoring-only relaxation, evaluated separately from session-steering capacity.
- **RECONSIDER — Fix the daemon's single-pairing-slot ceiling** before raising any phone-side cap —
  already filed, unresolved, and more fundamental than the phone-side number.

### Flags

- Lancer's 3-machine cap is the most-constrained of three competitors on this specific dimension
  (Anthropic Remote Control: up to 32 concurrent sessions; Codex mobile: multiple hosts, portfolio
  framing) — by design per the governance-first pivot, not by oversight, but worth the owner knowing.
- Raising the phone-side cap without first fixing the daemon's one-pairing-slot ceiling makes the
  known orphaning bug worse, not better.

---

## 3. Terminal & SSH

### Existing state

Fully implemented, deliberately unwired from V1 nav (2026-06-30/07-01 decision). Block mode +
Raw PTY mode both work; `grep -rn "LiveTerminalView("` across all of LancerKit returns zero call
sites outside its own file — confirmed truly orphaned, not just de-emphasized. The keyboard rail
(`HardwareInputHandler.swift`, `KeyCommands.swift`) is also built and unwired.

### Competitor findings

- **Happy**: does **not** render a live terminal on the phone at all. Its "terminal" route is a
  QR/deep-link pairing flow that authorizes a *desktop* terminal session — on native iOS/Android it
  shows a literal placeholder screen ("terminal requires a web browser"). Independent confirmation
  of Lancer's own instinct that terminal isn't a mobile-native surface.
- **Happier** (a materially more advanced fork of Happy, live on the App Store, **not currently
  tracked in `competitors.jsonl`**): does ship a live embedded terminal — but as an opt-in,
  admin-configurable feature flag (`terminal.embeddedPty`), one of several togglable extras
  alongside voice/automations/social/session-handoff. On phone it's forced into a sidebar dock (never
  full-screen/primary) with a compact 4-key quick-bar, not the full desktop dock menu. Architecturally
  it's a WebView wrapping xterm.js — weaker fidelity than Lancer's native SwiftTerm+BlockRenderer
  engine, and exactly the WebView/native tradeoff `ARCHITECTURE.md` §8.5 already argued against.

**Net: even the one competitor that ships mobile PTY treats it as secondary, flag-gated, and
quick-keys-only** — closer to validating "escape hatch" than to justifying promoting terminal to a
primary surface.

### Platform findings

- iOS 27's UIKit is described across independent write-ups as a genuinely small release — no new
  hardware-keyboard or terminal-relevant paradigm shipped this cycle. This weakens any "wait for iOS
  27 to make terminal cheaper to re-surface" argument — there's nothing new to wait for.
- `UIKeyCommand`/hardware keyboard support is a stable, non-iOS-27-specific API — confirms no
  version-gating blocker exists to re-wiring the already-built keyboard rail if the nav decision is
  ever reversed.

### Feature ideas

- **ALREADY_COVERED — Keep terminal deferred; reaffirm, don't reverse.** Fresh competitor evidence
  doesn't surface a reason to change course — if anything it's independent confirmation.
- **ALIVE — Cheap re-surfacing hook**: a single low-prominence "View raw terminal" action buried in
  an overflow menu on Work Thread or Machine Detail, not a promoted nav entry — matches the shape the
  Away Mode doc's own "Terminal Escape Hatch" section already recommends. Cost is almost entirely
  wiring one button, since the view/transport/engine all already compile.
- **ALREADY_COVERED — Do not copy Happier's WebView/xterm.js approach** if re-surfacing — a negative
  recommendation confirming the existing native-rendering decision is still right.

### Flags

- Happier deserves its own `competitors.jsonl` entry, distinct from Happy — materially more advanced
  (multi-vendor, live on the App Store, embedded terminal, session handoff, enterprise SSO/OIDC/mTLS).

---

## 4. Watch app

### Existing state — corrects the prior "already built, just unwired" framing

**The Watch app is far more complete than assumed, and the actual gap is different than described.**
It's a fully-built, tested, standalone-buildable watchOS app: a real 4-tab UI (Inbox, Session
Status+Stop, Activity Feed, Snippet Runner), live WatchConnectivity sync (pending approvals, session
status every 5s, activity every 10s, snippets every 60s — not stubs), haptics, and a complication with
real App Group-backed pending count. Two dedicated Swift-Testing test files confirm it's genuinely
tested, not dead code.

**The real gap: `LancerWatch`/`LancerWatchWidget` are deliberately NOT embedded in the iOS app
target** (`project.yml:138-143`, an explicit comment about `simctl`/XcodeBuildMCP breakage from
embedding a watchOS-arch binary). A Watch app normally installs automatically alongside its parent
iOS app — this one isn't attached to the parent at all, so it currently **reaches zero real users**
via the shipped TestFlight build. This is a packaging/CI decision, not a feature-flag-off situation —
more severe than "unwired," and it needs resolving before any further Watch UI investment is worth it.

Also found: zero in-app discoverability anywhere (no Settings row, no onboarding mention), and the
complication's `TimelineProvider` never sets `TimelineEntryRelevance`, so it can't proactively surface
via watchOS 27's smarter Smart Stack.

### Competitor findings

- **Omnara**: repo has zero watchOS code and no `.xcodeproj` anywhere — but the live App Store
  listing states "requires watchOS 10.0 or later." Unlike the already-confirmed-fake E2EE claim,
  this is **not** cleanly confirmed fake — the repo snapshot may just not capture a native Watch
  companion built elsewhere. Flagged as unresolved, not asserted either way.
- **Happy and Happier**: neither has a watchOS target at all — every "watch" hit in both repos is a
  filesystem watcher (dev-tooling), not an Apple Watch companion.
- **Vibe Kanban, Orca**: not applicable (neither is a phone product).

**Watch companion apps are essentially unique to the Omnara-claims-it/Lancer-actually-has-it axis**
among all 6 repos checked.

### Platform findings

- **`PrivateCloudComputeLanguageModel`** confirmed to run on watchOS 27 — genuine use: generate a
  one-line plain-English gloss of a pending approval directly on-wrist, no API keys, no BYOK, no
  round-trip through the phone.
- **watchOS 27 Smart Stack**: now proactively surfaces widgets by situational relevance — the
  complication should adopt `TimelineEntryRelevance` scored by pending count/risk to actually benefit
  from this (currently unused).
- Same EU/China Siri regulatory gap applies identically to any Watch-side Siri integration.

### Feature ideas

- **NEW — Resolve the embed-vs-simulator-testability tradeoff so LancerWatch actually ships**: this
  is the real blocking prerequisite, not a new feature — e.g. conditional embed for Release/archive
  builds with a separate non-embedded Debug scheme for simulator verification. Higher-leverage than
  any new Watch UI work, and invisible from doc-level review alone.
- **NEW — On-wrist approval summary** via the confirmed watchOS-27 `PrivateCloudComputeLanguageModel`
  — fits the governance wedge directly (summarization to aid a decision, not editing).
- **NEW — Smart Stack relevance scoring** for the existing complication — concrete, low-risk, serves
  the "notify and approve without context-switching" job specifically on the surface where it matters
  most.
- **RECONSIDER — Trim or re-scope Activity Feed / Snippet Runner tabs**: these replicate phone-level
  chat/terminal depth on a worse screen, cutting against the "demote chat/terminal depth" direction
  doubly hard on a small screen. Inbox + Session Status + Stop map cleanly onto the governance wedge;
  the other two read as scope creep.

### Flags

- **This is a distribution gap, not a wiring gap** — needs an explicit owner decision on
  Release-embedding vs. Debug-simctl-testability before any further Watch investment.
- `ARCHITECTURE.md` states watchOS 26.0+ as the floor but `project.yml` hardcodes `WATCHOS_DEPLOYMENT_TARGET: "11.0"` in 4 places — reads like a stale scaffold default, not an intentional floor.
- Honest investment read: Watch is worth keeping and lightly investing in for the governance triad
  (approve/deny/stop) specifically, since that's a real, cheap "glanceable control surface" story to
  compare against competitors — but not worth investing in as a second terminal/chat surface.

---

## 5. Cross-device sync

### Existing state

Two distinct sync domains: (1) curated settings (snippets/hosts/host-key fingerprints) via a CloudKit
private-DB default zone, and (2) conversation continuity, where **execution truth is a host-owned
SQLite ledger** (`daemon/lancerd/conversation_store.go`), mirrored to iOS via GRDB and to other Apple
devices via a CloudKit custom-zone mirror. CloudKit is explicitly a **read-continuity mirror, never a
writer** — pulled rows never trigger a dispatch, conflicts surface rather than auto-merge, offline
sends stay honestly local rather than faking a "sent" state.

**Critical open gap, already flagged in `ARCHITECTURE.md`**: `CKDatabaseSubscription` silent-push
delivery has **not been observed on physical hardware** — CloudSync is a simulator no-op by design.
Two-device behavior (start on A, appears on B; kill/reinstall A, restores from CloudKit) is unverified
on real devices.

### Competitor findings

- **Happier**: architecturally **not** peer-to-peer or Apple-mirror-based like Lancer — it's
  client-server, where a Relay Server (Fastify + Socket.IO + Postgres + Redis + S3, self-hostable or
  hosted) is the **persistent store of record**, not any device. Real-time sync rides a persistent
  WebSocket connection, not a push-notification-triggered background fetch. Payloads are client-side
  E2E encrypted before hitting the server (philosophically similar to Lancer's blind relay), but the
  server still durably stores all encrypted history across devices — unlike Lancer's relay, which
  never stores conversation history at all.
- **Happier's continuity story is broader than viewing**: it supports **live session handoff between
  machines** — moving an in-flight running session (including provider state and working directory)
  between hosts while keeping the same session ID. Materially different from Lancer's read-only
  mirror, which can't move an in-flight session or create an executable turn from CloudKit data. Also
  ships fork/replay and collaborative sessions (add friends by username, view-only public links) —
  none of which Lancer has or is pursuing.
- The existing `competitors.jsonl` entry for "happy" is stale and describes the wrong project —
  Happier (not tracked at all) is the one with the actually-relevant, far more capable feature set.

### Platform findings

- No confirmed iOS-27-specific `CKSyncEngine`/`CKDatabaseSubscription` changes found — this is itself
  useful signal that no forthcoming API removes the physical-hardware verification burden.
- General (not iOS-27-specific) guidance confirms silent pushes are commonly delayed/throttled
  regardless of platform version, and are recommended to pair with fallback polling — which
  corroborates why Lancer's existing foreground-polling fallback design is the right mitigation, and
  why the still-open physical-hardware gap is a real risk, not paranoia.
- One low-authority, uncorroborated claim that iOS 27 makes `UISceneDelegate` mandatory in a way that
  could silently break push token registration — flagged as unverified, not established.

### Feature ideas

- **ALREADY_COVERED — Close the physical-hardware CloudKit verification gap.** More urgent than any
  new feature: Lancer's entire differentiation claim here is unproven on real hardware, while
  Happier's competing claim rests on a mechanism that structurally can't have the same failure mode
  (a persistent connection isn't push-dependent while the app is open).
- **NEW — Foreground-refetch-as-fallback banner state**: if push turns out unreliable in practice
  (well-documented general OS behavior), make the existing `cloudStale` UI state surface an explicit
  pull-to-refresh affordance rather than a passive indicator — likely a cheap, additive UI change.
- **CONFLICTS_WITH_NONGOAL — Live session handoff between hosts** (Happier's model): not literally on
  the non-goals list, but cuts directly against "execution truth is the host, not the phone or
  CloudKit." Would require either a shared execution substrate (conflicting with the no-built-in-cloud-
  VMs non-goal) or reimplementing session state as host-portable — a different, heavier product. Not
  recommended to chase; flagged only because a reviewer may ask why Lancer doesn't have it.
- **CONFLICTS_WITH_NONGOAL — Cross-platform (Android/web/desktop) mirror**: would require standing up
  Happier's exact architecture (a hosted relay that's itself the durable store), contradicting
  "execution truth is the host." If ever wanted, this is a strategic fork requiring an explicit owner
  decision, not an incremental CloudKit feature.

### Flags

- Lancer's "execution truth lives on the host" model is a genuinely different (arguably safer/
  simpler) architecture than Happier's "server is the store of record" model — worth stating as a
  real differentiator **once the CloudKit gap is resolved**, but it's a design claim, not a proven
  capability, until then. Don't market it as an advantage yet.
- The competitive dataset has no scored dimension for cross-device/multi-device sync at all, and its
  one relevant entry ("happy") is stale/wrong about the actual current state of that lineage.

---

## 6. Billing & packaging

### Existing state — three uncoordinated paid mechanisms

1. **StoreKit one-time "Lancer Pro" IAP** (`dev.lancer.mobile.pro`, "$14.99" placeholder price,
   "pay once, yours forever" copy) — **currently gates zero features.** `showingPaywall` is declared
   in `AppRoot.swift` but never set `true` anywhere in the codebase; `isPro`'s only other consumer in
   `SettingsView.swift`/`BillingView.swift` is a cosmetic FREE/PRO badge. This is pure UI scaffolding
   today, not a design choice on record anywhere. **Correction (2026-07-04, per independent Codex
   verification): this dormant-gate finding applies only to this one-time IAP's `isPro` flag —
   it does not mean "billing gates nothing" more broadly (see item 2).**
2. **push-backend Stripe monthly/annual "cloud AI" subscription** — real, wired (customer creation,
   OpenRouter sub-key provisioning), single tier, no team-plan branch in the billing code. **This
   entitlement (`PurchaseManager.hasCloudEntitlement`, distinct from the dormant `isPro` in item 1)
   genuinely does gate real functionality — hosted-agent/cloud-AI operations require it.** Don't
   conflate the two: the one-time client IAP is dormant, the separate cloud subscription is not.
3. **Away Mode subscription** ($25/mo solo, $99/mo team, per the Away Mode consolidation doc and
   memory) — documented, gated on the 2026-07-21 validation deadline, but **no team-tier billing code
   exists yet** — it's a plan, not a shipped Stripe product.

### Competitor findings

Across all 6 cloned repos, **none charges anything for client access itself** — subscription or
one-time:
- **Omnara**: client fully open-source; monetizes hosted execution via Stripe (Free/Pro $9→$20/mo/
  Enterprise) — real, wired billing code, zero paywall in the mobile client.
- **OpenCode**: CLI free/MIT; monetizes a separate hosted product ("Zen") via Stripe subscriptions —
  model-credit access, not client-gating.
- **Vibe Kanban**: desktop/CLI free/Apache-2.0; a separate `remote` crate implements org-level Stripe
  billing for a hosted layer — the closest structural precedent to Lancer's own push-backend org
  model, but again the base client ships free.
- **Happy & Happier**: both free/MIT clients, both integrate RevenueCat, but the flow is an explicit
  **voluntary tip-jar** (`voluntary_support` CTA), only gating an expensive AI-cost feature (realtime
  voice) — not the app itself.
- **Orca**: fully free/MIT, confirmed zero payment-related code anywhere in the mobile client.

### Feature ideas

- **NEW — Wire the dormant Lancer Pro paywall to real features, or delete it.** This is a
  correctness gap, not a speculative idea: App Review and paying testers will notice a purchase that
  visibly changes nothing. Directly affects the credibility of the 2026-07-21 validation gate's
  "3 paying customers" criterion if the only currently-functional monetization surface does nothing.
- **RECONSIDER — Whether the one-time client IAP is worth keeping at all**, given zero peer precedent
  for *any* client-side paywall (subscription or one-time) across all 6 competitors. Doesn't
  invalidate the "no subscription gating" non-goal (which specifically targets recurring fees,
  citing Termius/Blink backlash) — a one-time purchase is a different animal — but the "client is
  paid" framing has no supporting precedent here. Worth an explicit owner decision: keep the
  lifetime-IAP tier as a differentiated bet, or consolidate around the Away Mode subscription as the
  sole paid surface, following the free-client-plus-metered-layer pattern every competitor uses.

### Flags

- Three paid mechanisms exist without a unified pricing narrative — needs an owner decision on how
  they relate before external beta.
- The dormant paywall is a real gap, not a documented design choice.

---

## 7. Settings, Trust Center & Security

### Existing state — materially ahead of the docs that describe it

**The biometric gate is back**, and both `ARCHITECTURE.md` and the 2026-07-02 competitive baseline
are stale on this point (see the headline correction above). The reinstated gate
(`Packages/LancerKit/Sources/SecurityKit/ApprovalDecisionAuth.swift`, new, 41 lines) is narrower and
more deliberate than the original spec's blanket app-launch lock:
`requiresUnlock(risk:)` returns true for risk ≥ high, or unknown risk (fail-closed when there's no
local row to read a tier from). `authorize(risk:unlock:)` runs `BiometricGate.shared.unlock(reason:)`
only for those tiers; any throw (cancel, or failed biometry+passcode) blocks the decision. Wired at
every live decision entry point: `InboxViewModel`/`LiveInboxViewModel.decide`, notification-action
routing, and `ApprovalRelay.enqueue` (the last one matters because it's what Live Activity/Dynamic
Island buttons and Siri route through — `UNNotificationActionOptions.authenticationRequired` doesn't
cover widget intents). Low/medium decisions deliberately stay one-tap, mirroring the daemon's
`policy.PermitsNoClientGrace` split — a design choice, not an oversight. Apple Watch decisions
deliberately bypass phone-side Face ID, trusting wrist detection + the watch's own passcode. Two
dedicated test files confirm this is tested, not just merged.

**Two real gaps this merge did *not* touch, confirmed by direct code read, still open:**

1. **JWT is still HS256-only** (`daemon/push-backend/auth.go:46-60`) — no JWKS fetch, no RS256/ES256
   path, no `kid`-based key selection. Gates device management, App Attest, every standard-account
   API. If the production Supabase project is ever configured to sign RS256, every standard-account
   call fails outright.
2. **`BiometricGate` itself still degrades open with no device passcode enrolled**
   (`BiometricGate.swift:16-24`): if `canEvaluatePolicy` fails for any reason other than
   "biometry not enrolled" (i.e., no passcode set at all), the function returns success instead of
   throwing — "degrade gracefully" per its own comment. Because the brand-new high/critical gate is
   built directly on this function, **it inherits the exact same hole**: an attacker holding an
   unlocked iPhone with no passcode configured can still approve high-risk actions with zero
   friction. This is the single most actionable gap found in this entire consolidation — it directly
   undercuts a governance-critical control that was just built.

**Smaller finding**: the previously-known `e2eRouter.sendApproval` silent-no-op-when-unpaired gap was
partially addressed the same day (commit `a37920a8`) — but only with a log line. The drop itself is
unchanged: an approval raised while the phone is unpaired is still dropped, not queued. Diagnosable
now, not fixed.

Device management UX (`DeviceManagementView.swift`) still has no last-active timestamp, no IP/
location/platform metadata, no bulk revoke — matches the prior baseline, unchanged.

### Competitor findings

- **Happy and Happier**: neither has any biometric/lock-screen/local-authentication gate anywhere —
  exhaustive grep for biometric/Face ID/Touch ID/LocalAuthentication/app lock/passcode across both
  repos returned zero hits, no `expo-local-authentication` dependency in either. Happier uses
  `expo-secure-store` (encrypted-at-rest token storage), which is not an authentication ceremony.
  **Lancer is now ahead of both on this specific dimension.**
- Neither repo has a `SECURITY.md` or references any CVE/security-advisory string in its markdown
  corpus (in-repo check only, not the upstream orgs' hosted advisory databases).

### Platform findings

- `LAPolicy.deviceOwnerAuthenticationWithBiometricsOrWatch` was checked as a way to formalize the
  Watch-bypasses-Face-ID exception via an official API — ruled out, it's macOS-only, not available
  on iOS at any version.
- No iOS-27-specific LocalAuthentication API change found that would close the degrade-open gap —
  that remains an app-level logic fix, not a new platform API to adopt.

### Feature ideas

- **RECONSIDER — Fail-closed `BiometricGate` on no-passcode devices**: throw instead of silently
  returning success when `canEvaluatePolicy` fails for a non-enrollment reason, with an explicit
  debug/simulator-only bypass preserved. Not a new idea — it's the exact fix already written down in
  `docs/KNOWN_ISSUES.md` §2, unresolved — but now higher priority since it's the direct dependency of
  the new high/critical approval gate, not just a device-theft footnote.
- **NEW — JWKS/RS256 verification path**: fetch-and-cache the configured Supabase project's JWKS,
  branch on token alg/kid, keep the existing HS256 path for backward compatibility, fail closed if
  neither validates.
- **RECONSIDER — Queue-and-retry (not just log) an approval dropped while unpaired**: persist the
  dropped event and flush it on next successful pairing, rather than leaving it invisible until the
  120s fail-closed timeout resolves it unseen.

### Flags

- Both `ARCHITECTURE.md` and the 2026-07-02 competitive baseline need the "biometric gate removed"
  claim corrected to "partially reinstated, risk-tiered" — flagging for the owner, not editing those
  docs directly here.
- JWT HS256-only and the BiometricGate no-passcode degrade-open path are the two genuinely open
  security gaps in this area, confirmed by code, not doc claims — the most actionable next items if
  closing the security-posture gap further is a priority.

---

## 8. LancerMac

### Existing state — confirms the prior recommendation to keep it scoped

LancerMac is a thin, stateless SwiftUI menu-bar app (~1266 lines across 8 files) managing `lancerd`'s
lifecycle over a hardened Unix-socket IPC — install/update/launch-at-login, QR/6-digit pairing,
device revocation, machine-identity rotation, connection health, diagnostics/doctor/redacted-log
export. The scope is locked by `docs/product/mac-ios-responsibility-matrix.md`, which explicitly
excludes full transcripts, terminal/PTY rendering, a full approval inbox, and a file browser from the
Mac app. Phase A shipped 2026-06-22; Phase B (Security, Agents & Workspaces panes) has shipped since.

**One concrete gap found in code**: `MenuBarContentView.swift` ships "Pause All" and "Emergency Stop"
buttons that are `.disabled(true)` with an explicit `// TODO: wire to lancerd — no pause-all/
emergency-stop RPC exists yet`. Confirmed by grep: no such RPC exists anywhere in the daemon. The
responsibility matrix already promises this as a LancerMac responsibility — this is a build-out gap
to close, not a new feature to invent, and it directly relates to the non-atomic emergency-stop gap
already found in the Governance area (§1) — the same underlying daemon primitive is missing on both
the iOS and Mac sides.

### Competitor findings

- **Happier**: its desktop app is explicitly **not** a thin companion — the same React Native
  codebase used for iOS/Android/web, wrapped in Tauri, with full feature parity including an embedded
  terminal dockable full-screen. Happier chose exactly the "clone the mobile app onto desktop" path
  that Lancer's responsibility matrix explicitly rejects.
- **Orca**: the cleanest real precedent for a desktop-heavy/mobile-light split — desktop owns parallel
  worktrees, account switching, rich previews, Computer Use; mobile is explicitly scoped to "monitor
  and steer... get notified... send follow-ups," not orchestrate. This validates LancerMac's direction,
  but for a different underlying reason: Orca's desktop needs to be heavy because its orchestration
  logic lives in a GUI, whereas Lancer's own git-worktree-per-run isolation already runs headlessly
  inside `lancerd` with no GUI required — Lancer doesn't need an Orca-style heavy Mac app to get the
  same capability.
- **Vibe Kanban**: its desktop surface (Tauri-wrapped) is its entire orchestration UI with no separate
  mobile client at all — another data point that competitors building a native desktop surface tend
  to make it the primary, not a scoped utility.
- The structured competitive dataset has zero entries for "menu bar" utilities — either genuine
  whitespace or just outside what the audit's dimensions capture; can't distinguish which.

### Platform findings

- **macOS menu-bar Live Activities are a Continuity/mirroring feature**, not native macOS ActivityKit
  support — a Mac Handoff-paired to the same Apple ID's iPhone (BT+Wi-Fi in range, iOS 18+) already
  gets Lancer's existing iOS Live Activity mirrored into its menu bar automatically, with **zero new
  LancerKit code**. This predates LancerMac's macOS 15 minimum target — it's OS-level behavior, not
  an API to adopt. Caveat: only works for a dev's own personal Mac paired to their own iPhone —
  irrelevant for remote/headless Linux hosts, or a Mac signed into a different Apple ID.
- No macOS-27-specific MenuBarExtra API change found that would affect LancerMac's existing approach.

### Feature ideas

- **ALREADY_COVERED — Wire real Pause-All/Emergency-Stop RPCs into `lancerd`'s control IPC**: not new
  scope, already locked in the responsibility matrix, UI already stubbed — a build-out gap to close.
- **NEW — Confirm the mirrored Live Activity renders legibly small in the Mac menu bar**, and document
  the Handoff prerequisite so its absence (remote host, different Apple ID) isn't mistaken for a
  LancerMac feature gap. Small, additive, free distribution once the existing Live Activity is solid.

### Flags

- The Pause-All/Emergency-Stop gap here is the same underlying missing daemon primitive already
  flagged in Governance (§1) — one fix closes both.
- The mirrored-Live-Activity finding is genuinely Continuity/system behavior, not a LancerMac
  capability — don't describe it in any spec as "LancerMac gets Live Activities."
- This pass found no competitive or platform evidence arguing for expanding LancerMac's scope, and
  one concrete architectural reason (headless worktree isolation already lives in `lancerd`) that
  staying thin isn't just a positioning choice but matches where the orchestration logic actually is.

---

## 9. Mobile-Primary Cockpit remainder

Covers the 6 named pillars from the 24-pillar pivot inventory not already folded into Away Mode:
Touch-Native Repo Browser, Micro Editor, Agent Patch Composer, Developer App Drawer, Project Memory/
Notebook, Team and Client Proof Layer, and the broad (non-"Light") version of Automations for Code.

### Verdict per pillar

| Pillar | Status | Why |
|---|---|---|
| **Touch-Native Repo Browser** | ALIVE | No non-goal conflict *if* symbol indexing/dependency-mapping happens host-side via the daemon, not an on-device language server. Orca proves the pure browse/preview version is real and shippable (`MobileFileExplorerPanel.tsx`). Partially overlaps with the already-carried Changed Files Review, but whole-repo search/browse/symbol-jump is net-new. |
| **Micro Editor** | CONFLICTS_WITH_NONGOAL | Directly conflicts with the "no local iOS code editor" non-goal, and already explicitly cut in the Away Mode sweep. Even Orca's own inline-editing code scopes strictly to narrow terminal-scratch-artifact files, never general worktree files — the strongest available competitor precedent still draws the same line Lancer already drew. Treat as closed. |
| **Agent Patch Composer** | ALREADY_COVERED | Agent-directed, not manual editing, so no non-goal conflict — but almost entirely overlaps with already-approved Mobile/Visual Diff Review and already-carried Run Comparison. The one thin net-new slice (selection-scoped "rewrite just this") is small enough to fold into existing diff review rather than a separate pillar. |
| **Developer App Drawer** | CONFLICTS_WITH_NONGOAL | The clearest internal-consistency conflict found in this whole pass: `ARCHITECTURE.md` §4.1 is explicit that the sidebar has exactly 5 destinations and says "do not reintroduce a tab bar" — a prior Fleet/Activity/Control multi-root layout was already deprecated. This pillar's 14-mini-app drawer reintroduces that exact rejected shape under a new name. No competitor precedent found either way. Needs an explicit owner call before any design work. |
| **Project Memory / Notebook** | ALIVE | No non-goal conflict, genuine competitor gap — neither Happy nor Happier (despite Happier being materially more advanced elsewhere) has anything like it. Needs one scoping decision before building: it's adjacent to but undifferentiated from the already-carried "Repo Playbook" (named only, no code, no defined scope beyond mission-composer defaults) — Repo Playbook should stay "smart defaults feeding the composer," Notebook should be "a standalone browsable knowledge surface," or the two will duplicate. |
| **Team and Client Proof Layer** | ALIVE (partially already shipped) | No non-goal conflict. Roughly half of this is already done and uncredited by the pivot doc: TeamRole/TeamRoleStore, PolicyPreset, and an `agent.audit.export` RPC shipped from the 2026-06-24 Governance Home build. Genuinely net-new: client-safe redacted export, shared proof links (**Happier already ships this — a real, shipped competitor gap**), weekly AI work report, approval delegation, team-wide (not just solo-phone) emergency stop. |
| **Automations for Code (broad)** | CONFLICTS_WITH_NONGOAL | Already explicitly considered and narrowed to "Light Automations" in the Away Mode sweep for exactly this reason — the full rule engine competes with agent judgment. This pillar's broad framing is the version already declined; treat as closed unless a specific narrow trigger is separately proposed. |

### Competitor findings

- **Orca** ships a real touch-native repo browser (lazy file tree, RPC-fetched, markdown/syntax
  preview) — proof this pillar is buildable and non-conflicting.
- **Orca** also has real inline editing — but scoped strictly to "terminal artifact" scratch files
  via an explicit narrow grant, never general worktree files. Even the strongest read-write
  competitor precedent draws the same line Lancer's non-goal already draws.
- No "app drawer"/mini-apps-store pattern exists in Orca, Vibe Kanban, or OpenCode — no precedent
  either way.
- **Happier already ships session public-share links** (`SessionShareDialog.tsx`, `PublicLinkDialog.tsx`)
  — exactly the "shared proof links" piece of Team and Client Proof Layer that Lancer doesn't have.
- Neither Happy nor Happier has any persistent per-project notes/knowledge-base feature — the only
  "notebook" hit in either repo is an unrelated Jupyter tool-call UI renderer.

### Platform findings

- **TextKit** (WWDC26 session 370): a new viewport-rendering API plus caching for text attachments,
  explicitly demonstrated for line numbers and collapsible code sections — directly relevant if the
  Repo Browser is ever built (Orca had to hand-roll this client-side). iOS-27-gated, consistent with
  the version-gated fast-follow pattern already recommended for iOS 27 features generally.
- Xcode 27's own new Code Assistant Extensions API validates Lancer's Agent Patch Composer
  positioning — Apple is building the same agent-patch-review UX, just desktop-only inside Xcode. No
  iOS-side API to consume from this, competitive context only.
- No iOS 27 API found specifically for "reading source code on a phone screen" beyond the already-
  cataloged Foundation Models/Vision findings and TextKit above — confirms this remains a
  client-rendering problem Lancer must solve itself, as Orca did.

### Flags

- Developer App Drawer directly contradicts a locked, dated `ARCHITECTURE.md` §4.1 nav decision —
  needs an explicit owner call before any design work, not quiet inclusion in a roadmap bucket.
- Micro Editor is simultaneously a non-goal violation *and* already cut in the Away Mode sweep — it
  shouldn't resurface as "Next Layer" roadmap material in the pivot doc without that contradiction
  being resolved on the page itself.
- Automations for Code (broad) as written in the pivot doc is the version already rejected in favor
  of Light Automations — the pivot doc itself doesn't flag this, so a reader following only that doc
  would think it's still open.
- Project Memory/Notebook and the already-carried Repo Playbook are adjacent, undifferentiated
  concepts — whoever builds either first should define the boundary explicitly.
- Team and Client Proof Layer overlaps substantially with already-shipped Governance Home work that
  the pivot doc doesn't credit — reads as if fully net-new when roughly half is already done.

---

## Cross-cutting flags worth an owner decision, gathered across all 9 areas

1. **"Biometric gate removed for V1" is stale** (see headline correction above) — `ARCHITECTURE.md`
   and the 2026-07-02 competitive baseline both need this corrected to "reinstated, risk-tiered for
   high/critical decisions" per commit `695d2440`. Anything built or marketed on the old claim should
   be re-checked.
2. **The reinstated biometric gate has one real, still-open hole**: `BiometricGate` degrades open
   (returns success) on any unlocked device with no passcode configured, and the new high/critical
   gate inherits this exactly. This is now the single most actionable security fix in the whole
   consolidation — it directly undercuts a governance-critical control that was just built.
3. **The Watch app ships to zero real users** — fully built and tested, but not embedded in the iOS
   app target for simulator-testability reasons. One of the highest-leverage fixes found in this
   pass: real, tested code that currently reaches nobody.
4. **Emergency stop is not atomic, on either the phone or LancerMac** — the iOS client loops per-run
   stop messages instead of one daemon-side stop-all command, and LancerMac's own Pause-All/
   Emergency-Stop buttons are disabled stubs waiting on the same missing daemon RPC. One fix closes
   both gaps.
5. **The audit hash chain has no external anchor** — tamper-evident against accidental corruption,
   not against a compromised host that could regenerate a fully self-consistent fake chain.
6. **JWT is still HS256-only** — no JWKS/RS256 path; a real risk if the production Supabase project
   is ever configured to sign RS256.
7. **Three uncoordinated paid mechanisms**, one of which (the StoreKit IAP) is fully built but wired
   to gate nothing.
8. **The daemon has exactly one pairing slot system-wide** — a more fundamental fleet-scaling ceiling
   than the phone-side 3-machine cap, already filed as an unresolved P1.
9. **`Happier` (happier-dev/happier) is a materially more advanced fork of `happy` and isn't tracked
   in `competitors.jsonl` at all** — recommend adding it as its own competitor entry; it ships live
   session handoff, an opt-in embedded terminal, session public-share links, and enterprise
   SSO/OIDC/mTLS that the current dataset has no visibility into.
10. **Developer App Drawer directly contradicts a locked `ARCHITECTURE.md` §4.1 nav decision**
    (exactly 5 sidebar destinations, no tab bar) — needs an explicit owner call before any design
    work, not quiet inclusion in a future roadmap bucket.
11. **The `ARCHITECTURE.md` §2 (iOS 27.0+) vs. `project.yml` (`IPHONEOS_DEPLOYMENT_TARGET: "26.0"`)
    discrepancy recurs across nearly every area researched** — worth resolving once, centrally,
    rather than continuing to flag it area-by-area. None of the findings above are blocked by it
    either way, but it should be reconciled before it causes a real mistake.

## Sources

External (new to this pass, in addition to the Away Mode doc's list):
- [App Intents background execution, iOS 27](https://blakecrosley.com/blog/app-intents-ios-27-background-execution)
- [WWDC26 App Intents capabilities](https://matthewcassinelli.com/wwdc26-sessions-new-capabilities-app-intents-framework/)
- [iOS 27 security/App Intents authenticationPolicy](https://www.nowsecure.com/blog/2026/06/11/ios-27-security-what-wwdc-2026s-ai-features-mean-for-mobile-app-risk/)
- [What's new in UIKit, iOS 27](https://ikyle.me/blog/2026/whats-new-in-uikit-ios-27)
- [CKSyncEngine](https://mjtsai.com/blog/2026/04/01/cksyncengine/)
- [Silent push reliability](https://www.courier.com/blog/firebase-cocoapods-support-is-ending-what-happens-to-ios-push-notifications)
- [watchOS 27 roundup (Smart Stack)](https://www.macrumors.com/roundup/watchos-27/)
- [WWDC26 session 206 — device management/fleet health](https://developer.apple.com/videos/play/wwdc2026/206/)
- [WWDC26 session 223 — Live Activities essentials (Continuity/menu-bar mirroring)](https://developer.apple.com/videos/play/wwdc2026/223/)
- [WWDC26 session 370 — Elevate your app's text experience with TextKit](https://developer.apple.com/videos/play/wwdc2026/370/)
- [WWDC26 session 258 — Xcode 27 Code Assistant Extensions / Swift Assist](https://developer.apple.com/videos/play/wwdc2026/258/)
- [LAPolicy.deviceOwnerAuthenticationWithBiometricsOrWatch (ruled out, macOS-only)](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometricsorwatch)

Cloned competitor repos used this pass: `research_repos/{omnara,opencode,vibe-kanban,happy,happier,orca}/`

Internal: `ARCHITECTURE.md` §0.1/§1/§1.1/§2/§4.1/§8.5/§10.2/§11.2, `docs/KNOWN_ISSUES.md`,
`docs/legal/SECURITY_ARCHITECTURE.md`, `docs/product/mac-ios-responsibility-matrix.md`,
`docs/plans/macos-host-implementation.md`,
`docs/competitive-intelligence/{data,reports}/*`, `docs/_archive/away-mode-2026-07/2026-07-04-away-mode-master-consolidation.md`
