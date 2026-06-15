# Dead Features Backlog

> Tracked list of features with finished-looking UI over non-functional or
> disconnected data paths. **List, do not hide** — each entry documents the gap
> so someone can fix it later. Audit date: 2026-06-15.

---

## 1. Scoped allow-always — iOS cosmetic only

**Gap:** The scope sheet collects repo/path/expiry choices but writes to
`UserDefaults["inbox.allowAlwaysRules"]` only — never sends to the daemon.
`buildPolicyYAML()` is complete dead code (zero callers). The daemon already
supports all scoped fields (`policy/types.go`) and `agent.policy.set` works.

| Layer | File | Lines |
|---|---|---|
| Scope sheet UI | `InboxFeature/AllowAlwaysScopeSheet.swift` | 1–418 |
| UserDefaults-only persist | `InboxFeature/InboxView.swift` `persistScopedAllowAlwaysRule` | 648–681 |
| Dead YAML builder | `InboxFeature/InboxView.swift` `buildPolicyYAML` | 683–726 |
| PolicyEditor reads local cache | `SettingsFeature/PolicyEditorView.swift` | 138–200 |
| Daemon rule model (ready) | `daemon/policy/types.go` | 43–60 |
| Daemon RPC (ready) | `daemon/conduitd/server.go` `agent.policy.set` | 527–563 |

**To fix:** Wire `buildPolicyYAML()` → `channel.sendRPC("agent.policy.set", yaml)`.
PolicyEditor reads `agent.policy.get` instead of UserDefaults.

---

## 2. Worktree / Branch Board — empty data source

**Gap:** Full 3-column kanban UI exists and is reachable from Fleet, but
`DaemonChannel.fetchWorktrees()` hardcodes `return []`. No `agent.worktree.*`
RPC exists on the daemon.

| Layer | File | Lines |
|---|---|---|
| Model | `ConduitCore/Worktree.swift` | 1–132 |
| Store | `AppFeature/WorktreeStore.swift` | 1–84 |
| 3-column board UI | `AppFeature/WorktreeBoardView.swift` | 1–291 |
| Empty stub | `SSHTransport/DaemonChannel.swift` `fetchWorktrees()` | 76–82 |
| Nav entry (live) | `AppFeature/FleetView.swift` | 154–160 |

**To fix:** Register `agent.worktree.list` in `daemon/conduitd/server.go` and
wire `fetchWorktrees()` to call it instead of returning `[]`.

---

## 3. CI / PR Integration — nonexistent RPC

**Gap:** iOS calls `agent.ci.recent` via JSON-RPC, but conduitd's `server.go`
switch has no handler for it — falls through to "method not found". The
push-backend `webhooks.go` has a real GitHub webhook receiver + in-memory CI
event store, but nothing bridges it to conduitd.

| Layer | File | Lines |
|---|---|---|
| iOS RPC call | `SSHTransport/DaemonChannel.swift` `recentCIEvents` | 327–344 |
| Caller (silently swallows error) | `AppFeature/FleetView.swift` `ciEventLoader` | 479–483 |
| CI section in loop detail (never renders) | `AppFeature/LoopDetailView.swift` | 6–120 |
| CI section in ProofCard (never renders) | `DesignSystem/ProofCardView.swift` | 21, 209–211, 411–458 |
| Push-backend webhook store (unbridged) | `daemon/push-backend/webhooks.go` | 64–120, 267–293 |

**To fix (a):** Register `agent.ci.recent` in conduitd that proxies
push-backend's `GET /webhooks/recent`. **Or (b):** push-backend pushes CI
events to conduitd over the control plane.

---

## 4. Blocked-state OS — gallery-only UI (partially fixed)

**Status:** LoopRepository decode path fixed this session (proper JSON
encoding/decoding of `BlockedReason`). SessionViewModel derives
`awaitingApproval` from pending approvals. Remaining gap: AgentStatusBar is
only in the gallery; production SessionView uses ChatHeaderView instead.

| Layer | File | Lines |
|---|---|---|
| BlockedReason model | `ConduitCore/BlockedReason.swift` | 1–53 |
| DSBlockedReasonRow UI | `DesignSystem/AgentState.swift` | 104–146 |
| AgentStatusBar UI | `SessionFeature/Chat/AgentStatusBar.swift` | 1–140 |
| Decode fix (done) | `PersistenceKit/LoopRepository.swift` decode | 139 |
| Production derivation (done) | `SessionFeature/SessionViewModel.swift` `blockedReason` | 142–148 |

**Remaining:** Wire AgentStatusBar into SessionView, or integrate
DSBlockedReasonRow into the existing ChatHeaderView.

---

## Fix priority

| # | Feature | Effort | Impact | Fix path |
|---|---|---|---|---|
| 1 | Scoped allow-always | Small | High — users who "allow always" with scope get a local illusion | Wire `buildPolicyYAML` → `agent.policy.set` |
| 2 | Worktree board | Small | Medium — board renders but shows empty | Add `agent.worktree.list` RPC |
| 3 | CI/PR integration | Medium | Medium — entire CI section hidden | Bridge push-backend → conduitd |
| 4 | Blocked-state OS | Small (remaining) | High — "why am I blocked?" was #1 research pain | Integrate DSBlockedReasonRow into SessionView |