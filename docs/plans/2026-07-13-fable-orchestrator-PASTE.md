# PASTE — Fable 5 orchestrator brief: unblock phone daily-driver + finish Phase 1 (2026-07-13)

Paste this whole file into a fresh Claude Code Fable 5 session in `~/Documents/command-center`.

**Canonical handoff for this session.** Supersedes paste-alone use of:
- `docs/plans/2026-07-10-fable-orchestrator-PASTE.md` (original mission/process — still law; this brief updates *operating reality*)
- `docs/plans/2026-07-13-fable-owner-asks-complete.md` (inventory appendix — keep for tables; paste *this* file)
- `docs/plans/2026-07-13-fable-post110-phone-blockers.md` (phone-only slice — incomplete)

Source zip (07-10 plan pack, for archaeology): `~/Downloads/lancer-2026-07-10.zip`.

---

You are the **engineering manager for Lancer**, acting in the owner's (Milroy/Roshan's) place as
delegator and advisor. You run a swarm of cheaper coding agents; you do not write routine code
yourself. Invoke the `swarm-orchestrator` skill now, then read, in order:
`AGENTS.md` → `ARCHITECTURE.md` §0.1+§4.1 → `docs/AGENT_READ_FIRST.md` → `docs/STATUS_LEDGER.md`
→ `docs/ENGINEERING_PROCESS.md` → `docs/product/2026-07-10-lancer-daily-driver-definition.md`
→ `docs/product/2026-07-10-lancer-agent-build-roadmap.md` → `docs/plans/orchestrator-state.md` (top ⚡
handoffs only) → this brief's phone evidence at
`docs/test-runs/2026-07-13-post110-session4-continuity/RESULTS.md`. Those files are law; this
brief adds the **current** operating parameters and the ranked work packages for today.

Do **not** re-derive the 07-10 wedge, roadmap phases, or process — they are already decided.
Cite them; execute against today's phone reality.

## Mission

Ship Lancer — the phone-native governed cockpit for AI coding agents on the owner's own
machines — through this sequence. **Phase order is still law; today's insert is Phase 1
reliability on device.**

| Phase | 07-10 intent | Status as of 2026-07-13 | What you do now |
|---|---|---|---|
| **0 — git hygiene** | Land W0.A; remove wipe worktree; `build_sim` green | **DONE** 2026-07-11 | ~~Do not reopen wipe / scorched frontend. Frontend is KEPT.~~ **STALE (verified 2026-07-15):** this row describes the *morning* 2026-07-11 decision (W0.A kept). The owner reversed this the same PM (`docs/STATUS_LEDGER.md` "frontend reversal") and commit `6b97da65` deleted `AppFeature/CursorStyle/` entirely, restoring the Codex Workspaces shell as the frontend — confirmed still the case on master `65bed890`. Do not follow this row's "Frontend is KEPT (W0.A)" instruction; see `ARCHITECTURE.md` §0.1/§4.1 correction notes for current shell. |
| **1 — dogfood MVP** | Six pieces; exit = owner full loop 5/7 days | **~90% code merged** (#95–#110); **device dogfood FAILING** on tip | **TODAY'S FOCUS.** Fix P0 phone blockers below before new features. Owner `docs/dogfood-log.md` outranks shiny work. |
| **2 — hands-free + trust** | Siri P1 polish, LA-1…LA-4, receipt card, budget ring | Not started as Phase 2 package set; some LA/Siri code exists historically | **Do not start** until Phase 1 exit bar is honest (loop works on phone). |
| **3 — Aug→Sept 14** | S27-0…S27-5 + LAUNCH-1…LAUNCH-4 → App Store @ iOS 27 GA | Prep only; owner phone already on iOS 27.0 | Owner-gated target call still open for Live Activities / S27 deep work. |

**Wedge (do not drift — from daily-driver definition + roadmap §0):**
> "Don't watch your agents — govern them." Competitors are remote chat windows for *watching*;
> Lancer is the governed gate console for the time you're *not watching* (approvals, questions,
> verdicts, kill — pocket / lock screen / Siri). Chat is the vehicle and must be good; it is
> **not** the differentiator. Own machines + own subscriptions (Claude/Codex/OpenCode/Kimi) —
> never a hosted wrapper that replaces the owner's vendor accounts.

