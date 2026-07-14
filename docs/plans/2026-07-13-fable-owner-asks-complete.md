# Fable inventory — owner asks + recurring bugs (complete, 2026-07-13)

> **Canonical Fable handoff / paste:** [`docs/plans/2026-07-13-fable-orchestrator-PASTE.md`](2026-07-13-fable-orchestrator-PASTE.md)
> — paste *that* file into a fresh Fable 5 session. This document is the detailed inventory appendix.

Supersedes paste-alone use of the phone-only slice in
`docs/plans/2026-07-13-fable-post110-phone-blockers.md` (that file points at the PASTE via this
appendix). Prefer **Fable** (orchestrate / sensitive / integration debug) and **GPT-5.6**
(worktree implementation) for hard or recurring items — **not** casual Composer. Sonnet only
where ENGINEERING_PROCESS already requires it (`dispatch.go`, relay protocol, credentials).

Do **not** run bare `lancerd pair` (relay **732590** / `73CA5B5B` confirmed; see pairing-durability).

---

## Explicit ask

1. Unblock **phone daily-driver** on POST-110 tip (`0e0b9eba` + uncommitted tree fixes).
2. Close **desk Mac ↔ phone continuity** (owner primary ask, repeated 07-12 → 07-13).
3. Do not drop prior owner feature asks mined from Claude/Cursor/Codex (~7 days) — route each
   with a checkable done-bar.
4. Recurring bugs (≥2×) get root-cause lanes, not one-off patches.

**Out of swarm / frozen:** team tier, hosted-cloud, Away Launch Composer, Watch.

---

## Routing legend

| Route | Use for |
|---|---|
| **Fable** | Diagnosis, sequencing, sensitive full-diff review, multi-surface integration, anything that failed after a “fix” PR |
| **GPT-5.6** | Implementation in an isolated worktree after Fable/spec is clear |
| **owner-gated** | Needs owner time, hardware, or a product decision before coding |
| **already-fixed-uncommitted** | In working tree or worktree — verify + device rebuild / merge, do not re-implement |

---

## A. Already fixed in working tree / worktree (verify — do not re-do)

| Item | Where | Route | Done-bar |
|---|---|---|---|
| Ugly separate **Attach** label | `LiveThreadView` → `+` / `ContextAttachView` via `ChatThreadChrome.onAddContext` | already-fixed-uncommitted | Device rebuild: no standalone Attach; `+` opens attach sheet |
| Spurious **4 files +442/−11** session pill | Was `FixtureReviewDataSource`; switched to `RelayReviewDataSource` stub | already-fixed-uncommitted | New chat shows no fake diff pill |
| Daemon skip `<task-notification>` on **new** imports | `isObservedWrapperUserText` + `claudeUserMessages` | already-fixed-uncommitted | `go test` + new attaches omit wrappers; **old ledger rows still need iOS filter** (B/P1) |
| **Vendor picker** Codex/OpenCode (phone Agent chip) | Uncommitted: `DispatchVendorSelection`, `VendorPickerView`, bridge/hydration | already-fixed-uncommitted | Device: New Chat → Agent → Codex/OpenCode; Claude still gold-standard models |
| **Pairing durability** | `.worktrees/pairing-durability` + `docs/plans/2026-07-12-pairing-durability.md` | already-fixed-uncommitted → Fable review on merge | Merge without stomping relay; confirmed identity survives reboot/binary replace |

Evidence screenshots: `docs/test-runs/2026-07-13-post110-session4-continuity/`.

---

## B. P0 phone blockers (today) — Fable orchestrates, GPT-5.6 implements

| # | Symptom | Evidence | Route | Done-bar |
|---|---|---|---|---|
| B1 | New Chat **"Hi" stuck Working…**; Follow up inert | `03-newchat-working-attach-diff.png`; audit `conversation-append-launched` @ `2026-07-13T19:31:24Z`; UI `sendState=.working`; REL-1 #110 merged but still fails | **Fable** root-cause → **GPT-5.6** fix | "Hi" completes to assistant text without Retry; Follow up sends; force-quit → reopen → first send (R1) works |
| B2 | Agents **"Machine unreachable — no successful update yet"** while Trusted Machines **Connected** | `02-home-agents-unreachable.png`; `RunningAgentsFreshness` when `!hasEverSucceeded` | **Fable** (poll/RPC path) → **GPT-5.6** | Zero agents + healthy relay → **"No agents running"**; desk Claude session appears and opens (continuity) |
| B3 | Photo attachment chip **spinner forever**; send disabled | `05-attachment-chip-spinner.png`; `relayPutAttachment` / `attachmentPut` | **Fable** → **GPT-5.6** | Photo → chip `.done` → send → Mac agent prompt contains host path |

