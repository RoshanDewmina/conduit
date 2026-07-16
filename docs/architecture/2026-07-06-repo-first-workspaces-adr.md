# ADR: Repo-first Workspaces (vs. host-first)

> **Last updated: 2026-07-15.** Module paths naming `CursorShellLiveBridge` / CursorStyle below
> are **historical** (pre-`6b97da65`); the ADR decision (repo-first Workspaces) remains in force
> for the current `AppFeature/Workspaces/` production root. Do not treat CursorStyle types as
> present in the tree.

> Resolves `docs/product/FEATURE_BACKLOG.md` "Workspaces repo-first vs host-first".
> Scope when written: Tier 0/1 shell — Home/Away Digest stays frozen.

## 1. Context

Two disconnected "workspace" concepts exist in code today, both host-first:

- **`Workspace`/`WorkspaceRepository`** (`PersistenceKit/WorkspaceRepository.swift`) — a real
  persisted, **machine-owned** record (`Workspace.machineID` is the root key; `list()` only
  answers "workspaces on machine X"). Its only caller is the legacy, deprecated
  `NewChatTabView` composer's MRU path picker — not the Cursor shell.
- **`CursorShellLiveBridge.WorkspaceRow`** — not persisted at all. `AppRoot.refreshCursorLiveBridge`
  (`AppRoot.swift:1016-1032`) derives it every refresh by grouping `ChatConversationRepository
  .recent()` rows by `(cwd as NSString).lastPathComponent` — a bare string with **no machine
  scoping**. Two machines with a same-named checkout silently collide into one row, and there is
  no way to show "which machines can run this repo."

The approved wireframe (`03-workspaces.html`) and the Happier competitor pattern
(`.study/competitors/happier`, "persistent repository surfaces... launch a session into the exact
checkout context") both model the repo as the primary object: a repo row shows one status line
("hermes-box · checks passed") and drilling in reveals **Run targets** — the machines that can
execute this repo, each with its installed agents. `FleetStore.swift` (live SSH slot manager,
`Slot.hostID`) is unrelated to this decision — it manages live PTY sessions, not repo identity, and
is out of scope.

## 2. Decision

**Repo-first.** The repo is the durable, cross-machine identity; a machine is one of possibly
several *run targets* for that repo, not its owner. Adopt in two phases:

- **T1 (this lane, minimal, additive, no migration):** keep grouping by name (already true) but
  stop discarding `ChatConversation.hostID`/`hostName` when building rows — surface them as each
  repo's `runTargets`, matching the wireframe's status line and Workspace Detail "Run targets"
  list. No schema change; pure derivation from fields `ChatConversation` already has.
- **Phase 2 (not this lane):** a real `repos` table + `RepoRepository`, with `workspaces` rows
  reinterpreted as per-machine *checkouts* (`repo_id` FK) instead of root records, and repo identity
  resolved from git remote origin (needs a daemon RPC) with directory-basename as the offline
  fallback. Tracked as a follow-up, not specified further here (same phasing convention as
  master-plan §10).

## 3. What stays host-scoped

- `WorkspaceRepository`/`Workspace` keeps its current machine-owned shape and its one real caller
  (`NewChatTabView`'s composer MRU picker) — that view is legacy/deprecated UI, not touched here.
- `FleetStore` (`Slot.hostID`, live SSH session slots) is untouched — it is a connection/session
  manager, not a workspace identity store.
- E2E relay pairing (`CursorShellLiveBridge.onRequestPairing` / `E2ERelayPairingView`) is untouched.

## 4. T1 code-change plan (file list, no full Home migration)

1. `CursorShellLiveBridge.swift` — add `RunTarget { machineID, hostName }` and
   `WorkspaceRow.runTargets: [RunTarget]`; extend `ThreadRow` with `hostID`/`hostName` so the
   grouping step below has the data to aggregate.
2. `AppRoot.swift` (`refreshCursorLiveBridge`, ~1016-1032) — when grouping conversations by repo
   name, also collect the distinct `(hostID, hostName)` pairs per group and pass them through to
   `reloadWorkspaceThreads`/a new bridge setter, instead of dropping host info on the floor.
3. `CursorWorkspacesView.swift` — render the one-line meta under each repo row ("hermes-box ·
   checks passed" shape) from `runTargets`, instead of just a trailing thread count.
4. `CursorShellLiveBridgeTests.swift` — add coverage: two conversations, same repo name, different
   `hostID`s, aggregate into one row with two run targets (proves the collision case above is
   fixed, not just relabeled).

## 5. Done

`FEATURE_BACKLOG.md` §6 "Workspaces repo-first vs host-first" → **Decided**, pointing here. Phase 2
(persisted `repos` table, git-remote identity) stays **Open** as a separate, later item.
