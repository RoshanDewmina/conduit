# Fable Frontend Wipe + Rebuild — Status

**Track:** Frontend wipe → Orca study → Apple docs → rebuild
**Gate:** **Wave 0 COMPLETE (Fable 5, 2026-07-09)** — awaiting owner **APPROVED**
**Inventory base:** main checkout, `feat/chat-overhaul-w0a` @ `d4db7da7` (dirty — W0.A in flight)

## Done (Wave 0, this session)

- [`2026-07-09-fable-frontend-wipe-rebuild-Plan.md`](2026-07-09-fable-frontend-wipe-rebuild-Plan.md) rewritten with the executed inventory:
  - **Table 1 DELETE (proposed):** 13 CursorStyle chrome views, 19 dead DesignSystem files/types, 4 orphan modules/files (DiffFeature, FilesFeature, HostKeyConfirmSheet, LivePromptInputView), chrome-only UITests — **importer count + evidence on every row**, orchestrator re-verified with independent `rg`.
  - **Table 2 KEEP (hard):** 13 CursorStyle engine/contract/seam files, SessionFeature engines + governance chat cards, all non-UI modules, all 11 `Lancer/` app-target files, keep-side DesignSystem tokens/atoms — with the why per row.
  - **Table 3 REWRITE/stub:** CursorAppShell rewritten-in-place to a minimal 3-root stub preserving `CursorRoute` names, deep-link parsing, bridge wiring, launch seams; `CursorRelayPairingSheet` + `CursorReviewDiffView` deferred to Wave 3 (pairing/approval must never break); staged delete order + gate.
  - **Table 4 UITests** and **Table 5 extension targets** (LA/status widgets REWRITE-stub with binary contracts pinned; Watch OUT OF SCOPE/KEEP).
  - **Orca notes:** prior 5 citations re-verified line-accurate; new mobile-IA mining (single-root stack, Resume card, connection-health thresholds, sort/group patterns) with file:line; MIT re-verified.
  - **Apple citations:** NavigationStack, safeAreaInset(.bottom), scrollDismissesKeyboard, defaultScrollAnchor, TabView, AppShortcutsProvider, ActivityAttributes + WWDC session index.
  - **Rebuild architecture:** recommendation = keep 3-root IA with Orca-informed content contracts (Home=attention+resume / Workspaces=browse / Settings=manage); bridge API frozen.
- Key discoveries: tree already contains the `25609ca0` rebuild (seed plan's delete list was stale); 9 DS Cursor atoms now outright dead; `ReturnPacketModel` orphaned (owner decision needed); shell deliberately avoids TabView (caching bug); `LANCER_CURSOR_SHELL_LIVE` lives in `CursorShellLaunchSeam` with LIVE-wins rule.
- Process note: first subagent inventory pass ran against a stale worktree — detected, discarded, re-run with mandatory proof-of-tree. No counts from the bad pass survive.
- **Zero product/backend edits this session** (writes = 2 plan docs only; verified via `git status`).

## Remaining

1. Owner reviews Plan Tables 1–5 + IA recommendation → replies **APPROVED** (with any row edits / IA override).
2. Owner lands or checkpoints the dirty W0.A dogfood work on `feat/chat-overhaul-w0a` (12 CursorStyle files IN-FLIGHT).
3. Separate Wave 1 session, isolated worktree: staged deletes per approved tables → verify gate (swift build/test, app-target build, mock-shell smoke, `CursorShellLiveApprovalTests`, no `daemon/**` in diff).
4. Wave 2 rebuild plan → Wave 3 implement (new briefs; Done-bar D1–D10 from the shell-rebuild brief).

## Blockers

- **Wave 1 is blocked on owner APPROVED** and on the W0.A checkpoint — both by design.
- None for the review itself.

## Next agent instruction

Do nothing until the owner replies **APPROVED** (optionally with table edits / IA choice). Then request a Wave 1 execute brief; execute only in an isolated worktree; never touch `daemon/**`; keep pairing + approval surfaces alive through the wipe.

## Explicit non-goals this gate

- No product deletes/edits yet · no backend deletes/edits ever on this track
- No Wave 3 implement · no Siri Approve intent · no Face ID gate · no iOS 27 target raise