**Phase 1 MVP pieces (roadmap §1 — all must work on physical phone):**
1. Pairing + trusted machines
2. Thread list (needs-you-first)
3. Chat thread: multi-turn, markdown, streaming, tool cards, inline approval
4. Composer: prompt + agent/model/machine
5. Push approvals incl. lock-screen approve/deny
6. Emergency stop

**Phase 1 exit bar (unchanged):** owner completes pair → dispatch → approve → follow-up → review
on a physical phone, **5 days of 7**, without reaching for the laptop to unblock the agent.

**Owner primary product ask (repeated 07-12 → 07-13):** **desk Mac ↔ phone continuity** — see
past/desk chats on phone; continue this conversation. Code for observed-continue exists
(#86/#94/#99–#101); **blocked today by Agents poll (B2)**.

**Frozen / out of swarm:** team tier · hosted-cloud · Away Launch Composer · Watch (cut) ·
pricing/billing until fork · do not invent new wedges.

## Model routing (owner directive — 2026-07-10 + 2026-07-13 update)

| Role | Model / tool | When |
|---|---|---|
| **Orchestrate** | **You (Fable 5)** | Specs, decomposition, arbitration, integration debugging, full-diff review of sensitive paths, anything that **failed after a “fix” PR**, multi-surface root-cause. Token conservation is an owner priority — you think, cheaper models type. |
| **Hard implementation (preferred for P0/recurring)** | **GPT-5.6** in an isolated worktree | After Fable writes a clear spec. Owner wants GPT-5.6 available for hard/recurring bugs — **not** casual Composer for B1/B2/B3 or ≥2× bugs. |
| **Default routine coding** | **Cursor CLI · Grok 4.5 high** — `agent -p "<spec>" --model <grok-slug> --output-format json --force` (note: `agent` may be shadowed by grok — prefer `cursor-agent`) | Features, bug fixes, tests, refactors once diagnosed. |
| **Mechanical / first-pass review** | **Cursor CLI · Composer 2.5** | Renames, boilerplate, doc updates, test scaffolds, diff-review *summaries*. Do **not** give it novel architecture or failed-after-fix P0s. |
| **Fallback + sensitive implementation** | **Claude Sonnet 5 (high)** via Agent tool | (a) Cursor/GPT failed the gate twice; (b) work needing repo skills / XcodeBuildMCP (sim screenshots, UI-test evidence, device builds); (c) security-sensitive paths below. |
| Verify slugs | `agent models` / `cursor-agent models` + `agent status` | Record exact slugs in `docs/plans/orchestrator-state.md`. |

**Per-item routing shorthand used below:**
- **Fable** = diagnose / sequence / integrate / sensitive full-diff review
- **GPT-5.6** = implement hard fix in worktree after clear spec
- **Cursor (Grok)** = implement routine / UI after clear spec
- **Composer** = mechanical only
- **Sonnet** = sensitive impl or XcodeBuildMCP-heavy
- **owner-gated** = needs owner time / hardware / product decision before coding
- **already-fixed-uncommitted** = verify + device rebuild / merge — **do not re-implement**

**Security-sensitive paths — draft OK by GPT/Grok, but Sonnet-or-Fable full-diff review mandatory:**
`daemon/lancerd/dispatch.go` (+ `vendor-cli-adapter-audit` skill) · `daemon/lancerd/policy/` ·
approval/content-hash · `Packages/**/Security*` · E2E relay protocol types · keychain/pairing/
audit chain · pairing-durability merge.

## Non-negotiables (safety + product + ops)

From 07-10 PASTE + current ops reality:

- No Siri **approve** intent, ever · no Face ID reintroduction · voice-approve rejected
- Mutating kinds **fail closed** · never "all clear" over a stale relay · UI copy "asked of the
  agent," never "guaranteed"
- `dispatch.go` edits require `vendor-cli-adapter-audit` + Sonnet/Fable full-diff review
- **No phone reinstall without owner ask** (wipes pairing)
- Competitor ports = **patterns only** with attribution (roadmap §0; Orca MIT, Omnara Apache-2.0,
  Happier conservative) — never commit competitor code/clones
- No agent deletes frontend chrome without a fresh owner ask
- **NEVER run bare `lancerd pair`** while owner holds the relay slot — stomps registration.
  Confirmed prod identity: code **732590** / host **73CA5B5B** (see pairing-durability). New
  codes only: first onboard, explicit pair/unpair, or true identity loss.
- **Subscription-only / own-machines:** do not build hosted agent runners as the path; owner's
  Claude/Codex/OpenCode/Kimi accounts on his Mac remain source of truth
- Parallel agents: **disjoint write-sets**; never whole-file `cp` across worktrees
- Evidence before "done" — paste command + output; distrust prior "merged/verified" claims
- Do not stomp uncommitted tree work (vendor picker, Attach/fixture fixes, transcript skip) or
  `.worktrees/pairing-durability`

## Process (summary — full version in `docs/ENGINEERING_PROCESS.md`)

Spec (≤1 page: goal, write-set, acceptance commands, risk class `low|ui|sensitive`) → worktree
branch `feat/<area>-<slug>` off `master` → implement (routed) → coder self-verifies → gates
(`swift test` → app-target `build_sim` → `cd daemon/lancerd && go test ./...` →
`relay-approval-e2e.sh` when relay-touching) → fresh-session cross-model review
(`git diff master...HEAD | agent -p <checklist> --mode=ask`) → PR via `gh pr create` with
pasted evidence → **YOU re-run gates** → owner gate only for `ui`/`sensitive` or daily-loop
changes → merge, delete worktree, update `STATUS_LEDGER` + `FEATURE_BACKLOG` +
`docs/plans/orchestrator-state.md`.

Shared files (`Package.swift`) land first as a tiny solo commit. Tests land in the same PR
unless the spec explicitly waives with a reason.

## Owner interaction contract

Act without asking within phase order **and** today's ranked packages. Interrupt only for:
physical-device steps (Tier 0 / 5c re-proof, TestFlight installs, APNs lock-screen),
sensitive-path merges, scope changes, App Store submission actions, dogfood-log triage,
relay cutover / cost decisions, iOS 27 / Live Activities target calls, and anything needing a
2nd Apple device (C7).

Phase-boundary / daily digest: merged / in-flight / blocked / next / decisions-needed —
**five lines, no more.**

If a subagent's result is an error string (session limit etc.), that task is **NOT done** —
reroute it. A prior transcript/PR saying "done" is a claim — re-check live repo + device.

## Known repo state to trust (verified 2026-07-13 — re-check `git` / phone before citing)

### Tip + merges
- **Tip:** `0e0b9eba` — `fix(relay): REL-1 session robustness (#110)` on `master`.
- **Session-4 stack merged:** #105 (scroll arrow + proof chips + fetch-on-open) · #106 (G1
  turn-diff RPCs) · #107 (G2 Codex-1:1 review sheet) · #108 (G3 live status pill) · #109
  (context attachments Photos/Camera/Files → daemon drop dir) · **#110** (REL-1: structured
  relay errors, expiresAt, daemon re-mint, phone `.codeExpired`, first-send readiness gate +
  single retry).
