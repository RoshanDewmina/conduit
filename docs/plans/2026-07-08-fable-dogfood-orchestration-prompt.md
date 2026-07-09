# Fable prompt — Lancer dogfood → public readiness (paste into Claude Code)

**For Milroy:** open a new Claude Code session in `/Users/roshansilva/Documents/command-center` with Fable (`--model fable` / `claude-fable-5-thinking-high`). Paste **everything below the `=====` line**. Do not paste this header.

**Verified before this brief (2026-07-08 ~21:40 America/Toronto):**
- Chat hotfixes committed on `master` as **`f610306a`** — model slug remap + relay routing-id persistence. `go test ./...` PASS; `swift build` PASS. **Still insufficient** for multi-turn (stale `baseSeq` + wiped thread UI remain).
- Owner authorized **phone reinstall** for this run.
- Owner will run Fable; Fable dispatches **Composer 2.5** (default) via `cursor-agent`.

=====

You are **Fable 5**, top-level orchestrator for Lancer. You **plan, verify, and delegate** — you do not type application code except trivial one-line doc fixes. Implementation routes through **`cursor-agent`** on this Mac (`/Users/roshansilva/.local/bin/cursor-agent`), workspace `/Users/roshansilva/Documents/command-center`.

**Owner mandate (2026-07-08 evening):** Chat is broken on device and is the #1 blocker. Overhaul chat first, then immediately build cross-device continue, then finish a max dogfood slice (pairing UI + search + GitHub add-repo). Produce a ranked multi-day plan for everything else toward public/TestFlight readiness. **Start building after the read pass — do not stop at a plan for Wave 0.**

This is a deliberate, scoped deviation from `CLAUDE.md`'s Claude-only Agent dispatch: for **this run only**, subagents are Cursor CLI. Do not edit `CLAUDE.md` to match.

---

## 0. Read order (do this BEFORE any dispatch)

Re-verify live repo over every doc (`git log -8 --oneline`, `git status`, `gh pr list`). Working code wins.

### 0.1 Repo contract
1. `AGENTS.md`
2. `ARCHITECTURE.md` §0.1 + §4.1
3. `docs/AGENT_READ_FIRST.md`
4. `docs/STATUS_LEDGER.md` (tip claim may be stale — re-check `git rev-parse HEAD`)
5. `docs/agent-contract.md`
6. `docs/LIVE_LOOP_RUNBOOK.md` (conflict UX ~Refresh + Resend)
7. `docs/product/2026-07-06-feature-implementation-gap-matrix.md`
8. `docs/product/FEATURE_BACKLOG.md` (treat as scope list; distrust stale "mock" captions vs gap matrix + code)
9. `docs/PUBLISH_READINESS_CHECKLIST.md`

### 0.2 Today's Fable / Cursor archaeology (skim; do not re-derive)
**Must-read:**
- Claude Fable: `3a50328d` (primary cleanup orchestrator), then `845e097b` / `2d6e0186` (session-limit hop)
- Claude Fable morning: `511c29bb`, `afab6d27`
- Cursor parent: `5983442d` (evening merges, 5c, phone walkthrough)
- Downloads:
  - `~/Downloads/2026-07-08-lancer-chat-experience-fable-handoff.md` ← **chat failure bible**
  - `~/Downloads/2026-07-08-fable-completion-gap.md`
  - `~/Downloads/2026-07-08-fable-remaining-closed.md`
  - `~/Downloads/2026-07-08-lancer-frontend-audit.md`
- Plans: `docs/plans/2026-07-08-fable-cleanup-orchestration-brief.md`, `docs/plans/2026-07-07-fable-cursor-orchestration-prompt.md`, `docs/plans/2026-07-08-lancer-layer-4-6-lane-proposal.md`

**Skip/skim:** Jul 7 prompt scaffolding (`351f4fac`); duplicate tails.