---

## C. Recurring bugs (≥2×) — do not treat as one-offs

| Bug | Dates / sessions | Symptoms | Route | Done-bar |
|---|---|---|---|---|
| **First-send / stuck Working / “machine didn’t respond”** after pair/reconnect | 07-11 (`74d1b836` timeouts); 07-12 ×3 live (orchestrator-state + readiness); 07-13 POST-110 B1 | Send races relay re-key or UI never leaves `.working` | **Fable** (failed after #110) → **GPT-5.6** | 10 consecutive reconnect→first-send successes without Retry |
| **Pairing “waiting for peer” / code dead / slot churn** | 07-11 pin/peer; 07-12 L2343–2415 code 818038; 07-12 localhost stomp → 732590 | Pair sheet stalls; agent re-pair wipes owner slot | **Fable** merge durability + ops rule | No bare `lancerd pair`; confirmed code survives update; expired shows TTL not infinite wait |
| **Agents empty/unreachable while Connected** | 07-12 L1597 (slow “No agents”); 07-13 B2 | Continuity blocked | **Fable** → **GPT-5.6** | Same as B2 + Mac session visible within ~2s of Connected |
| **`<task-notification>` / wrapper gibberish in chat** | 07-12 imports; 07-13 `04-….png` “Fix triple…” | Raw XML + “(no reply text)” | **GPT-5.6** (iOS filter + optional re-attach) after daemon skip | Re-open “Fix triple…” — no XML bubbles; real turns remain |
| **Mock/fixture painted as real** | 07-11 filler purge #78; 07-13 fixture review pill | Fake +442/−11 | already-fixed-uncommitted + **GPT-5.6** live `repo.*` wire | Review sheet shows **that turn’s** files only |
| **Scroll-↓ arrow wrong place / no scroll** | 07-12 L3104; 07-13 polish still owed (#105 mechanics shipped) | Mid-screen; dismiss-only | **GPT-5.6** polish | Above keyboard; scrolls to bottom; hidden when at bottom |
| **Cursor CLI “Too many MCP tools”** (process) | orchestrator-state recurring | `agent -p` dies | Process note for Fable | Use `cursor-agent` + trimmed MCP / documented workaround — not a product PR |

---

## D. Continuity (owner primary — asked repeatedly)

| Ask | Status | Route | Done-bar |
|---|---|---|---|
| **Desk Mac ↔ phone**: see past/desk chats; continue this conversation on phone | Code #86/#94/#99–#101; **blocked by B2** | **Fable** until Agents poll works, then owner dogfood | Open Mac Claude session from Agents → full transcript → follow-up round-trip |
| **Phone A → Phone B (CloudKit C7)** | Plumbing exists; **no 2nd Apple device** | **owner-gated** | Leave open; do not mark fixed |
| Search finds thread but couldn’t open | Fixed **#102**; was 07-12 L2452 | — | Regress-check only on device |

Sources: Claude `4a407758` L1514, L1597, L3456; Cursor `c10ba344` / `a30ca9db` continuity plan.

---

## E. Screenshot / UI port work (do not lose — cite for Fable)

### E1 — Full terminal (Orca)

- **Ask (verbatim):** “look at how orca handles terminal feature… **i want full terminal support**”
- **Session:** Claude `4a407758-e5c4-477f-b007-099b48def762` — queued_command / attachment around **L1403–L1411** (JSONL queue-operation + attachment; not a normal `type:user` line)
- **Spec:** `docs/product/2026-07-12-orca-terminal-port-map.md` (Phase 1–3; **not started**)
- **Route:** Phase 1 **GPT-5.6** (UI re-wire); Phase 2 **Fable** + Sonnet (daemon PTY / relay); Phase 3 **GPT-5.6**
- **Done-bar Phase 1:** Phone → Terminal at paired cwd; vim/htop survive background

### E2 — Claude desktop + Codex app live features (“this works / this doesn’t”)

- **Ask:** loading animation + live “calling xcodebuildmcp” / plan; buttons from **Claude Code desktop**; features from **Codex app**; study Orca/competitors; brainstorm before build
- **Session:** Claude `4a407758` **L2571** (+ image block **L2573**)
- **Screenshots:** `~/Desktop/Views/Screenshot 2026-07-12 at 2.38.{24,26,27,28,29,31,33,41} PM.png` (+ duplicate `2.38.27 PM 1.png`)
- **Partial ship:** tool chips / thinking rows **#104**; G3 status pill **#108** (code merged, **not proven on device** — B/P1)
- **Route:** **Fable** gap-map vs screenshots → **GPT-5.6** lanes (UI); daemon events stay Fable-reviewed
- **Done-bar:** On a real edit turn, phone shows Thinking / Calling〈tool〉 / Editing with elapsed; remaining Codex/Claude desktop affordances listed in a short port checklist with owner yes/no

### E3 — Claude mobile transcript formatting

- **Ask:** format toolcalls, thinking, user messages, diffs separately; study Claude mobile first
- **Session:** `4a407758` **L2079**
- **Screenshots:** `~/Downloads/Screenshot 2026-07-12 at 1.09.13 PM.png`, `1.10.24 PM.png`
- **Route:** **Fable** brainstorm/port-map (if not already) → **GPT-5.6**
- **Done-bar:** Long “Fix triple…” thread matches competitor separation (no megablob); owner eyeball vs Claude mobile refs

### E4 — Cursor mobile IA / polish references

- **Session:** Cursor [`cf9acad8-7a69-4763-8f2d-cc33c55e31bb`](cf9acad8-7a69-4763-8f2d-cc33c55e31bb)
- **Assets:** `~/Downloads/Cursor Mobile App/` (IMG_2408–2422, 2496–2499, Dark/)
- **Asks still open:** input box on most pages; chat polish + animations; artifacts rendered inline; Live Activities / Dynamic Island concepts
- **Route:** Live Activities / Island → **owner-gated** (S27 / iOS 27 target call) then **GPT-5.6**; composer-everywhere + polish → **GPT-5.6** after P0s; artifacts → §F #26

---

## F. Owner-asks ledger + readiness still open

Sources: `~/Downloads/lancer-owner-asks-ledger-2026-07-11.md`, `docs/product/2026-07-12-full-time-readiness-audit.md`, `docs/plans/orchestrator-state.md`.

| # / ask | Status | Route | Done-bar |
|---|---|---|---|
| **#18 APNs lock-screen approve** | Never re-proven on tip | **owner-gated** (+ Fable prep traces) | Force-quit app → gated action → lock-screen Approve → audit + queue clear |
| **#22 Plan-limits** (Claude/Cursor/Codex) | Research done (`lfg` study); not built | **owner-gated** (skip Cursor per-device V1?) then **GPT-5.6** | Settings shows remaining budget before dispatch |
| **#23 Identity badges → Claude hot-swap** | Designed `2026-07-12-account-hotswap-and-identity-design.md` | Badges **GPT-5.6**; hot-swap **Fable**/Sonnet | Badge on thread/Agents; capture/activate profile without leaking creds |
| **#24 Text-to-agent in-app** | Needs scope confirm | **owner-gated** | Owner picks thin thread type vs defer |
| **#25 In-app bug reporting** | Not designed | **owner-gated** → **GPT-5.6** | Sheet → GitHub issue via daemon (or chosen path) |
| **#26 Artifacts both directions** | Inbound #109 merged but **hangs (B3)**; outbound inline still open | **Fable**/GPT-5.6 after B3 | Agent PNG/screenshot inline in chat; photo attach works E2E |
| **#27 Siri / S27 deep iOS** | Phase 2 resurrected historically; target call open | **owner-gated** | Owner sets iOS 27 target; then Live Activity restore gate |
| **#28 / C7 cross-device** | See §D | **owner-gated** | 2nd device QA script |
| **#29 Tier 0 / 5c re-proof** | Pending on tip | **owner-gated** | Checklist `docs/test-runs/2026-07-11-tier0-owner-checklist.md` PASS |
| **#30 Emergency stop** | Unverified on current shell | **owner-gated** + **GPT-5.6** if broken | Stop from phone kills run; honest UI |
| **#31 dogfood-log habit** | One line 07-13; habit still weak | **owner-gated** | Daily lines through Phase 1 exit |
| **Live G1→G2 review wire** | Fixtures removed; `repo.turnDiff`/`sessionDiff` not called from phone | **GPT-5.6** | Real edit → pill + sheet match that turn |
| **"+" vs Add Repo dedupe** | Queued orchestrator-state | **GPT-5.6** | One affordance; no duplicate entry points |
| **Backfill paging >50** | Edge-sweep backlog | **GPT-5.6** | Fresh install can page past 50 host rows |
| **Proof card placement** | Decided: chip in chat, full Proof/Reel in Flight Recorder; #105 moved FR to ⋯ | **GPT-5.6** polish | No FR block after every response (owner L3030); chip tappable → FR |
| **Flight Recorder spam** | Owner L3030 “why after every response?” | **GPT-5.6** | FR only via ⋯ / explicit; not inline every turn |
| **Multi-vendor gold standard** | Owner L2114: Claude #1, then Codex/OpenCode/Kimi; also **Pi** + **Cursor** | Vendor picker = already-fixed-uncommitted (Codex/OC); Pi/Cursor adapters **Fable** sensitive | Claude parity first; Cursor/Pi either shipped or explicitly deferred with owner note |
| **Webapp preview** | Readiness gap | Defer / doc deploy-preview | Documented path or V2 tunnel — not this week’s P0 |
| **GCP relay ~$130/mo cost** | Cursor `2ff457a9` 07-13 — owner wants cheaper, low downtime | **Fable** ops plan → **owner-gated** cutover | Cost down without breaking pairing; parallel setup OK |

---

## G. Recommended swarm order

1. **Fable:** B1 + B2 + B3 root-cause (shared relay/session list / attachmentPut?) — evidence in audit + phone screenshots.
2. **GPT-5.6:** implement fixes in worktrees; Fable re-verifies on device rebuild.
3. **GPT-5.6:** task-notification iOS filter; live `repo.*` review wire; scroll polish; FR/proof placement.
4. Land **vendor picker** + **pairing-durability** (Fable review on durability).
5. **Fable** gap-map E2/E3 vs Desktop/Views + Claude mobile screenshots → GPT-5.6 UI lanes.
6. Terminal Phase 1 (GPT-5.6); Phase 2 only after P0 reliability holds.
7. Owner-gated batch: APNs, emergency stop, Tier 0, plan-limits skip call, C7 hardware, S27 target, relay cost cutover.

---

## H. Verify commands

- `cd daemon/lancerd && go test ./...` (transcript wrappers, attachments, relay)
- `cd Packages/LancerKit && swift build` (+ `swift test` if behavior changed)
- App-target / device rebuild for UI (XcodeBuildMCP) — plain `swift build` skips `#if os(iOS)`
- Owner re-dogfood: `docs/plans/phone-test-session4.md` + R1/R2 + continuity (Agents → Mac session)

---

## I. Session / path index (quick cite)

| ID / path | Why |
|---|---|
| Claude `4a407758-e5c4-477f-b007-099b48def762` | Terminal L1403; Claude mobile L2079; multi-vendor/Siri L2114; Claude+Codex screenshots L2571; FR spam L3030; scroll L3104; continuity L1514/1597/3456 |
| Cursor `cf9acad8-7a69-4763-8f2d-cc33c55e31bb` | Cursor Mobile App refs; IA; Live Activities; chat polish |
| Cursor `c10ba344` / `a30ca9db` | App Store status + POST-110 continuity dogfood |
| Cursor `2ff457a9` | Relay cost reduction |
| Codex `019f5929-05b3-7b12-a8d3-d4e10f39034f` | Swarm continue 07-12 |
| `~/Desktop/Views/` | Claude desktop + Codex app screenshots |
| `~/Downloads/Cursor Mobile App/` | Cursor mobile reference set |
| `~/Downloads/lancer-owner-asks-ledger-2026-07-11.md` | Ledger #18–#31 |
| Canvas | `~/.cursor/projects/Users-roshansilva-Documents-command-center/canvases/lancer-appstore-status-2026-07-13.canvas.tsx` |
