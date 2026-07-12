# P1 repo/cwd hygiene — lane specs (rescued 2026-07-12)

> Rescued verbatim from the dead session's scratchpad. Three disjoint-write-set lanes fixing the owner-reported P0: multiple command-center rows in Workspaces. Lanes T/V implemented (worktrees .worktrees/p1-repo-bucketing, .worktrees/p1-chat-loop); lane W never dispatched.

---

## Lane T — fix/p1-repo-bucketing

# Lane T — one repo, one row: unify Workspaces repo bucketing + honest labels

## Goal (owner P0, 2026-07-12: "Multiple instances of command-center — make sure we can only have one")
Owner's phone shows THREE "command-center" rows + a "roshansilva" row. Root causes are mapped
below with file:line — implement ALL of them. One invariant drives everything: **a single
bucketing rule, applied identically to row derivation, counts, tap-filters, and search.**

Work in THIS worktree only (branch fix/p1-repo-bucketing).

## Verified root-cause map (WorkspaceRepoCatalog.swift unless noted)
- `normalizeCwd` (:81-91) works, BUT `deriveRepos` buckets via
  `matchingRepoCwd(for:among: addedCwds)` (:197, pool built :189) — added repos only. The
  doc-comment (:170-171) claims "added (or derived)" — the code never absorbs sub-paths into
  DISCOVERED repos. A `.claude/worktrees/...` cwd under command-center becomes its own row.
- Relative cwd `command-center` (3 daemon rows) can't realpath (:96-114 returns input) → its
  own pathKey → second "command-center" row alongside the absolute one.
- `/Users/roshansilva` (39 rows, agents dispatched from $HOME) is an ancestor of everything
  under Documents — currently its own "roshansilva" row that, when tapped, shows EVERY
  descendant thread (filter `isEqualOrUnder` :251) while its badge counts only exact matches.
- Empty cwd (1 row) is dropped from rows (:196) but still appears under All Repos as "Untitled".

## Required behavior (the single rule)
Define one function, `bucketKey(forCwd:) -> String?`, used EVERYWHERE:
1. Normalize (existing `normalizeCwd`).
2. Absorb into the longest matching repo root among (added repos ∪ discovered repo roots).
   Discovered repo roots = the set of normalized cwds that are not descendants of another
   conversation cwd or added repo (compute roots first, then bucket).
   EXCEPTION: do NOT treat one repo root as a descendant of another legitimate repo root just
   because of filesystem nesting UNLESS the ancestor is itself a conversation cwd. But DO
   absorb `.worktrees/`, `.claude/worktrees/` style sub-paths: a cwd whose path contains a
   component starting with "." (hidden dir) under an existing root always absorbs into that root.
3. Relative (non-absolute), non-empty cwd: merge into an absolute root whose LAST PATH
   COMPONENT equals the relative path IFF exactly one such root exists; otherwise keep it as
   its own bucket but label it verbatim (still one row per distinct relative string).
4. Empty cwd → nil bucket: exclude from repo rows AND from All Repos count; such threads
   appear only in the All Repos list at the bottom labeled "No folder" (not "Untitled").
5. `/Users/<user>` (the home directory itself): keep as a row but display it as "Home"
   rather than the username, and never absorb OTHER repo roots into it (home is a bucket of
   last resort: only cwds equal to home, or under home but not under any other root, land there).

Counts, `conversations(forCwd:)`, Search chip filtering (`SearchView.swift:20` — currently
exact-equality), and All Repos count (`WorkspacesView.swift:55`) must all use `bucketKey`.
Result: counts sum exactly to All Repos; tapping a row shows exactly `count` threads; one
"command-center" row whose count = 18+3+1(worktree) = 22 on the owner's data.

## Additional fixes (same lane, audited findings)
A. **"Today" bucket missing** — `groupByRecency` (:299-313): everything ≥ startOfYesterday is
   titled "Yesterday". Add Today `[startOfToday, ∞)`, Yesterday `[startOfYesterday, startOfToday)`.
