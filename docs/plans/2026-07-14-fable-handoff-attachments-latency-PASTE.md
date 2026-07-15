# Fable handoff — fix the recurring issues, biggest first (2026-07-14 → 15 session close)

**Generated:** 2026-07-15T09:50Z · **Branch:** `master` @ `292525b7` (pushed, matches origin)
**Owner directive for this handoff:** today is the last day of laptop-side development — the
owner is switching to daily-driving and dogfooding through the **mobile app** starting now.
**Fix the issues we've been having, starting with the biggest first.** "Biggest" = whatever most
blocks basic phone daily use, not feature scope.

**Source docs (read in this order, all live under `docs/plans/` — do not re-derive from raw chat
transcripts, none of the underlying Cursor/Claude conversation IDs resolve on this Mac):**
1. This file — priority-ordered work list with evidence.
2. `docs/plans/orchestrator-state.md` — Session 7 (2026-07-14) has the full narrative of what
   this session actually did; earlier sessions above it have older context.
3. `/Users/roshansilva/Downloads/lancer-beta-handoff-2026-07-14/` — the external bundle this
   session continued from (repo/branch state snapshot, patches, plans).
4. `/Users/roshansilva/Downloads/lancer-2026-07-13-fable-handoff/` — an **older** Fable brief from
   two days prior. **Its "known repo state" section is stale — master has moved ~15 commits since
   its cited tip `0e0b9eba`, and its model-routing table (which references "GPT-5.6") does not
   match current `CLAUDE.md`, which only names Cursor CLI Grok/Composer + Sonnet 5. Do not follow
   that doc's routing table.** What's still valuable from it: a **recurring-bug table tracking
   the same failures across 07-11 → 07-13**, and a bug (`"Machine unreachable"` copy, and photo
   attachment chip spinner) that this session's own verification shows is **still unresolved in
   current code** — both are folded into the priority list below with fresh verification, not
   copied blind.

---

## What's already done (verified this session, not just claimed)

