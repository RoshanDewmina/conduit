# Feature Checklist for Workflow-by-Workflow Wireframing

Prepared: 2026-07-05
Updated: 2026-07-05 — corrected and extended after an independent two-round subagent verification
pass against all 5 source sessions (plus a 6th session discovered during verification, see below),
the wireframe HTML itself (grepped directly, not caption-trusted), and 6 existing synthesis docs.
Status: working checklist to drive the Mobbin + wireframe pass, one feature/workflow at a time
Compiled from a full read of 5 sessions (see Source Sessions below) plus the existing consolidated
docs. This is not a decision doc — it's the punch list Codex's design session should work through,
feature by feature, checking off what's already wireframed vs. what still needs a pass.

**Read section 6 and 7 first** — they contain corrections to sections 1-5 below (a few "wireframed"
calls were wrong) and net-new features the first compile missed entirely.

## How to read this

- **Board section** = where it lives in `docs/design-audit/lancer-workflows-2026-07-05/artifacts/` (HTML wireframes)
  (sections: onboarding, home, workspaces, thread, launch-setup, artifact-views, ship-history,
  fast-follow, review, settings, final-ia, handoff). "—" means not yet represented anywhere.
- **Status**: `wireframed` (has a screen/view already) / `named-only` (decided but no screen yet) /
  `gap` (discussed but never captured in any doc or board).

---

## 1. Core Away Mode Loop (V1)

