# Handoff — Frontend scorched-earth wipe (2026-07-09/10)

**For the next agent.** Read this + live git. Do not re-derive from chat.

## Goal that was executed

Owner wanted **all frontend UI gone**, nothing left to look at, **no stub / no rebuild**. Rebuild is a **later session owned by the human**.

Locked answers: **1C / 2A / 3A**
- **C** = scorched earth (delete `CursorStyle/` views **and** former hard-KEEP bridges/engines, entire `DesignSystem/`, SessionFeature Chat/UI, orphan UI modules, chrome tests, widget UI sources)
- **A** = broken compile OK
- **A** = checkpoint dirty W0.A → wipe in isolated worktree

## Where the work is

| Item | Value |
|---|---|
| Wipe worktree | `/Users/roshansilva/Documents/command-center/.worktrees/frontend-scorched-wipe` |
| Wipe branch | `feat/frontend-scorched-wipe` (uncommitted deletes — **not committed**) |
| Base commit | `e850b126` (Wave 0 plan docs) |
| Main checkout | `/Users/roshansilva/Documents/command-center` on `feat/chat-overhaul-w0a` @ `e850b126` |
| W0.A dogfood checkpoint | `stash@{0}` + branch `checkpoint/w0a-dogfood-pre-scorched-wipe` |

**Start here:** `cd` the wipe worktree (or `git worktree list`). Do not invent deletes on main.

## What was deleted (~113 paths)

- `Packages/LancerKit/Sources/AppFeature/CursorStyle/` — **entire dir** (shell, views, LiveBridge, contracts, transcript engines, etc.)
- `Packages/LancerKit/Sources/DesignSystem/` — **entire dir** (tokens, atoms, fonts)
- `SessionFeature/Chat/` + `LivePromptInputView.swift`
- `DiffFeature/` + `FilesFeature/` (+ removed from `Package.swift`)
- `HostKeyConfirmSheet.swift`, `PaywallSheet.swift`
- `LancerLiveActivityWidget/*.swift`, `LancerWidget/*.swift`
- All `LancerUITests/*.swift` (6 files)
- Cursor* + chat-card / ThreadAttention unit tests

Also: `Package.swift` cleaned of DesignSystem / DiffFeature / FilesFeature / MarkdownUI products+targets.

## What was NOT deleted (still present)

- `AppRoot.swift` + AppFeature stores / sync / dispatch / approval ingest (still reference deleted types)
- SessionFeature **engines** (E2ERelayBridge, ApprovalRelay, LiveActivityManager/attributes, RunDispatchService, SessionViewModel, …)
- `Lancer/` app intents + `@main`
- Non-UI kits: LancerCore, Persistence, Sync, SSH, Security, AgentKit, Notifications, IntentsKit, TerminalEngine (`RawTerminalView` still there), PreviewKit, Inbox/Onboarding/Settings VMs
- Watch targets
- **`daemon/**` — OFF LIMITS; untouched in wipe tree** (main checkout may still have unrelated dirty `dispatch.go`)

## Evidence

- Dirs gone: `CursorStyle`, `DesignSystem`, `SessionFeature/Chat`
- iOS app-target `build_sim` **FAILS** (e.g. `cannot find 'QuestionCardModel'` in `CommandGateway.swift`) — expected
- macOS `swift build` can still look green because `AppRoot` is `#if os(iOS)`

## Docs

- Plan (Wave 0 inventory; execute scope superseded by C/A/A): `docs/plans/2026-07-09-fable-frontend-wipe-rebuild-Plan.md`
- Status: `docs/plans/2026-07-09-fable-frontend-wipe-Status.md`
- Prior Wave 0 PASTE: `docs/plans/2026-07-09-fable-frontend-wipe-PASTE.md`
- Orca notes / WWDC inventory cited in the Plan — patterns only; MIT; no verbatim competitor code

## Standing rules (do not violate)

- No Siri **Approve** intent · no Face ID · no daemon edits on this track
- No phone reinstall without explicit owner ask
- Do not revert unrelated dirty git on main
- Prefer KEEP when unsure on non-UI engines — owner already wiped UI aggressively

## Suggested next steps (owner decides)

1. Commit wipe on `feat/frontend-scorched-wipe` if they want it durable
2. **Rebuild UI** in a new session (owner’s job) — hang new chrome on remaining engines/stores/intents; study Orca at `research-repos/orca` (MIT) + Plan Orca/Apple sections
3. Optionally restore W0.A dogfood from `checkpoint/w0a-dogfood-pre-scorched-wipe` / `stash@{0}` onto a rebuild branch

## Do NOT

- Re-run Wave 0 inventory as if wipe didn’t happen
- Implement a stub shell unless owner explicitly asks
- Touch `daemon/**`
- Whole-file `cp` across worktrees (diff/rebase only)