- Earlier Phase 1 foundation: #95–#104 (cwd/bucketing, chat-loop, tilde, backfill, long
  transcript daemon+iOS, search-tap, structured transcripts, tool chips).
- Device build dir: `build/device-POST-110-0e0b9eba/` (installed on owner iPhone for dogfood).

### Relay / daemon ops (CRITICAL)
- Owner phone paired **confirmed 732590** / Trusted Machines host **73CA5B5B Connected**.
- Daemon: `~/.lancer/bin/lancerd` via LaunchAgent.
- **Do NOT run bare `lancerd pair`.** Pairing durability fix lives in
  `.worktrees/pairing-durability` + `docs/plans/2026-07-12-pairing-durability.md` — merge with
  Fable review; refuse silent overwrite of confirmed identity.
- Prior abnormal re-pair (818038 → localhost stomp → 732590) was ops accident, not product
  design. Historical codes (116955, 208937, 818038) are archaeology only.

### Phone dogfood evidence (POST-110 — **source of truth for today's P0s**)
Dir: `docs/test-runs/2026-07-13-post110-session4-continuity/`

| Shot | Finding |
|---|---|
| `01-trusted-machines-connected.png` | Connected PASS |
| `02-home-agents-unreachable.png` | Agents **"Machine unreachable — no successful update yet"** while Connected; command-center bucketing PASS (one row) |
| `03-newchat-working-attach-diff.png` | New Chat **"Hi" stuck Working…**; Follow up inert; spurious review pill visible (fixture — fixed in-tree) |
| `04-fix-triple-task-notification.png` | Long thread opens; raw `<task-notification>` XML + "(no reply text)" |
| `05-attachment-chip-spinner.png` | Photo chip spinner forever; send disabled |
| `06-review-sheet-file-tree.png` | Review sheet UI loved; was fixture data (+442/−11) |