**P0 — the biggest recurring bug, auth/relay stuck-Working after reconnect, appears fixed —
merged, but needs more confirmation than one clean run (see priority #1 below for why).**

- Root-caused a phone reinstall (`SQLite error 14`) as a broken app container, not a code defect
  — confirmed by a clean simulator boot of the same build; reinstalled + re-paired.
- Ran the physical-device proof `fix/relay-append-correlated-resume` existed for: force-quit →
  reopen → wait Connected → wait 16s → send `Reply with exactly reconnect-ok. Do not use tools.`
  → `reconnect-ok` in 3.0s, no Retry, no duplicate turn. Independently corroborated against
  `~/.lancer/audit.log` (exactly one `conversation-append-launched` entry).
- Fresh gates before merge: `go test ./...` clean, 38/38 focused Swift suites clean, including
  `"append retries keep the same clientTurnId so the host can dedupe"`.
- Fast-forward merged to `master` (`e1309f95..292525b7`), pushed. `fix/claude-auth-ttfo` is now a
  fully-included ancestor — superseded, safe to delete.
- Confirmed already resolved (verified against current code, not assumed): the fixture review
  pill bug (`RelayReviewDataSource` genuinely calls live `repo.turnDiff`/`sessionDiff` RPCs, not
  a stub — matches merged commit `c90bed67`), the vendor picker (Codex/OpenCode chip present),
  the `<task-notification>` daemon-side import skip, and pairing durability (superseded by a
  different fix, #116, already in master history before this session started).

---

## Priority-ordered remaining work — biggest first

### 1. (BIGGEST) Confirm the reconnect/stuck-Working fix actually holds — this bug has beaten multiple "fixes" before

**Why this is #1:** this exact failure mode — first message after pairing/reconnect either hangs
in "Working…" forever with a dead Follow-up bar, or silently drops — has recurred across **at
least four separate dates**: 07-11 (timeouts), 07-12 (×3 separate live sessions), 07-13 (`REL-1
#110` merged specifically to fix it, then confirmed still failing on device the same day), and
this session's `fix/relay-append-correlated-resume`. This session proved it fixed **once**, live,
cleanly. Given the history, one clean run is not enough evidence to trust it — #110 also looked
fixed until the next dogfood session.

**Done when:** 10 consecutive force-quit → reopen → wait Connected → first-send cycles complete
without a Retry button appearing and without a duplicate turn. This is the actual bar from the
July 13 recurring-bug table (`"10 consecutive reconnect→first-send successes without Retry"`) —
use it verbatim, don't relitigate what "done" means.

**If it fails even once:** treat as failed-after-fix, not a new bug — root-cause against the
`fix/relay-append-correlated-resume` diff specifically (`ShellLiveBridge.swift`,
`E2ERelayBridge` first-send/append-resume correlation, `daemon/lancerd/dispatch.go`
`launchConversationTurn`), since that's the fourth attempt at the same failure class.

---

### 2. Desk Mac ↔ phone continuity — the owner's repeatedly-stated #1 product ask, and it's still broken

**Why this is #2:** per the July 13 brief, this was called out explicitly as **"Owner primary
product ask (repeated 07-12 → 07-13)"** — being able to see and continue a desk Claude Code
session from the phone. It is blocked by the same underlying issue the owner hit again *this
session*: tapping the `swarm-orchestrator-lancer...` entry under Agents (a live/observed session
mirrored to the phone) "didn't work," and this was never actually investigated — I deferred it to
stay on the P0 proof and it's still an open bug with no repro screenshot.

**Also unresolved (verified against current code, not assumed):** the `"Machine unreachable — no
successful update yet"` degraded-state copy (`LivePollPolicy.swift:75`,
`RunningAgentsMapping.swift:221`) is unchanged since the July 13 bug report, which described it
showing even while Trusted Machines itself reports Connected. The underlying poll/freshness logic
(`RunningAgentsFreshness`, `!hasEverSucceeded`) has not been touched since. Not confirmed broken
right now (a fresh phone check is needed), but the code path that produced the bug is unchanged.

**Done when:**
1. Reproduce the agent-tap failure with a screenshot (blank screen? error? freeze?) — get real
   evidence before diagnosing.
2. With zero agents running and a healthy relay connection, Agents shows **"No agents running,"**
   never "Machine unreachable" — that copy should only appear on genuine repeated poll failure.
3. A desk Claude Code session appears in the phone's Agents list within ~2s of Connected, opens,
   shows the full transcript, and a follow-up sent from the phone round-trips back to the desk
   session.

---

### 3. Attachment work is code-complete but unproven — this is the same bug the owner hit on 07-13

**Why this matters:** the July 13 bug report was a photo-attachment chip stuck spinning forever,
send disabled. This session drove `feat/attachment-daemon-dispatch` + `feat/attachment-ios-ux`
through multiple security review cycles to a feature-complete state (server-issued
`contentDigest`, content-addressed objects, TOCTOU rehash, path/symlink containment) and merged
them into `feat/attachment-integration` (`92823811`, pushed) — but that branch predates today's
P0 merge and needs a rebase, and **none of it has been proven live on device.** The specific
regression to check is the exact July 13 symptom: does the attachment chip actually reach
`.done` and send, instead of spinning forever.

**Done when:**
1. Rebase/merge `feat/attachment-integration` onto current `master` (`292525b7`) — expect real
   conflicts in `dispatch.go`'s `launchConversationTurn` (documented order: clean policy+digest →
   budget/policy → Claude-only gate + attachment verify → `ensureClaudeAuth` → vendor manifest →
   launch). `dispatch.go` is security-sensitive — Sonnet 5 implementation + full-diff review, not
   Cursor/Grok.
2. `go test ./... && go test -race ./... && go vet ./...` clean; Swift package + app-sim build +
   `AttachmentPreviewUITests` green.
3. Co-install the digest-hardened daemon **and** digest-aware iOS app together on the phone (old
   daemon + new app, or the reverse, fails closed by design — never install one half).
4. Live proof: photo attach → chip reaches `.done` → send → desk agent prompt actually contains
   the file. Also: PDF, multiple attachments, force-quit/relaunch persistence, Retry after a
   forced failure keeps the same `clientTurnId` (no duplicate), no `hostPath` ever visible in UI
   or accessibility labels.

---

### 4. Latency fix — real and proven, needs one decision then a push

**State:** root-caused and fixed this session (`perf/conversation-turn-cold-start`, `4f4ad218`,
**not yet pushed to origin**). A trivial "Hi" to Claude/Haiku was taking the owner 11 seconds;
root cause was 23 MCP servers' tool schemas loading into the system prompt on every single
phone-dispatched turn (this project's 5 dev-tooling servers + ~18 of the owner's personal/global
connectors), forcing a cold prompt-cache write server-side. Fix adds `--strict-mcp-config` to the
`claudeCode` case in `agentArgv`/`continueArgv`/`resumeArgv`. Verified two ways: raw CLI timing
(`ttft_ms` 9,966ms → 4,110ms, 58% cut) and a real end-to-end send through the actual app UI in
the simulator (11.0s → 4.0s, same "Hi", same Haiku model, isolated test daemon so the phone's
real pairing was untouched).

**The unresolved tradeoff — decide, don't silently ship either way:** this flag applies to
**every** phone-dispatched Claude turn, chat or real coding task alike — there's no way to tell
them apart at dispatch time. A phone-dispatched coding task loses XcodeBuildMCP/apple-docs/
context7 access under this fix and falls back to raw shell commands. Given the owner is about to
start daily-driving from the phone specifically to do real work, this tradeoff deserves an actual
decision, not a default.

**Done when:** owner decides (ship as-is, or scope it to a heuristic/config so real coding
dispatches keep MCP tools) → push `perf/conversation-turn-cold-start` → rebase onto current
`master` (also predates the P0 merge) → `go test ./...` clean → merge.

---

### 5. Everything else from the July 13 backlog — lower priority, don't drop, don't front-load

Kept as a compact reference so nothing owner-requested silently disappears. None of this blocks
the owner starting to daily-drive the phone; sequence after 1–4.

**Worth a quick regression check, likely already fine:**
- `<task-notification>` raw XML on *old* imported threads (daemon-side skip landed for new
  imports; old ledger rows may still need an iOS display filter — quick to verify).
- Scroll-to-bottom arrow polish, Flight Recorder / proof-chip placement (owner previously said
  "why after every response?" — should be ⋯-menu only, not automatic).
- `"+"` vs `Add Repo` — two affordances for one action, should be one.
- Backfill paging past 50 host rows on fresh install.

**Real feature work, explicitly owner-gated or lower priority (from the July 13 owner-asks
ledger #18–#31 — full detail in `lancer-2026-07-13-fable-handoff/2026-07-13-fable-owner-asks-complete.md`
§F if needed, don't re-paste the whole table here):** APNs lock-screen approve re-proof, plan-limits
display, Claude account hot-swap + identity badges, in-app bug reporting, artifacts rendered
inline (outbound direction), Siri/iOS-27 deep work, CloudKit second-device sync (needs hardware
the owner doesn't have), Tier-0/5c re-proof, Emergency Stop re-verification, a daily dogfood-log
habit, multi-vendor parity beyond Claude (Pi/Cursor adapters), GCP relay hosting cost (~$130/mo,
owner wants it down), and a documented webapp-preview path.

**Feature/design port work, explicitly deferred until after reliability holds (E1–E4 in the July
13 brief):** full terminal support (spec already written at
`docs/product/2026-07-12-orca-terminal-port-map.md`, not started), Claude-desktop/Codex-app
feature parity, Claude-mobile transcript-formatting parity, Cursor-mobile IA/polish references.

---

## Process notes worth carrying forward

- **Possible false-positive test failures, check this before treating them as real regressions:**
  the July 13 brief notes `RelayMachineMigrationTests` can **collide across concurrent `swift
  test` runs in different worktrees because they share the same Keychain** — run LancerKit test
  suites serially, not in parallel across worktrees. This session saw exactly those tests fail
  (6/866) during the attachment-integration full-suite run; they were treated as pre-existing and
  unrelated based on file-overlap analysis and reproducing on plain `master`, but this Keychain-
  collision explanation was not checked and is a real alternative explanation worth ruling out.
- Model routing: use **current** `CLAUDE.md` (Cursor CLI Grok 4.5 high / Composer 2.5 for
  implementation, Sonnet 5 for security-sensitive paths and anything Cursor failed twice) — not
  the July 13 doc's routing table, which references a "GPT-5.6" tier that no longer appears
  anywhere in current process docs.
- `dispatch.go`, `e2e_router.go`, approval/`ContentHash`, and relay protocol types are
  security-sensitive per `AGENTS.md`/`CLAUDE.md` — Sonnet-or-Fable implementation and full-diff
  review, never Cursor/Grok, for these specific files.
- Do not install/restart the daemon or touch phone pairing without the owner present — verify
  physical-device claims against `~/.lancer/audit.log` and `~/.lancer/lancerd.stderr.log`, not a
  status report alone. This session's own mistake — pushing a physical install before a basic
  simulator boot check — is worth not repeating; boot-check any new build on simulator first.
- `fix/claude-auth-ttfo` branch is a fully-included ancestor of `master` now — safe to delete.
