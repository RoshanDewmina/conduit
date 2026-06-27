# Dead Features Backlog

> Tracked list of features with finished-looking UI over non-functional or
> disconnected data paths. **List, do not hide** — each entry documents the gap
> so someone can fix it later. Audit date: 2026-06-15.
> Updated: 2026-06-15 (opencode/phase-next — items 1, 2, 3, 4 fixed)

---

## 1. Scoped allow-always — ✅ FIXED

**Status:** `buildPolicyYAML()` is now wired to `agent.policy.set` RPC.
`InboxView` accepts an `onSetPolicy` closure; `AppRoot` passes
`bridgeSessionActions().savePolicyYAML` so scoped allow-always rules are sent
to the daemon (in addition to the local UserDefaults cache).

- `InboxView.swift`: added `onSetPolicy: ((String) async -> Void)?` parameter,
  called from the scope sheet completion handler after building YAML via
  `buildPolicyYAML()`
- `AppRoot.swift`: passes `actions.savePolicyYAML` as `onSetPolicy` to InboxView
- **PolicyEditorView** still reads UserDefaults (`inbox.allowAlwaysRules`). The
  daemon's `agent.policy.get` returns all *file-based* policy rules; the scoped
  rules written by `agent.policy.set` land in the daemon's in-memory policy
  store. The PolicyEditor reads UserDefaults (the local persist for convenience),
  but the daemon receives and enforces the real rules. A future enhancement could
  merge daemon-reported rules into PolicyEditor's display.

---

## 2. Worktree / Branch Board — ✅ FIXED

**Status:** The git-v1 merge added `agent.worktree.list` RPC on lancerd
(`daemon/lancerd/git.go`) and `DaemonChannel.listWorktrees()` on the iOS side.
`WorktreeStore.refresh()` calls it with per-host workdirs. `WorktreeBoardView`
now passes `workdirByHost` derived from connected fleet slots' `cwd`.

- `WorktreeBoardView.swift`: derives `workdirByHost` from `fleetStore.slots`
  where `sessionViewModel.status == .connected` and `cwd` is non-empty

---

## 3. CI / PR Integration — ✅ FIXED

**Status:** The git-v1 merge registered `agent.ci.recent` on lancerd
(`daemon/lancerd/server.go:914`). The handler proxies the push-backend's
`GET /webhooks/recent` endpoint. `DaemonChannel.recentCIEvents()` calls this
RPC. `FleetView.gitStore()` and `FleetView.ciEventLoader()` wire `GitStore`
and CI events into `LoopDetailView` with per-loop workdir/repo.

- `daemon/lancerd/git.go`: `recentCIEvents()` proxies push-backend webhook
  ring buffer. Gracefully degrades (returns `[]`) when no device/backend
  is registered.
- PR link in Proof Card and CI checks section in LoopDetailView will render
  when the daemon has real CI events to return.

---

## 4. Blocked-state OS — ✅ FIXED

**Status:** `ChatHeaderView` now accepts an optional `blockedReason: BlockedReason?`
parameter. When non-nil, a `DSBlockedReasonRow` is rendered below the header
HStack, showing the "why am I blocked?" explanation with severity-appropriate
styling.

- `ChatHeaderView.swift`: added `blockedReason` property, `init` parameter,
  and `DSBlockedReasonRow(reason)` below the header bar
- `SessionView.swift`: passes `vm.blockedReason` to `ChatHeaderView`
- `AgentStatusBar.swift` remains as the full-featured gallery component for
  the always-dark HUD strip scenario.

---

## Fix priority

All four items from the original audit are now fixed on `opencode/phase-next`.
The board below is retained for reference.

| # | Feature | Effort | Impact | Fix path |
|---|---|---|---|---|
| 1 | Scoped allow-always | Small | High | ✅ `buildPolicyYAML` → `agent.policy.set` (via `onSetPolicy` closure) |
| 2 | Worktree board | Small | Medium | ✅ `agent.worktree.list` RPC + `workdirByHost` from fleet slots |
| 3 | CI/PR integration | Medium | Medium | ✅ `agent.ci.recent` handler proxies push-backend |
| 4 | Blocked-state OS | Small | High | ✅ `DSBlockedReasonRow` integrated into `ChatHeaderView` |