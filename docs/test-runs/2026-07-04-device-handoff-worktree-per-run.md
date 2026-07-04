# Worktree-per-run — live device pass

Date: 2026-07-04  
Branch: `cursor/worktree-per-run-9257`

## Preconditions

- [ ] Daemon with worktree RPCs deployed on paired Mac host
- [ ] Real git repo on host (clean enough for `git worktree add`)
- [ ] Phone build from branch

## Test 1 — concurrent dispatches do not collide

1. Dispatch **two** agent runs into the **same repo/cwd** concurrently (both with worktree isolation if UI toggle exists, else via RPC/`useWorktree: true`).
2. **Expected**: each run uses distinct worktree path; no working-tree collision on host.

| Run A worktree path | Run B worktree path | Collision? | Pass/Fail |
|---------------------|---------------------|------------|-----------|

## Test 2 — non-worktree runs unaffected

1. Dispatch one normal run **without** worktree flag.
2. **Expected**: uses original cwd; behavior unchanged from pre-feature.

| Pass/Fail | Notes |
|-----------|-------|

## Test 3 — failed run retention

1. Trigger a run that fails (denied tool or explicit failure).
2. **Expected**: worktree **kept** on host; listable via `agent.worktree.list?managedOnly=true`.

| Pass/Fail | Worktree still on disk? | Notes |
|-----------|-------------------------|-------|

## Test 4 — UI isolation signal

1. During isolated run, check chat/run header on phone.
2. **Expected**: shows isolation indicator (e.g. `Isolated · <id>`).

| Pass/Fail | Notes |
|-----------|-------|

## Follow-ups (not blocking first merge)

- Composer UI toggle for `useWorktree` (RPC ready, UI may lag)
- Stale failed-worktree TTL / cleanup tooling

Owner sign-off: _______________