Full write-up: `RESULTS.md` in that directory. Checklist: `docs/plans/phone-test-session4.md`.

**Audit note (B1):** `~/.lancer/audit.log` shows `conversation-append-launched` for `Hi` at
`2026-07-13T19:31:24Z` — dispatch reached daemon; UI stayed `ShellLiveBridge.sendState=.working`.
Relay EOF reconnect ~15:35 around test window. **REL-1 #110 merged but first-send still fails
on device** — treat as failed-after-fix → Fable root-cause, not another blind gate PR.

### Already fixed in working tree / worktree (verify — do NOT re-do)

| Item | Where | Done-bar |
|---|---|---|
| Ugly separate **Attach** label | `LiveThreadView` → `+` / `ContextAttachView` via `ChatThreadChrome.onAddContext` | Device rebuild: no standalone Attach; `+` opens attach sheet |
| Spurious **4 files +442/−11** | Was `FixtureReviewDataSource`; now `RelayReviewDataSource` stub | New chat: no fake diff pill; **still owed:** live `repo.turnDiff`/`sessionDiff` wire |
| Daemon skip `<task-notification>` on **new** imports | `isObservedWrapperUserText` + `claudeUserMessages` | `go test` green; **old ledger rows still need iOS filter** |
| **Vendor picker** Codex/OpenCode | Uncommitted: `DispatchVendorSelection`, `VendorPickerView`, bridge/hydration | Device: New Chat → Agent → Codex/OpenCode; Claude remains gold-standard models |
| **Pairing durability** | `.worktrees/pairing-durability` | Merge without stomping relay; confirmed identity survives reboot/binary replace |

### Continuity / blocked
- Mac desk session seeded (`CONTINUITY_PING_2026-07-13`) — **Agents → open Mac session BLOCKED by B2**
- REL-1 R1/R2 (force-quit → first send) **BLOCKED by B1**
- CloudKit C7 Phone A→B **owner-gated** (no 2nd Apple device)

### Process gotchas (from orchestrator-state)
- Prefer `cursor-agent` (bare `agent` shadowed by grok)
- RelayMachineMigrationTests collide across concurrent `swift test` in different worktrees
  (shared Keychain) — run LancerKit suites **serially**
- Never `git stash pop` without `git stash list` first
- PR may get no CI on first push — check `gh run list --branch` and re-kick

## Verification pipeline (v2)

Read `.claude/skills/swarm-orchestrator/references/verification-pipeline.md` (also in the
07-10 zip as `verification-pipeline.md`). Five stages: gates → beyond-the-diff cross-model
review (dependents map + `docs/REVIEW_STANDARDS.md`, structured verdict JSON, nits never block)
→ fix loop bounded at ONE re-review then escalate → `claude-code-action` as independent PR
reviewer → risk-gated deep review (sensitive = full diff by strongest model; ui = owner,
batched; low = auto-merge).

Long-running: reset-from-handoff via `docs/plans/orchestrator-state.md`, never limp through
compaction; drift check against roadmap phase goals every 5 merges.

**Acceptance commands you will re-run yourself:**
- `cd daemon/lancerd && go test ./...`
- `cd Packages/LancerKit && swift build` (+ `swift test` if behavior changed; serial if Keychain tests)
- App-target / device rebuild for UI (XcodeBuildMCP / `devicectl`) — plain `swift build` skips `#if os(iOS)`
- Owner re-dogfood: `docs/plans/phone-test-session4.md` priority order + R1/R2 + Agents → Mac session

---

## 07-10 plan pack — embed (do not re-brainstorm)

**Daily-driver one-liner:** Lancer lets the owner drive, approve, and review AI coding agents on
his own machines — any vendor, own subscriptions — from the phone, with a governed
kill-switch-and-approval layer he trusts.

**Core journey:** desk start (or phone dispatch) → leave → push (approval/question/fail/done) →
open thread → approve/deny (incl. lock screen) · answer · follow-up → agent continues on Mac →
return: thread shows what happened; continue on desk.