B. **Search status honesty** — `WorkspaceDataStore.search` (:494) maps through the cached
   `lastTurnByConversationID` (recent-200 only) → stale "No activity" on older hits. Fetch the
   last turn per search result.
C. **"No activity" label** — statusKind (:334-352): keep for genuinely turn-less threads, but
   change the label copy to "No runs yet" (honest, clearer); do not change failure/working logic.
D. **handleSend guards** — `WorkspacesView.swift:242-244` + `ThreadListView.swift:147-149`
   accept a relative cwd for live sends. If the resolved bucket is relative/empty, disable send
   into it (composer targets All Repos default instead).
E. **Zero-thread added repo shows no badge** — `WorkspacesView.swift:80`: show "0".
F. **`ForEach(groups.enumerated(), id: \.offset)`** `ThreadListView.swift:86` → key by group title.

## Write-set (exhaustive)
- Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspaceRepoCatalog.swift
- Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift
- Packages/LancerKit/Sources/AppFeature/ThreadList/ThreadListView.swift
- Packages/LancerKit/Sources/AppFeature/Search/SearchView.swift (or wherever filteredResults lives)
- Packages/LancerKit/Tests/LancerKitTests/WorkspaceRepoCatalogTests.swift

## Tests (must cover the owner's exact data shape)
Fixture cwds: `/Users/u/Documents/command-center` ×18, `command-center` ×3,
`/Users/u/Documents/command-center/.claude/worktrees/x` ×1, `/Users/u` ×39, `/tmp` ×8,
`/tmp/lancer-chat-proof-fable` ×4, `` ×1. Assert: exactly ONE command-center row count 22;
"Home" row count 39; /tmp row 8 (does NOT absorb lancer-chat-proof-fable — sibling roots
stay separate: lancer-chat-proof-fable is its own root count 4 since both are real
conversation roots); counts sum == All Repos count; empty-cwd excluded. Plus Today/Yesterday
bucketing tests around midnight boundaries.

## Acceptance (run, paste output)
- `cd Packages/LancerKit && swift build && swift test`
Orchestrator runs app-target + sim gate after.

## Bar
Zero new warnings · Swift 6 concurrency clean · no force-unwraps · pure functions where
possible (bucketing must be unit-testable without a DB) · risk: ui.

---

## Lane V — fix/p1-chat-loop-robustness

# Lane V — chat loop robustness: bridge reset, honest retry, real transcripts on reopen

## Goal (owner P0 sweep 2026-07-12, audited findings with file:line)
Fix the send→close→resend loop and reopen honesty. Work in THIS worktree only
(branch fix/p1-chat-loop-robustness). Do NOT touch WorkspaceRepoCatalog.swift,
WorkspacesView.swift, ThreadListView.swift, SearchView.swift (parallel lane owns them).

## Fixes (all verified file:line)