### 0.3 Chat UI research (before writing Wave 0 UI lane specs)
Spend a short research pass (you or one **read-only** Composer subagent) on modern agent chat UI patterns — adapt ideas to **SwiftUI**, do not port React:
- Vercel AI SDK UI: message **parts** (text / tool / error / streaming), not a single ephemeral string; Stop while generating; regenerate vs retry
- How **Cursor** mobile/desktop presents agent threads (tool cards, streaming, history that never wipes) — use `docs/design-reference/cursor-mobile-2026-07-08/` + any public Cursor UI references; Proof Reel stays receipt scrubber for now (research parity, don't rebuild as video)

Write findings into a short note under `docs/plans/2026-07-08-chat-ui-research-notes.md` (or `/tmp` if you prefer not to commit yet) before dispatching UI implementation.

---

## 1. Model tiering (owner override for this run)

| Role | Model | Use |
|------|--------|-----|
| You | Fable 5 (Claude Code) | Plan, write subagent prompts, verify acceptance yourself, resolve conflicts |
| Default subagent | **`composer-2.5`** via `cursor-agent --model composer-2.5` | Mechanical implementation, UI from specs, wiring, table-driven tests |
| Hard / retry | **Sonnet 5** (`claude-sonnet-5-high` or newest listed Sonnet 5 — run `cursor-agent --list-models` first) | Sync/seq correctness, security/fail-closed, architecture after Composer fails verification twice |
| Forbidden | opencode, deepseek, Fable-as-subagent, gpt/codex unless owner says | — |

Before first dispatch:
```bash
cursor-agent --list-models | rg -i 'composer-2\.5|claude-sonnet-5'
cursor-agent status
```

Budget ~90s+ startup for `cursor-agent -p`. Timeout hung runs (~10 min no output → kill, retry once).

---

## 2. Parallelism rules

- One **git worktree** per lane; **never** two writers on the same files.
- Prefer `git worktree add .worktrees/<lane> -b feat/<lane> origin/master` (or current tip after rebase).
- Merge/rebase against current tip — **never** whole-file `cp` across worktrees.
- Phone reinstall is **owner-authorized** for this run; still tell Milroy before you install, and paste the install command/result. Pairing may need re-entry of the code.
- Do not expand into **Away Launch Composer** until Wave 0 chat is green (owner deferred).
- Do not build relay-hosted terminal this run.
- Watch app remains **cut**.

---

## 3. Wave plan (build order)

### WAVE 0 — Must ship for dogfood (BUILD NOW)

#### W0.A — Chat / work-thread overhaul (P0 — start here)
**Blocked already (phone, 2026-07-08/09):**
1. Invalid `ManagedModel` slugs → exit 1 *(mitigated in `f610306a` daemon normalize; still fix iOS source)*
2. Bare `agentID` → "Unknown agent." on continue *(mitigated in `f610306a`; keep + harden `host_id`)*
3. Stale `baseSeq` → **"Conversation changed. Refetch before appending."** on "Thank you" after successful file-create — `conv_e28912a4-…`, host `last_seq=7`, one turn only
4. Thread UI wipes history — routes by **prompt title**, renders ephemeral `activeThreadPrompt`/`activeThreadResponse` only

**Evidence:** `~/Downloads/2026-07-08-lancer-chat-experience-fable-handoff.md`; host `~/.lancer/conversations.sqlite`; audit `d95c817c…`; code: `CursorAppShell.swift` (`workThread(payload.prompt)`), `CursorWorkThreadView.swift` (narration), `ConversationSyncCoordinator` conflict branch (no auto-retry), `conversation_store.go` BaseSeq gate, `HostedAgent.ManagedModel`.

**Deliver:**
- Route by stable `conversationID`, never prompt title
- Transcript from `ChatConversationRepository` turns/events; bridge fields = live overlay for current run only
- Refresh-before-append **or** conflict → refetch → update `lastHostSeq` → retry once (update tests that currently assert "no retry")
- Persist daemon `host_id`; keep full `relay|<uuid>|<vendor>` routing id
- Fix `ManagedModel` for Claude Code aliases; keep daemon normalize as defense-in-depth
- Error banner + Retry/Refresh; **never** blank the transcript
- Absolute cwd from repo picker (not `~` / home by default when a repo is selected)
- Research-informed parts-style rendering (user / assistant / tool / error / streaming)

**Accept (you run, paste output):**
1. `go test ./...` in `daemon/lancerd`
2. `cd Packages/LancerKit && swift build` (+ sync/routing tests)
3. XcodeBuildMCP app-target sim build
4. Automated continue e2e: turn1 → stream (seq advances) → turn2 without conflict
5. **Owner phone script** (after install): new thread in real repo cwd → create file under `/tmp/lancer-chat-proof-…` → "what did you create?" → both turns visible; no Unknown agent; no Refetch conflict; history survives error banner

**Suggested sub-lanes (exclusive write-sets — you define exact files):**
- `feat/chat-identity-ui` — routing + `CursorWorkThreadView` transcript (Composer)
- `feat/chat-sync-continue` — seq/conflict/host_id (Composer first; Sonnet if fails)
- `feat/chat-model-cwd` — ManagedModel + composer cwd (Composer)

#### W0.B — Cross-device continue (build **immediately after** W0.A green)
Start conversation on device A → continue on device B (and reverse). Host ledger + CloudKit mirror exist but **two-device QA unverified** (`PUBLISH_READINESS_CHECKLIST` C7).

**Accept:** documented two-device script + at least one successful continue on second device with matching `conversationID` / seq; conflict recovery if A and B race.

#### W0.C — Trusted machines / pairing management UI
Replace remaining old/weak host-management UX with Cursor-shell Settings surfaces. Live pairing sheet exists; management/list/remove/trust flows still feel legacy.

**Accept:** sim screenshots in `docs/test-runs/` + pairing still works after reinstall.

#### W0.D — Search polish
Conversation FTS is live (`CursorSearchOverlay` / `chat_fts`); finish scope chips / empty states / open-thread-from-hit so it feels product-ready (not mock).

#### W0.E — GitHub add-repo (wire for real)
`CursorAddRepoSheet` is currently **demo/mock**. Wire to real add-repo path (daemon/GitHub as designed in backlog) or honest disable — no fake success.

**Wave 0 done bar:** W0.A–E merged (or stacked PRs) + phone chat script PASS + cross-device continue PASS + add-repo not a lie.

---

### WAVE 1 — Ranked plan + build after Wave 0 (public / TestFlight path)

Produce a dated ranked plan file (`docs/plans/2026-07-08-public-readiness-wave-plan.md`) covering **all** of the below, then start the top items only after Wave 0 is green (unless a lane is fully disjoint and owner says go).

| Priority | Item | Notes |
|----------|------|--------|
| 1 | Siri / App Intents / never-open-app | Intents exist; many still `openAppWhenRun: true`. Goal: approve + status + continue without opening app where platform allows |
| 2 | Dynamic Island / Live Activities | Pipeline exists; **not observed** on Jul 8 device — make LA/DI visible for active run + pending approval |
| 3 | Fonts / typography consistency | Finish A3 token adoption; kill hardcoded light-only onboarding |
| 4 | WWDC 2026 / iOS 26–27 | Target remains **iOS 26.0**; adopt 27 APIs behind availability; Liquid Glass / modern chrome only where it fits Cursor shell |
| 5 | GitHub PR/diff/ship UI | Daemon gated ship **shipped**; wire `CursorPRDetailView` / ship sheets (not mock) |
| 6 | Localhost browser on mobile | `PreviewKit` exists, unwired — wire a V1 surface or cut explicitly |
| 7 | Mobile verification harness | Question round-trip in `relay-approval-e2e.sh`; post-A3 exhaustive UI re-run |
| 8 | Proof Reel parity research | Keep receipt scrubber; research Cursor-like proof presentation; **no video capture required this wave** |
| 9 | Screen recorder / video attachments | **Later** — composer attachments currently disabled |
| 10 | Away Launch Composer | **Deferred until chat green** (owner) — then unfreeze as next product lane |
| 11 | Billing / StoreKit vs Stripe | Publish checklist P1 |
| 12 | Remote (non-localhost) host E2E | Publish checklist C1 |

---

## 4. Dispatch template (every subagent)

```bash
git fetch origin
git worktree add .worktrees/<lane> -b feat/<lane> <current-tip-sha>

cursor-agent -p --force \
  --model composer-2.5 \
  --workspace /Users/roshansilva/Documents/command-center/.worktrees/<lane> \
  --output-format json \
  "TASK: <id>
   WRITE-SET: <exclusive files only>
   CONTEXT: read AGENTS.md; chat handoff ~/Downloads/2026-07-08-lancer-chat-experience-fable-handoff.md
   SPEC: <verbatim acceptance criteria>
   ACCEPT: <exact commands — run and paste real output before claiming done>
   RULES: no Face ID; Cursor shell only; no Away Launch Composer; no terminal; fail-closed; do not revert unrelated dirty files"
```

You re-run ACCEPT yourself. Distrust subagent "done".

---

## 5. First 60 minutes (efficiency)

1. Read §0 (docs + handoff + tip `f610306a`+).
2. Chat UI research note (§0.3) — short.
3. Decompose W0.A into 2–3 exclusive write-set lanes; open worktrees; dispatch Composer in parallel.
4. While they run, draft Wave 1 ranked plan file.
5. Verify W0.A → install to phone (authorized) → owner script.
6. Immediately start W0.B (cross-device) when W0.A green.
7. Parallelize W0.C/D/E only when write-sets don't collide with chat.

---

## 6. Status reports to Milroy

After each wave slice: tip SHA, PRs, ACCEPT command outputs, phone result, next dispatch. If blocked on owner taps (Siri, second device, App Store), say exactly what you need.

**Done for tonight's "users" bar:** Wave 0 green on device (chat multi-turn + cross-device + pairing/search/add-repo honest). Wave 1 plan written and first Wave 1 lane started if time remains.

Do not claim public App Store ready until Wave 1 publish checklist items are actually verified.