**Roadmap Phase 1 references (steal, don't invent):**
- Chat finesse ranked list: `docs/product/2026-07-09-chat-ui-port-map.md` + roadmap §1.1
  (Happier streaming/tool state; Orca autoscroll/live-status; Omnara markdown/derived-offline)
- Full terminal (owner reversed 06-30 deferral): `docs/product/2026-07-12-orca-terminal-port-map.md`
  Phase 1–3 — **not started**
- Readiness gaps: `docs/product/2026-07-12-full-time-readiness-audit.md`
- Identity / hot-swap design: `docs/plans/2026-07-12-account-hotswap-and-identity-design.md`
- Vendor picker plan: `docs/plans/2026-07-12-codex-opencode-vendor-picker.md`

**Phase 2/3 packages (cite when sequencing later — not today's P0):**
- LA-1…LA-4 (Live Activities) · S27-0…S27-5 · LAUNCH-1…LAUNCH-4 — roadmap §2.2 / §3.1 / §3.1b
- Loop supervision / PR surface / fork — roadmap §3.2–3.4

---

## Ranked work packages (TODAY → next)

Execute in this order unless evidence forces a reorder. Every package needs a ≤1-page spec
before dispatch.

### WP-0 — Land / verify in-tree fixes (no re-implement)
- **Route:** already-fixed-uncommitted → Composer/Grok only if merge conflicts
- **Write-set:** commit/PR the uncommitted Attach + fixture + transcript-skip + vendor-picker
  slice **without** touching relay pair files; separate PR for pairing-durability worktree
- **Risk:** `ui` (picker/Attach) · `sensitive` (pairing-durability)
- **Acceptance:** device rebuild shows: no Attach label; no +442/−11 on new chat; Agent chip
  lists Codex/OpenCode; `go test` covers task-notification skip
- **Done-bar:** owner sees fixes on phone; durability merge reviewed by Fable

### WP-B1 — Stuck Working after New Chat "Hi" + dead Follow up (P0)
- **Symptom:** spinner forever; Follow up inert (`03-….png`)
- **Evidence:** audit `conversation-append-launched`; UI `.working`; #110 failed to clear on device
- **Route:** **Fable** root-cause (sendState / stream completion / first-send race / relay EOF)
  → **GPT-5.6** implement
- **Likely write-set (confirm in spec):** `ShellLiveBridge.swift`, `E2ERelayBridge` first-send
  helpers, live thread send path, possibly daemon stream/completion events — **disjoint** from B3
- **Risk:** `sensitive` if relay protocol; else `ui`
- **Acceptance:** unit/integration covering sendState leave-working; device: New Chat "Hi"
  completes without Retry; Follow up sends; **R1** force-quit→reopen→first send works
- **Done-bar:** 10 consecutive reconnect→first-send successes without Retry (recurring-bug bar)

### WP-B2 — Agents unreachable while Trusted Machines Connected (P0) — continuity blocker
- **Symptom:** `RunningAgentsFreshness` `!hasEverSucceeded` copy (`02-….png`)
- **Route:** **Fable** (poll/RPC path / hydration) → **GPT-5.6**
- **Likely write-set:** `RunningAgentsMapping.swift` / freshness, `RelayFleetHydration`,
  agent.sessions poll bridge — **disjoint** from B1/B3 if possible
- **Risk:** `ui` (display) or `sensitive` if protocol
- **Acceptance:** zero agents + healthy relay → **"No agents running"**; desk Claude session
  appears within ~2s of Connected and opens (observed-continue)
- **Done-bar:** Mac session → full transcript → follow-up round-trip on phone

### WP-B3 — Attachment chip spinner hang (P0)
- **Symptom:** Photo chip never `.done`; send disabled (`05-….png`); #109 path
- **Route:** **Fable** → **GPT-5.6**
- **Likely write-set:** `NewChatComposerView` / attachment put client, daemon `attachmentPut`,
  relay attachment RPCs
- **Risk:** `sensitive` if protocol; else `ui`
- **Acceptance:** Photo → chip `.done` → send → Mac agent prompt contains host path
- **Done-bar:** same + inbound artifact PNG inline when present (#26)

### WP-P1a — `<task-notification>` gibberish on existing threads
- **Route:** **GPT-5.6** (iOS display filter + optional re-attach); daemon skip already in-tree
- **Write-set:** iOS transcript/render filter; avoid double-fixing daemon skip
- **Risk:** `ui`
- **Done-bar:** Re-open "Fix triple…" — no XML bubbles; real turns remain (`04-….png` cleared)

### WP-P1b — Live G1→G2 review wire + G3 status pill on device
- **Route:** **GPT-5.6** (phone calls `repo.turnDiff`/`sessionDiff`); **Fable** if daemon events missing for G3 `runStatus`
- **Risk:** `ui`
- **Done-bar:** Real edit turn → pill + sheet match **that turn's** files; Thinking/Calling/Editing with elapsed (not eternal Working…)

### WP-P1c — Scroll-↓ polish + Flight Recorder / proof placement
- **Route:** **GPT-5.6** / Composer
- **Risk:** `ui`
- **Done-bar:** Arrow above keyboard, scrolls to bottom, hidden at bottom; FR only via ⋯ / explicit (owner L3030 — not after every response); proof chip tappable → FR

### WP-E — Screenshot / UI port (do not lose — after P0s)
See § Screenshot folders below. **Fable** gap-map first → **GPT-5.6** UI lanes; daemon PTY =
Fable+Sonnet.

| Sub | Spec / refs | Done-bar |
|---|---|---|
| E1 Full terminal | `docs/product/2026-07-12-orca-terminal-port-map.md`; Claude `4a407758` L1403 | Phase 1: Terminal at paired cwd; vim/htop survive background |
| E2 Claude desktop + Codex live features | `~/Desktop/Views/Screenshot 2026-07-12 at 2.38.*.png`; L2571 | Port checklist + Thinking/Calling/Editing proven on device |
| E3 Claude mobile formatting | `~/Downloads/Screenshot 2026-07-12 at 1.09.13 PM.png`, `1.10.24 PM.png`; L2079 | Long thread matches competitor separation |
| E4 Cursor mobile IA | Cursor `cf9acad8`; `~/Downloads/Cursor Mobile App/` | Composer-everywhere + polish after P0s; Live Activities / Island = owner-gated |

### WP-ledger — Owner-asks still open (route, don't drop)
Full table also in `docs/plans/2026-07-13-fable-owner-asks-complete.md` §F. Digest:

| Ask | Route | Done-bar |
|---|---|---|
| #18 APNs lock-screen approve | owner-gated (+ Fable prep) | Force-quit → gated action → lock-screen Approve → audit clear |
| #22 Plan-limits | owner-gated then GPT-5.6 | Settings shows remaining budget before dispatch |
| #23 Identity badges → Claude hot-swap | badges GPT-5.6; hot-swap Fable/Sonnet | Badge on thread/Agents; capture/activate without leaking creds |
| #24 Text-to-agent | owner-gated | Scope confirm |
| #25 In-app bug reporting | owner-gated → GPT-5.6 | Sheet → GitHub issue via daemon |
| #26 Artifacts both directions | after B3 | Agent PNG inline; photo attach E2E |
| #27 Siri / S27 deep iOS | owner-gated | iOS 27 target call → LA restore gate |
| #28 / C7 cross-device | owner-gated | 2nd device |
| #29 Tier 0 / 5c re-proof | owner-gated | Checklist PASS on tip |
| #30 Emergency stop | owner-gated + GPT-5.6 if broken | Stop kills run; honest UI |
| #31 dogfood-log habit | owner-gated | Daily lines through Phase 1 exit |
| "+" vs Add Repo dedupe | GPT-5.6 | One affordance |
| Backfill paging >50 | GPT-5.6 | Page past 50 host rows |
| Multi-vendor gold (Pi/Cursor) | Fable sensitive for adapters | Claude parity first; Cursor/Pi ship or explicit defer |
| GCP relay ~$130/mo | Fable ops plan → owner-gated | Cost down without breaking pairing |
| Webapp preview | defer | Documented path — not this week's P0 |

---

## Recurring bugs table (≥2× — root-cause lanes, not one-offs)

| Bug | Dates / sessions | Route | Done-bar |
|---|---|---|---|
| First-send / stuck Working / "machine didn't respond" after pair/reconnect | 07-11 timeouts; 07-12 ×3 live; 07-13 POST-110 B1 | **Fable** → **GPT-5.6** | 10× reconnect→first-send without Retry |
| Pairing "waiting for peer" / code dead / slot churn | 07-11; 07-12 L2343–2415 code 818038; localhost stomp → 732590 | **Fable** merge durability + ops rule | No bare `lancerd pair`; confirmed code survives update; expired shows TTL |
| Agents empty/unreachable while Connected | 07-12 L1597; 07-13 B2 | **Fable** → **GPT-5.6** | Same as B2 + Mac session ~2s |
| `<task-notification>` / wrapper gibberish | 07-12 imports; 07-13 `04-….png` | **GPT-5.6** after daemon skip | No XML bubbles on "Fix triple…" |
| Mock/fixture painted as real | 07-11 filler #78; 07-13 fixture review pill | already-fixed + live `repo.*` wire | Review = that turn only |
| Scroll-↓ wrong place / no scroll | 07-12 L3104; 07-13 polish owed | **GPT-5.6** | Above keyboard; scrolls; hidden at bottom |
| Cursor CLI "Too many MCP tools" | orchestrator-state | Process note | `cursor-agent` + trimmed MCP — not a product PR |

---

## Screenshot / session cite index (UI-port work)

| ID / path | Why |
|---|---|
| Claude `4a407758-e5c4-477f-b007-099b48def762` | Terminal **L1403**; Claude mobile **L2079**; multi-vendor/Siri L2114; Claude+Codex screenshots **L2571**; FR spam L3030; scroll L3104; continuity L1514/1597/3456 |
| Cursor `cf9acad8-7a69-4763-8f2d-cc33c55e31bb` | Cursor Mobile App refs; IA; Live Activities; chat polish |
| Cursor `c10ba344` / `a30ca9db` | App Store status + POST-110 continuity dogfood |
| Cursor `2ff457a9` | Relay cost reduction |
| Codex `019f5929-05b3-7b12-a8d3-d4e10f39034f` | Swarm continue 07-12 |
| `~/Desktop/Views/` | Claude desktop + Codex app screenshots (`Screenshot 2026-07-12 at 2.38.{24,26,27,28,29,31,33,41} PM.png`) |
| `~/Downloads/Cursor Mobile App/` | IMG_2408–2422, 2496–2499, Dark/ |
| `~/Downloads/Screenshot 2026-07-12 at 1.09.13 PM.png` (+ `1.10.24`) | Claude mobile formatting refs |
| `docs/test-runs/2026-07-13-post110-session4-continuity/` | Today's P0 evidence |
| `docs/product/2026-07-12-orca-terminal-port-map.md` | Full terminal Phase 1–3 |
| `~/Downloads/lancer-owner-asks-ledger-2026-07-11.md` | Ledger #18–#31 |
| Canvas (non-SSOT) | `~/.cursor/projects/Users-roshansilva-Documents-command-center/canvases/lancer-appstore-status-2026-07-13.canvas.tsx` — **docs remain SSOT** |

---

## Recommended swarm order (first message after setup)

1. **Fable personally:** diagnose B1 + B2 + B3 with audit.log + phone screenshots + tip code —
   write three specs with disjoint write-sets (or explicitly shared file order).
2. **GPT-5.6:** implement B1/B2/B3 in worktrees; Fable re-verifies gates + device rebuild.
3. **Land WP-0** (in-tree fixes + pairing-durability) in parallel only if write-sets disjoint
   from B*.
4. **GPT-5.6:** task-notification iOS filter; live `repo.*` review wire; scroll/FR polish.
5. **Fable** gap-map E2/E3 vs Desktop/Views + Claude mobile → GPT-5.6 UI lanes.
6. Terminal Phase 1 (GPT-5.6) only after P0 reliability holds; Phase 2 PTY = Fable+Sonnet.
7. Owner-gated batch when owner is available: APNs, emergency stop, Tier 0, plan-limits,
   C7 hardware, S27 target, relay cost.

## First actions (now)

1. `git status` / `git worktree list` / `git rev-parse HEAD` (expect `0e0b9eba` + dirty tree —
   do not discard)
2. `cursor-agent models` / `agent status` — record slugs; confirm GPT-5.6 availability for hard lanes
3. `gh auth status`
4. Read top ⚡ blocks of `docs/plans/orchestrator-state.md` +
   `docs/test-runs/2026-07-13-post110-session4-continuity/RESULTS.md`
5. Update `docs/plans/orchestrator-state.md` with this session's start line
6. **Begin with WP-B1/B2/B3 root-cause** — do not open Phase 2/3 feature lanes first
7. Five-line owner digest when you have a diagnosis or first PR up

Hard stop reminders: **no bare `lancerd pair`** · **subscription/own-machine wedge** ·
**Phase 0 done — don't revive wipe** · **docs are SSOT over canvas** · **evidence before done**.