### 1. P0 — closing a live sheet mid-run permanently wedges the next chat
`LiveThreadPresentation.swift:34-41` injects ONE shared ShellLiveBridge into every
LiveThreadView; nothing resets it on dismiss. Close during working/streaming leaves
`sendState` in-flight, so the next New Chat send hits the `guard !isSendInFlight` at
`ShellLiveBridge.swift:199` and silently no-ops, showing the previous thread's transcript
and a stale "Working…".
Fix: add `ShellLiveBridge.resetForNewThread()` — cancels/abandons the current poll loop
(existing task cancellation is already cooperative), clears sendState/.idle,
transcriptTurns, inFlightPrompt, activeConversationID, observed binds — and call it when
the live sheet is dismissed (`.onDisappear` in the presentation modifier, or on new
LiveThreadIdentifier presentation). The daemon-side run continues (that's fine — the list
sync from #93 keeps its status honest); the UI must not stay wedged.

### 2. P1 — Retry re-sends the INITIAL prompt and wipes the thread
`LiveThreadView.swift:391-407`: errorState Retry calls `bridge.send(prompt: prompt, ...)`
(the sheet's original prompt). After a failed FOLLOW-UP this restarts a brand-new
conversation (`ShellLiveBridge.swift:217-219` wipes transcriptTurns), and on the
observed-adopt sheet `prompt` is "" so Retry sends empty.
Fix: track the last attempted prompt+path (initial send / follow-up / observed continue)
in the bridge; Retry re-dispatches THAT attempt. Never wipe existing transcript on retry
of a follow-up.

### 3. P1 — reopened threads hide the transcript that IS in the local mirror
`ThreadDetailView.swift:148-153` loads full ChatTurns (assistantText populated) but renders
only prompts + the line "Full transcript opens from a live send" (:54) — dishonest.
Fix: render each turn as user bubble + assistant markdown (reuse ChatMarkdownBody and the
visual pattern from LiveThreadView's staticAssistant). Delete the placeholder copy. Keep
the Flight Recorder rows (below each turn or behind the existing affordance — match the
current layout conventions).

### 4. P2 — observed-continue polling force-completes long runs
`ShellLiveBridge.swift:338-401`: bounded 20×2s + 5×2s loops; on expiry stamps
`status = .completed` + completedAt even though completion was never observed, with copy
"Continued on the host…".
Fix: never stamp .completed unobserved. Keep polling with the same cadence as
`pollUntilTerminal` (LivePollPolicy interval) until the transcript stops growing AND a
terminal signal is seen, or transition to the existing degraded presentation (honest
"last update Xs ago") instead of fake completion.

### 5. P2 — fractional-seconds host timestamps silently become .now
`ConversationSyncCoordinator.swift:546-551` single ISO8601DateFormatter without
fractionalSeconds; `parseDate(...) ?? .now` at :578-605 corrupts recency ordering.
Fix: try withInternetDateTime+withFractionalSeconds, then plain (mirror
ProofReelModel.iso8601Date). Add a unit test with both timestamp shapes.

### 6. P2 — receipt decode failures are invisible; raw UTC timestamp in Proof Reel
- `ProofReelModel.swift:57` `try?` swallows decode errors → no card, no signal. Change
  decodeReceiptPayload to log via the existing logging facility (os_log/Logger pattern used
  elsewhere in AppFeature) on failure; keep returning nil.
- `ProofReelView.swift:150-155` renders `command.startedAt` verbatim (UTC ISO string).
  Format via a localized date formatter (reuse iso8601Date to parse).

## Write-set (exhaustive)
- Packages/LancerKit/Sources/AppFeature/Bridge/ShellLiveBridge.swift
- Packages/LancerKit/Sources/AppFeature/LiveThreadPresentation.swift
- Packages/LancerKit/Sources/AppFeature/Chat/LiveThreadView.swift
- Packages/LancerKit/Sources/AppFeature/ThreadDetail/ThreadDetailView.swift
- Packages/LancerKit/Sources/AppFeature/ConversationSyncCoordinator.swift
- Packages/LancerKit/Sources/AppFeature/Chat/ProofReelModel.swift
- Packages/LancerKit/Sources/AppFeature/Chat/ProofReelView.swift
- Packages/LancerKit/Tests/LancerKitTests/** (new/updated tests; parse-date test mandatory)
FORBIDDEN: WorkspaceRepoCatalog.swift, WorkspacesView.swift, ThreadListView.swift,
SearchView.swift, daemon/**.

## Acceptance (run, paste output)
- `cd Packages/LancerKit && swift build && swift test`
Orchestrator runs app-target + sim gate after (close-mid-run → new chat works; reopen shows
full transcript).

## Bar
Zero new warnings · Swift 6 concurrency clean · no force-unwraps · UI copy states what was
asked of the agent, never guarantees · no "completed" without an observed terminal signal.
Risk: ui.

---

## Lane W — fix/p1-ledger-cwd-hygiene

# Lane W — daemon ledger hygiene: no more garbage cwds, prunable approvals

## Goal
The conversations table contains bare-relative (`command-center` ×3), empty (×1) cwds, and
queue.json accumulates approvals with empty RunID that restoreQueue can never prune. Stop all
three classes at write time. Daemon (Go) ONLY — no iOS files, no dispatch.go behavior changes
beyond calling its existing helper.

Work in THIS worktree only (branch fix/p1-ledger-cwd-hygiene).

## Fixes (verified file:line)

### 1. conversationsAppend persists unvalidated cwd (conversation_rpc.go:122)
The phone-append path does `resolvedCWD := expandHome(req.CWD)` only; `resolveDispatchCWD`
(dispatch.go:36 — fail-fast missing/non-dir/relative) runs later in realLauncher, AFTER the
ledger row is committed. A relative cwd persists even though the launch then fails.
Fix: validate via `resolveDispatchCWD` in `conversationsAppend` BEFORE `beginTurn`; on failure
return an RPC error and persist NOTHING. Keep the existing empty→`~` default for new
conversations (line 123-125) — apply the default first, then validate the result.

### 2. attachObservedSession inserts cwd verbatim (conversation_store.go:1283, caller conversation_rpc.go:306)
Observed vendor sessions insert `expandHome(req.CWD)` with no checks — source of the
empty-cwd row.
Fix: in the RPC handler, after expandHome: reject relative paths and empty cwd with an RPC
error (observed sessions whose source can't say where they ran should not create ledger
rows). An absolute path that doesn't currently exist on disk is ACCEPTED here (the session
may reference a removed worktree; history is still valid) — only reject relative/empty.
Note this is deliberately weaker than fix 1: append=launching (must be a real dir), attach=
importing history (must merely be well-formed).

### 3. ApprovalEvent.RunID empty when hook fires outside a dispatched run (server.go:1555-1557)
`runForCWD` only knows in-memory running dispatches; hooks from locally-launched agents get
RunID "" and restoreQueue keeps them forever (fail-closed by design).
Fix: add a second best-effort resolution: if `runForCWD` returns "", query the conversation
store for the most recent RUNNING turn matching (cwd, agent) — reuse/extend an existing store
accessor; add one if needed (read-only SELECT). If found, use its run_id. If still empty,
keep "" (fail-closed keep stays correct); do NOT invent IDs.

### 4. attachObservedSession title bypasses deriveTitle (conversation_store.go:1271-1283)
Wrap the non-empty `title` arg in `deriveTitle` so any future caller is truncated/sanitized.

## Tests
- append with relative cwd → RPC error, NO conversation row.
- append with empty cwd → defaults to home, row created with absolute home path.
- attach with relative cwd → error, no row; attach with empty cwd → error, no row; attach
  with absolute-but-nonexistent → accepted.
- hook event with no in-memory run but a running ledger turn at (cwd,agent) → RunID populated;
  restoreQueue then prunes it after the turn is marked failed.
- attach with an oversized title → stored truncated (80 runes).

## Write-set (exhaustive)
- daemon/lancerd/conversation_rpc.go
- daemon/lancerd/conversation_store.go (attachObservedSession + a read-only accessor if needed)
- daemon/lancerd/server.go (hook ingest RunID backfill only)
- daemon/lancerd/*_test.go
FORBIDDEN: dispatch.go edits (call its exported helper only), policy/, approval.go resolve
paths, resident.go, any iOS file.

## Acceptance (run, paste output)
- `cd daemon/lancerd && go test ./... && go vet ./...`

## Bar
Fail-closed (reject-and-error beats persist-garbage; never invent run IDs) · additive RPC
error semantics (existing success shapes unchanged) · zero vet issues. Risk: sensitive-adjacent
(approval ingest + RPC surface) — the orchestrator full-diff reviews; keep the diff tight.
