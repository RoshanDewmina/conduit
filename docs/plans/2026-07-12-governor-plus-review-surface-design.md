# Governor+ review surface — design (owner-approved scope A, Codex-mobile 1:1 visual reference)

Owner decisions (2026-07-12): scope **A — Governor+** (no IDE panes); visual design **copy the
Codex mobile app 1:1** (11 reference screenshots, owner: "absolutely perfect"). Research base:
Orca deep-dive (2026-07-12 agent report) — key finding: Orca does NOT have per-turn git
baselines, edit-chip Undo, or turn duration labels; those are NEW daemon work. Orca's shipped
MOBILE review queue (MobileDiffReview*) validates the phone form factor; its live-status comes
from agent hooks, not stream parsing (we already have hooks).

## What we're building (Codex-mobile anatomy → Lancer)

1. **Inline turn-diff card** (in chat, after a turn that edited files): "N files changed +A −D"
   collapsible; expanded rows = per-file path + per-file +a −d. Data: daemon turn diff (below).
2. **Session-total floating pill** above the composer: "21 files +442 −0" — whole-conversation
   diff vs the session baseline; tap → full review sheet.
3. **Review sheet** (Codex 1:1): grabber; X close; "N files changed / +A −D" title;
   expand/collapse-all toggle (top-right); **Modified | All Files** segmented control.
   Modified = file sections with sticky header (name, dimmed dir path, +a −d, open-in-viewer
   button) and per-hunk collapsible "Lines X–Y +a −d" groups with colored unified diff lines
   and line numbers. All Files = repo file tree (below).
4. **Line comments**: tap/long-press a diff line → "Add Comment" sheet (Cancel / Attach):
   quoted file:line + the line content, comment field. **Attach queues the comment into the
   composer as context for the next send** (Codex behavior) — comments ride the next follow-up
   to the agent, formatted as "file:line — quoted line — comment".
5. **All Files browser**: lazy repo tree over daemon RPC (dir listing per expand), search-files
   field pinned bottom; tap file → **file viewer** (Done / share; syntax-ish monospaced with
   line numbers; read-only). Serves the file links in prose too ("ProfileView.swift ↗").
6. **"Worked for Nm Ss ›"** collapsible turn-group header (chevron expands the turn's chips) —
   duration from turn started/completed timestamps (ledger already has them).
7. **Live status line** (Claude-Code style): status pill while a run is live — "Calling
   XcodeBuildMCP…", "Thinking…", "Editing ChatUI.swift…", with elapsed time and a >30s
   stall hint ("still working…"). Source: approval-hook + stream events the daemon already
   ingests (Orca precedent: hook-reported toolName, never stream regex). Mutually exclusive
   with streamed text (Orca native-chat-streaming rule, MIT, attribute).

## Daemon additions (the real new work — Orca lacks these)

- **Per-turn shadow baseline**: at each turn start/end on a dispatched run, `git write-tree`/
  `commit-tree` a shadow ref (refs/lancer/turns/<runId>) — never touches the user's index or
  HEAD. Turn diff = `git diff --numstat baseline..end`; session pill = first-turn baseline..now.
  New RPCs: `repo.turnDiff(conversationId, turnId)` → {files[], +a/−d, hunks on demand
  `repo.fileDiff(...)`}, `repo.tree(path)`, `repo.file(path, maxBytes)` (read-only, path-jailed
  to the conversation cwd, same fail-closed posture as dispatch).
- **Live status events**: daemon already sees PreToolUse hooks (tool name/input) and stream
  deltas; emit ephemeral `status` relay messages {state: thinking|tool(name,target)|streaming,
  startedAt} — ephemeral per the roadmap's persistent-vs-ephemeral split (never ledger rows).
- Undo is explicitly **deferred** (Orca finding: safe undo needs pre-edit snapshots + stacked-
  edit unwind; whole-file git checkout silently destroys later edits — do not ship that).

## Lanes (disjoint write-sets)

- **G1 daemon** (sensitive-adjacent: new read-only RPC surface + shadow refs): turn baselines,
  turnDiff/fileDiff/tree/file RPCs, status events. Go tests incl. path-jail.
- **G2 iOS review UI** (ui): review sheet, turn-diff card, session pill, line-comment→composer,
  file tree + viewer. Fixture-driven; gates on sim with a real turn diff.
- **G3 iOS live status** (ui, small): status pill + elapsed/stall, wired to status events;
  falls back to today's "Working…" when events absent.
Order: G1 → G2/G3 parallel. After the current tester-blocker queue (REL-1 first) per the
standing priority; G3 can ride earlier since it's small and event-additive.

## Interaction decisions (owner delegated 2026-07-12: "go with what seems best")

1. **Line-comment Attach queues into the composer** as context for the next send, rendered as
   an attached chip ("Status.md:16 · 1 comment") the user can remove before sending; the sent
   follow-up embeds "file:line — quoted line — comment" blocks. No auto-send.
2. **Session pill baseline = conversation start** (shadow ref stamped at the first dispatched
   turn; observed-imported threads fall back to the earliest turn baseline available).
3. **All Files browser is path-jailed to the conversation's repo cwd** (same fail-closed jail
   as `repo.file`/`repo.tree`); other repos are reachable by opening their own threads.