| # | Feature | Board section | Status |
|---|---|---|---|
| 1 | Away Launch Composer + thin launch contract (persistent bottom composer, Cursor-style) | home, thread, launch-setup | wireframed |
| 2 | Mobile attachments (photo/screenshot/video/voice note) in composer | launch-setup | wireframed |
| 3 | Share Sheet / Universal Link Intake (GitHub/Linear/Sentry/Clips/Loom/Jam/Safari) | launch-setup | wireframed |
| 4 | Smart Default Target (last successful machine/repo/agent chip) | thread, workspaces | wireframed |
| 5 | Away Mode Setup (progressive per-repo setup checklist) | launch-setup | wireframed |
| 6 | Repo Playbook (test/build/lint cmd, dev server port, PR branch, protected zones) | launch-setup | wireframed |
| 7 | Agent Readiness Check (preflight: machine online, agent available, notifications on) | launch-setup | wireframed |
| 8 | Run Mode (Strict / Normal / Hands-off until proof / Ask first) | launch-setup (folded into "Mission Defaults") | wireframed |
| 9 | Run Budget (time/retry/cost limits) | launch-setup (folded into "Mission Defaults") | wireframed |
| 10 | Interruption Budget (Quiet/Normal/Active/Focus) | launch-setup (folded into "Mission Defaults") | wireframed |
| 11 | Minimal Away Status (phase, elapsed time, last milestone, needs-action flag) | thread, home | wireframed |
| 12 | Question Cards / Question Ladder (glance → lock-screen chips → evidence reveal → typed instruction → contract update) | artifact-views | wireframed |
| 13 | Away Digest as Home (needs-you-first ordering: blocked → failed proof → risky → ready → quiet) | home | wireframed |
| 14 | All-clear / no-urgent-work state | home | wireframed |
| 15 | Proof Suite base layer (test result card, changed-file summary, screenshot/preview evidence) | thread | wireframed |
| 16 | Proof Reel (short video proof) | thread | wireframed |
| 17 | Proof Timeline (video + steps/logs/network synced) | thread | wireframed |
| 18 | Visual Diff Review (before/after screenshots, approve/reject/comment) | proof-gaps (panel B) | **wireframed 2026-07-05** — added as its own section, reusing the `compare-grid` pattern already proven in `fast-follow` |
| 19 | Device Matrix Proof (iPhone/iPad/dark mode/large text grid) | proof-gaps (panel A) | **wireframed 2026-07-05** — new `.device-grid`/`.device-tile`/`.status-badge` pattern, Mobbin ref: [Airtable status-badge tile grid](https://mobbin.com/screens/dc0fd8d2-c542-4035-ab72-d35e73fb3941) |
| 20 | Auto Bug Replay (before-failing / after-passing side by side) | proof-gaps (panel C) | **wireframed 2026-07-05** — new `.replay-stack`/`.replay-row` pattern, Mobbin ref: [Turo before/after damage report](https://mobbin.com/screens/54258d9f-cc90-4f59-b111-d7c0cdada5d2) |
| 21 | Slide-to-Compare diff viewer (Photos-style before/after slider) | — | **gap — CORRECTED. Was wireframed in the earlier, superseded 84-screen `~/Downloads/lancer-wireframe-2026-07-04.html`, but never carried into the current committed board; zero hits in the final HTML** |
| 22 | Auto-Highlight Diff Frame (vision-diffing marks the exact change moment) | — | **gap — CORRECTED, same as #21: wireframed only in the superseded artifact, absent from the current board** |
| 23 | Time-Travel Scrubber (drag across mission, see real repo state at that point) | fast-follow (panel D: "Time travel / fork / Clips") | wireframed — **section corrected: lives in `fast-follow`, not `thread`** |
| 24 | Fork-From-Timestamp ("continue from here" new mission) | fast-follow (panel D) | wireframed — **section corrected: lives in `fast-follow`, not `thread`** |
| 25 | Searchable Proof Transcripts (speech-to-text, tap-to-jump, cross-mission search) | — | **gap — CORRECTED, same as #21: wireframed only in the superseded artifact, absent from the current board** |
| 26 | Mobile QA Annotation (pause proof, circle/tap frame, dictate, send back) — headline feature | artifact-views | wireframed |
| 27 | Error Autopsy (failed-run card: last good step, failure screenshot/log, likely cause, actions) | artifact-views | wireframed |
| 28 | Stop and Snapshot (stop + preserve diff/log/proof, no auto-revert) | review, home | wireframed |
| 29 | Emergency Stop (atomic, distinct from Stop-and-Snapshot) | review, settings | wireframed |
| 30 | Git / PR / Merge Actions (commit, push, create/update PR, view checks, merge with proof gate) | ship-history | wireframed |
| 31 | Flight Recorder (scrubbable per-run timeline) | ship-history | wireframed |
| 32 | Work Search (search across runs/proof/files/PRs) | ship-history | wireframed |
| 33 | Web Preview / Preview Cockpit (open dev server, tap around, capture, send issue) | launch-setup / artifact-views | wireframed |
| 34 | Contextual Command Cards (run tests, restart preview, stop — contextual not toolbar) | artifact-views | wireframed |
| 35 | Changed Files Review (hunk-level comment/send-back, no full editor) | thread | wireframed |
| 36 | Voice Everywhere (dictation at every input point) | demoted to footnote callout | wireframed (footnote) |
| 37 | Light Automations (remind me later, rerun proof tomorrow, notify on CI fail, pause until morning) | artifact-views | wireframed |
| 38 | Provider Capability Badges (supports images / resume / structured questions / PR / cost data) | workspaces (agent picker) | wireframed |

## 2. Governance / Security (parallel track, not Away Mode UI but touches it)

| # | Feature | Board section | Status |
|---|---|---|---|
| 39 | Biometric approval gate (risk-tiered, reinstated `695d2440`) | review, settings | **built and wired in real code, not just wireframed** — `ApprovalDecisionAuth.swift:15-18`, wired into `InboxView.swift`/`ApprovalRelay.swift`, confirmed by two independent verification passes. UI representation on the board is a bonus, not the source of truth. |
| 40 | Biometric degrade-open fix (no-passcode hole) | — (code fix, not UI) | n/a — implementation plan only (governance-hardening plan Task 1) |
| 41 | Atomic Emergency Stop / Pause-All daemon RPC | review, settings (UI) | UI wireframed; **daemon-side RPC confirmed still missing** (no `emergencyStop`/`pauseAll` in `daemon/lancerd/*.go`) — see governance-hardening plan Task 2. The iOS-side per-run-loop stop is real, functioning, non-atomic code, not a mockup. |
| 42 | Audit chain external anchor | settings (audit export) | wireframed (UI) / gap (backend) |
| 43 | Policy engine (existing) — presets, simulate | settings, fast-follow (deeper) | named-only |
| 44 | Policy Diff Review (governance changes reviewed like a code diff, second-approver) | fast-follow | wireframed |
| 45 | Drift detector (doc/instruction rot scanner, existing) | settings | named-only |
| 46 | Cross-host policy-consistency check | fast-follow / settings | wireframed |
| 47 | On-device audit digest (Foundation Models summarizing audit.log) | fast-follow | wireframed |

## 3. Fast-Follow / Differentiator Features

| # | Feature | Board section | Status |
|---|---|---|---|
| 48 | Cross-Vendor Second-Agent Review (one-tap independent check by another CLI) | fast-follow (panels A/B/C) + thread (panel F) | **wireframed 2026-07-05, promoted from a single vague panel to 4**: vendor picker (A), agree verdict (B), disagree verdict (C, new — structured Confirmed/Flagged/Also-checked), plus a risk-tiered 3rd rail action in Work Thread (panel F) that only appears on high/critical-risk missions. Stays a Fast Follow by default; only earns a permanent rail slot when risk warrants it. |
| 49 | Proof Becomes Regression / Regression Watchlist | fast-follow | wireframed |
| 50 | Clips (Builder.io) integration — Clip-In → Mission | fast-follow | wireframed |
| 51 | Clip-Out (Lancer proof published as Clips-compatible artifact) | fast-follow | wireframed |
| 52 | `lancer.proof` JSON schema (portable, agent-readable proof format) | fast-follow | named-only |
| 53 | Run Comparison (single-vendor A/B, rerun with tweaked constraint) | fast-follow | wireframed |
| 54 | Multi-Agent Showdown (compare 2+ vendors side by side) | — | **gap — only named, resurfaces if #48 ships** |
| 55 | Weekly Away Mode Digest (retention: "shipped 4 fixes, 90% pass rate") | fast-follow | wireframed |
| 56 | Frustration Signal Missions (rage-click/dead-click auto-propose mission) | — | **cut for V1 per Claude's redundancy pass — confirm still cut** |
| 57 | True Handoff (Apple Continuity — exact scroll/hunk position on Mac) | fast-follow | wireframed |
| 58 | Siri / App Intents status query ("what's the status of the checkout fix?") | fast-follow | wireframed |
| 59 | StandBy mode / full-screen proof widget | fast-follow | wireframed |
| 60 | Interactive Home Screen widget (not just Live Activity) | fast-follow | wireframed |
| 61 | Watch app packaging (embed in iOS target so it reaches real users) | fast-follow (whole-app V2) | **CORRECTED from "named-only": the Watch app is a fully built, tested 4-tab watchOS app with live WatchConnectivity sync. The actual gap is a `project.yml` embed-target exclusion — a packaging/CI decision, not missing implementation.** |
| 62 | Team / Client Proof Layer, Proof Share Link | fast-follow / ship-history | wireframed |
| 63 | Account Switcher / multi-account hot-swap per vendor | fast-follow (new "competitive edge" batch) | wireframed |
| 64 | Vendor Performance comparison (revert-rate by vendor, same repo) | fast-follow (new batch) | wireframed |
| 65 | Continuous Cross-Vendor Audit (one unbroken hash chain across a vendor switch) | fast-follow (new batch) | wireframed |
| 66 | Compliance Export (audit chain as signed report for a compliance/security buyer) | fast-follow (new batch) | wireframed |
| 67 | Mobile Command Palette (Cmd+K global action launcher, distinct from Work Search) | command-context (panel A) | **wireframed 2026-07-05** |
| 68 | Inline mobile git blame (tap a diff line → "added 3 weeks ago, fixing X") | proactive-signals (panel C) | **wireframed 2026-07-05** |
| 69 | Dependency/security alert intake (Dependabot/Snyk → mission candidate) | proactive-signals (panel A) | **wireframed 2026-07-05** |
| 70 | Container/dev-service status (Docker Compose services up/down in Away Status) | proactive-signals (panel B) | **wireframed 2026-07-05** |
| 71 | Slack/Teams-triggered missions (@-mention to kick off/check a task) | command-context (panel C) | **wireframed 2026-07-05** |
| 72 | Whole-thread context ingestion (paste a full Slack/Linear thread, not one message) | command-context (panel B) | **wireframed 2026-07-05** |

## 4. Whole-App Areas (deferred / V2, own board section already)

| # | Area | Board section | Status |
|---|---|---|---|
| 73 | Workspaces (renamed Machines; repo/folder list first, host health in detail sheet) | workspaces | wireframed |
| 74 | Fleet & Machines management deeper (pairing, diagnostics, fingerprints, revoke) | workspaces (detail) | wireframed |
| 75 | Terminal / SSH escape hatch (already built, just unwired from V1 nav) | — | named-only, deliberately off primary UI |
| 76 | Settings / Trust Center / Security (native grouped list) | settings | wireframed |
| 77 | LancerMac (desktop companion, keep thin) | fast-follow (V2, desktop-frame mockups) | wireframed |
| 78 | Cross-device sync (CloudKit conversation continuity) | — | named-only, not on board as a screen |
| 79 | Billing (3 uncoordinated mechanisms need 1 decision) | fast-follow / settings | wireframed (pricing screen simplified — real consolidation decision still open). **Caveat: "gates nothing" is not uniformly true — the one-time StoreKit IAP (`isPro`/`showingPaywall`) is genuinely dormant, but a separate Stripe cloud/hosted-agent entitlement (`PurchaseManager.hasCloudEntitlement`) does gate real functionality. Don't flatten these into one status.** |
| 80 | Onboarding / Pairing (code-only, Cursor-simple first run) | onboarding | wireframed |
| 81 | Notification permission pre-prompt + denied-state recovery | onboarding | wireframed |

## 5. Final IA / Navigation

| # | Item | Board section | Status |
|---|---|---|---|
| 82 | Visible roots: Home, Workspaces, Settings (sparse, Cursor-simple) | final-ia | wireframed |
| 83 | "Needs Attention"/Inbox folded into Home/Away Digest (not a separate root) | final-ia | wireframed — **confirm this matches the REAL current app, which has Inbox as its own sidebar row today** |
| 84 | Governance folded into Settings (not a separate sidebar root) | final-ia | wireframed — **same caveat: real app currently shows Governance as its own sidebar row** |

---

## Known open threads worth resolving before/while wireframing

1. **Nav discrepancy never fully closed.** The Claude session flagged that real screenshots show 4
   sidebar items (Home, Inbox, Machines, Governance) + New Chat CTA + gear-icon Settings — not the
   "5 locked destinations" the whole brainstorm assumed from `ARCHITECTURE.md` §4.1. The wireframe's
   Final IA (Home/Workspaces/Settings only) is a **proposed simplification**, not confirmed against
   current code. Worth a quick check against `AppRoot.swift`/`SidebarShellState.swift` before treating
   it as locked.
2. **`&` HTML entity / button-contrast bugs** were caught and fixed by Codex mid-session — already
   resolved, no action needed.
3. **Billing consolidation** (3 mechanisms → 1 decision) is flagged everywhere but never actually
   decided — the wireframe's pricing screen is illustrative, not a real answer.
4. **Cross-Vendor Second-Agent Review** was cut in the `019f2ebf` walk-through, then reconsidered by
   Claude, then re-added to fast-follow by Codex. Confirm this is the final call before spending real
   design time on it.
5. **Frustration Signal Missions** — the term does not appear anywhere in the final committed board
   (confirmed by direct grep), so the practical outcome is "cut." But this was a proposal Claude made
   mid-session during a redundancy pass, not a decision the owner explicitly confirmed — the user's
   next message pivoted to "include everything we're missing" rather than confirming the cut. Treat
   as **cut by omission, not by clean owner decision** — worth a 10-second confirmation before
   treating it as permanently off the table.

## 6. Corrections and Additions from Verification Pass (2026-07-05)

A two-round subagent verification (all 5 original sessions plus 6 existing synthesis docs, with the
wireframe HTML grepped directly rather than caption-trusted) found the corrections already folded
into sections 1-5 above (marked "CORRECTED"), plus the net-new items below that weren't in the first
compile at all.

### 6a. Confirmed missing — add to the design-pass queue

| # | Feature | Source | Notes |
|---|---|---|---|
| 85 | Tap-to-Segment Bug Capture (Vision tap-to-segment in composer) | launch-setup (section note) | **resolved 2026-07-05 as a consolidation**: noted as the input-time twin of item 95's Vision-mask capability, not a separate build |
| 86 | On-Device Contract Drafting (Foundation Models drafts goal/scope from a screenshot) | platform-intelligence (panel A) | **wireframed 2026-07-05 as part of consolidated "on-device compression" pattern** |
| 87 | Full-Screen "Quick Mission" Widget | platform-intelligence (panel C) | **wireframed 2026-07-05 as one of 4 states in the consolidated widget template** |
| 88 | Session-Survives-Disconnect Signal ("reconnected after network drop" in Away Status) | platform-intelligence (section note) | **resolved 2026-07-05**: noted as a minor Away Status state variant, not drawn as its own screen |
| 89 | Landscape Dynamic Island Mission Strip | platform-intelligence (section note) | **resolved 2026-07-05**: same treatment as item 88 |
| 90 | "Read Me the Status" on-demand voice narration | platform-intelligence (panel A) | **wireframed 2026-07-05 as part of consolidated "on-device compression" pattern** |
| 91 | Siri-Answerable Question Cards (View Annotations API) | platform-intelligence (panel B) | **wireframed 2026-07-05 as part of consolidated Siri pattern** |
| 92 | Multimodal Clarifying Cards | platform-intelligence (panel A) | **wireframed 2026-07-05 as part of consolidated "on-device compression" pattern** |
| 93 | On-Device Proof Narration | platform-intelligence (panel A) | **wireframed 2026-07-05 as part of consolidated "on-device compression" pattern** |
| 94 | Semantic Diff Captions | platform-intelligence (panel A) | **wireframed 2026-07-05 as part of consolidated "on-device compression" pattern** |
| 95 | Tap-to-Isolate Annotation (Vision-mask upgrade of Mobile QA Annotation) | artifact-views (panel C, upgraded) | **wireframed 2026-07-05 as a real visual upgrade** (dashed Vision-mask outline replacing the old hand-drawn circle pin) to the existing panel, given real design attention as its own priority-#2 item rather than folded into a caption |
| 96 | Full-Screen "Proof Ready" Widget + Full-Screen "Decide Now" Widget | platform-intelligence (panel C) | **wireframed 2026-07-05 as 2 of 4 states in the consolidated widget template** |
| 97 | Siri Multi-Step Decision Batch | platform-intelligence (panel B) | **wireframed 2026-07-05 as part of consolidated Siri pattern** (follow-up chip after the status answer) |
| 98 | Atomic server-side `agent.emergencyStop` RPC (named distinctly) | lancer-whole-app-consolidation §1 | this is the backend half of item 41 — call it out as its own build task |
| 99 | JWKS/RS256 JWT verification path (fixes HS256-only gap) | lancer-whole-app-consolidation §7 | backend fix, not a screen |
| 100 | Fleet-wide status widget + interactive widget actions (stop/approve from widget, fleet-scale) | platform-intelligence (panel C) | **wireframed 2026-07-05 as the 4th state ("Fleet-wide") in the consolidated widget template**, distinct from item 60 which is single-mission scoped |
| 101 | Touch-Native Repo Browser | workspace-depth (panel A) | **wireframed 2026-07-05** |
| 102 | Project Memory / Notebook | workspace-depth (panel B) | **wireframed 2026-07-05** — explicitly distinct from Repo Playbook (operational config vs. knowledge/notes) |
| 103 | Agent Patch Composer | 24-pillar pivot doc | verdict ALREADY_COVERED — overlaps with Changed Files Review + Run Comparison, but never named as such anywhere; add a pointer note so it doesn't get "rediscovered" as a gap later |

### 6b. Explicitly closed — add as rows so nobody reopens them by accident

| # | Item | Status | Source |
|---|---|---|---|
| 104 | Micro Editor | **CLOSED — conflicts with `ARCHITECTURE.md` non-goal** ("no local iOS code editor") | 24-pillar doc + whole-app consolidation |
| 105 | Developer App Drawer | **CLOSED — conflicts with locked 5-destination sidebar IA, reintroduces rejected multi-root clutter** | whole-app consolidation |

### 6c. Six explicit V1 cuts never captured anywhere in the original 84-item checklist

All six were proposed by Claude in the free-association "wow ideas" pass and explicitly cut by the
owner ("i think im good with 1-5, the others are not the best or just too much effort to implement
for not sure gains") — confirmed absent from the final board by direct grep. Listed here purely so
they don't get silently re-proposed:

- Live Activity Risk Meter (continuous risk gauge in Dynamic Island)
- Haptic Risk Language (distinct haptic patterns per event tier)
- Live Shadow Second Opinion (always-on background second-agent watcher)
- Break-Point-Aware Nudges (Calendar/Focus-aware review timing)
- Live Camera Bug Repro (point phone camera at a second screen to report a bug)
- Big Agent Router ("send to best agent" auto-routing — superseded by Smart Default Target)

## 7. Note on Source Sessions — a 6th session exists

Verification found a 6th relevant session not in the original list of 5: Codex
`019f2e40-bf54-7830-b4eb-be1e156cf17f` ("Continue brainstorming thread," 2026-07-04 13:50-14:05) —
this is the session that actually produced the 24-pillar mobile-primary-cockpit inventory. Its
content reaches this checklist secondhand via `docs/product/2026-07-04-lancer-mobile-primary-pivot-feature-inventory.md`
and is cited directly in `away-mode-master-consolidation.md` §2 row 2. Not re-read in full for this
pass since its output is already captured in the pivot doc, but flagging its existence for completeness.

## Source Sessions Read (full transcripts, this pass)

- Codex `019f2dec-b131-7fa2-b96a-ca5dca31b095` — original brainstorm, differentiation, proof harnesses, Clips
- Codex `019f2ebf-513f-73e0-91ff-13cd74e0a412` — "Review features one by one," the definitive V1 feature walk
- Codex `019f2f6d-e4d8-7c11-aa1f-532e5d28c506` — independent verification of Claude's consolidation docs
- Claude Code `6ca8a207-be32-4400-aafd-5eee1970c012` — second opinion, whole-app research, 84-screen wireframe
- Codex `019f2ffd-eb61-72d1-928f-f60a8cd4cf5e` — Mobbin-driven final design pass, produced the current board

Plus the existing synthesis: `docs/product/2026-07-04-lancer-strategy-feature-source-of-truth.md`.
