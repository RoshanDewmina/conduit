# Git Support / Control for Conduit (iOS) — Research & Design

**Date:** 2026-06-15
**Author pass:** competitor survey (web, 2025–2026) + local scaffold audit
**Thesis anchor:** *supervision, not a mobile IDE.* Conduit's git surface exists to **review, approve, and ship the agent's work** from the phone — not to be a hand-editing git client. (Source: `~/Downloads/conduit-competitor-research-feature-backlog-2026-06-14.md`, §"Many developers are skeptical of mobile coding".)

---

## 0. Current reality (local audit — what's actually wired)

From `docs/audit/FEATURE_VERIFICATION_AUDIT.md` (#12, #13) and direct file reads:

| Asset | State | Evidence |
|---|---|---|
| `SSHTransport/GitClient.swift` | **Complete, ZERO callers.** Full git-over-SSH actor: `status`, `currentBranch`, `diff`, `log`, `listBranches`, `changedFiles`, `latestCommit`, `createBranch`, `checkout`, `stage`, `commit`, `push`, `createPullRequest` (via `gh`). Shell-quotes all inputs; captures exit code via sentinel marker. | `GitClient.swift:77-312` |
| `ConduitCore/Worktree.swift` | Model exists (`Worktree`/`ChangedFile`/`CommitInfo`), used only by gallery samples. | `Worktree.swift` |
| `AppFeature/WorktreeBoardView.swift` + `WorktreeStore.swift` | 3-column board renders, but `DaemonChannel.fetchWorktrees()` is a literal `return []`. **NO-OP.** | `WorktreeStore.swift:76-82` |
| `ConduitCore/CIEvent.swift` | Model exists. iOS calls RPC `agent.ci.recent` which **conduitd never registers** → swallowed `try?` → `[]`. Webhook receiver lives only in `daemon/push-backend/webhooks.go`, unbridged. **BROKEN.** | audit #13; `DaemonChannel.swift:327-330` |
| `DiffFeature/DiffView.swift` | **Works.** Renders `UnifiedDiff` (per-file sections, +/- summary, pinned headers) over `DiffKit`. | `DiffView.swift:5-32` |
| `SessionFeature/RecentPatch.swift` | Listens for `.approvalPending(kind:.patch)` events and forwards the unified-diff string to a sheet. **Works for patch approvals.** | `RecentPatch.swift:24-40` |

**Net:** the *client-side primitive* (`GitClient`) and the *diff renderer* (`DiffView`) are both real and unused. The gap is entirely **conduitd RPCs + one store that calls `GitClient`**. This is a wiring job, not a greenfield build.

---

## 1. Competitor capability matrix (2025–2026)

Legend: ● full · ◐ partial / via-agent · ○ none / N/A.

| Tool | Diff review | Stage / commit | Branch switch/create | Push / pull | PR create | PR review/merge | Checks status | Conflict resolution | Worktrees | Blame/history | Positioning |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Working Copy** (benchmark iOS git client) | ● | ● | ● | ● | ● (open PR) | ◐ (open, limited) | ○ | ◐ (manual merge) | ○ | ● | Full manual git client on-device |
| **GitHub Mobile** | ● (files-changed, inline comments, mark-viewed) | ○ (no working tree) | ◐ (create PR from existing branch) | ○ | ● (from branch) | ● (review + merge + re-request) | ● (checks; can't approve workflow runs) | ○ | ○ | ● | PR review & triage, not a working client |
| **CC Pocket** (self-hosted bridge) | ● (unified + image diff; hunk→chat) | ● (stage, commit, push, revert) | ◐ | ● | ○ | ○ | ○ | ○ | ○ | ◐ | Self-hosted phone control of Claude/Codex with git ops |
| **Omnara** | ● (per-agent diffs in dashboard) | ◐ (agent-driven) | ◐ | ◐ | ● (auto-open PR after session) | ◐ (handoff for review) | ○ | ○ | ● (parallel agents per worktree) | ○ | Command center for agents; worktree+PR handoff |
| **Cline Kanban** (local web, mobile-responsive) | ● (visualize git) | ● (commit) | ● (switch/fetch/pull/push) | ● | ● (open PR) | ○ | ○ | ○ | ● (isolated worktree per card) | ● | Multi-agent orchestration board |
| **Cursor (cloud/remote agents)** | ● (review diffs, approve) | ◐ (agent) | ◐ (worktree per agent) | ◐ | ● (merge-ready PRs) | ◐ | ◐ | ○ | ● (≤8 parallel) | ○ | Control agents from any device; mobile = approve/review only |
| **Termius** | ○ (SSH terminal only) | ◐ (raw git in shell) | ◐ (raw) | ◐ (raw) | ◐ (raw `gh`) | ○ | ○ | ◐ (raw) | ◐ (raw) | ◐ (raw) | SSH/Mosh client; git only via terminal |
| **opencode mobile** | ◐ (review) | ◐ (agent) | ◐ | ◐ | ● (auto PR review on open) | ◐ | ◐ | ○ | ◐ | ○ | Mobile opencode client |
| **GitKraken / Tower** | ● (desktop) | ● | ● | ● | ● | ● | ◐ | ● (Kraken conflict UI) | ◐ | ● | **Desktop only — no iOS app** (Tower is Mac/Win; GitKraken Mac/Win/Linux) |

**Reading of the field:**
1. **No one ships a full manual mobile git working-client except Working Copy** — and Working Copy is explicitly not an agent tool. The market has *not* validated "edit + resolve conflicts on a 6-inch screen."
2. **The convergent agent-era pattern is: review the agent's diff → ship it (commit / open PR) → watch checks.** Omnara, Cursor, Cline, opencode all auto-open PRs after an agent session; GitHub Mobile owns the PR-review/merge/checks half. CC Pocket proves self-hosted *stage/commit/push from phone* is desirable and feasible over a bridge.
3. **Worktree-per-agent is now table stakes for parallel-agent products** (Omnara, Cline, Cursor) — but as a *supervision board* ("which agent owns which branch + its diff"), not a manual `git worktree add` UI.
4. **Conflict resolution and blame/history are desktop-client features** (GitKraken/Tower) that no agent-supervision product bothers with on mobile.

---

## 2. What Conduit should offer (framed by "supervision, not IDE")

Conduit's git is the **review-and-ship tail of an agent loop**: the agent did the work on the host; the phone's job is *see what changed → judge it → ship it → confirm CI is green.* Everything that fights that (manual editing, conflict UIs, blame browsing) is explicitly out.

### Must-have (v1) — minimum to review + ship agent work — **≤5 items**

1. **Changed-files + unified diff per run/loop.** The agent's diff, rendered in the existing `DiffView`. The single most-validated mobile-agent capability (every competitor has it). Reuse `GitClient.diff()` / `changedFiles()` → `DiffView`.
2. **The agent's branch & git status, surfaced on the run/loop.** Branch name, ahead/behind, dirty/clean — so the user knows *what* they're about to ship and *where*. Reuse `GitClient.status()` / `currentBranch()`.
3. **One-tap "Ship it": commit + push + open PR of the agent's work.** The decisive supervision action. Reuse `GitClient.stage()` → `commit()` → `push()` → `createPullRequest()` (`gh`). Gated by an approval-style confirmation sheet showing the diff summary.
4. **PR status + checks on the run/loop & Proof Card.** "PR #123 · checks passing/failing" with a tap-through link. Reuse `CIEvent` model; needs the CI bridge wired (see §3).
5. **PR link in the Proof Card.** Closes the loop: the run's terminal artifact is a reviewable PR. Already a field on `ProofCardModel` per audit #7; just needs a real value.

> These five map cleanly onto the existing **Inbox → review → approve** muscle: a "ship the agent's branch" action is structurally a patch-style approval (`RecentPatch` already routes `.patch` approvals to a diff sheet).

### Should-have (v1.5)

- **Branch switch / create on the host** (`GitClient.checkout` / `createBranch`) — for "start the agent on a fresh branch" or redirect.
- **Worktree board that actually works** — wire `fetchWorktrees()` to a real `agent.worktree.list` RPC so the existing 3-column board shows *which agent/loop owns which branch + its changed files*. Supervision board, not a worktree manager.
- **Stage / partial (per-hunk) commit** — CC Pocket's "hunk → chat" and selective staging; lets the user ship *part* of the agent's work. Reuse `GitClient.stage(paths:)`; per-hunk needs `git apply --cached` plumbing.
- **PR review comments + merge from Conduit** — either deep-link to GitHub Mobile (cheap) or proxy `gh pr review` / `gh pr merge` (richer, more auth surface).

### Later / avoid (fights the thesis)

- **Full manual file editing on-device.** The core skepticism; cede to nobody.
- **Conflict-resolution UI.** Desktop-client territory (GitKraken/Tower); if the agent's merge conflicts, the right move is *nudge the agent to resolve it on the host*, not a 3-way merge on a phone.
- **Blame / history browsing.** A code-archaeology feature, not a supervision one. `git log` already exists in `GitClient.log()` if a thin "recent commits" peek is ever wanted, but don't build a history browser.
- **Generic git-client features** (stash manager, cherry-pick, rebase UI, tag management, submodules). All fight "supervision, not IDE."

---

## 3. Simplest coherent design

### 3.1 Where git lives in the existing model

Git is **not a new top-level tab.** It attaches to the units the user already supervises:

```
Loop / Run (Fleet, Inbox, Activity)
   └─ "Changes" section
        ├─ branch chip + ahead/behind  (GitStatus)
        ├─ N files changed             (GitClient.changedFiles → DiffView)
        ├─ [Review diff]  → DiffView (reuse, unchanged)
        └─ [Ship it ▸]    → confirmation sheet → commit+push+PR
   └─ Proof Card (terminal state)
        ├─ diff summary (+adds / −dels / files)
        ├─ PR #123 ▸ (link)
        └─ checks: ● passing / ✕ failing   (CIEvent)

Fleet ▸ Worktree Board (v1.5)
   └─ columns: Active / Completed / Idle  (already built)
        └─ each card: repo · branch · agent · changed files · last commit
            (now fed by real agent.worktree.list)
```

**Flow (v1 happy path):** agent finishes a run → run shows "12 files changed on `feat/x`" → user taps **Review diff** (`DiffView`) → taps **Ship it** → confirmation sheet (diff summary + commit message prefilled from run goal) → conduitd runs commit+push+`gh pr create` on the host → Proof Card updates with PR link + checks. This is the *same approve-from-phone gesture* the product already centers on, applied to "ship the branch."

### 3.2 Reuse vs build

**Reuse as-is (no new code):**
- `GitClient.swift` — every needed primitive already exists. **Just needs callers.**
- `DiffView` / `DiffKit` / `UnifiedDiff` — diff rendering done.
- `RecentPatch` — patch→diff-sheet routing done; the "ship" confirmation can reuse the same sheet pattern.
- `Worktree` / `CIEvent` / `ProofCardModel` — models done.
- `WorktreeBoardView` — UI done.

**Build (the missing wiring):**

| Layer | What to add | Notes |
|---|---|---|
| **conduitd RPCs** | `agent.git.status` (→ `GitStatus`), `agent.git.diff` (path?/staged? → unified diff string), `agent.git.changedFiles`, `agent.git.ship` (stage+commit+push+`gh pr create`, returns PR URL), `agent.worktree.list` (→ `[Worktree]`), `agent.ci.recent` (the one iOS already calls but conduitd never registers) | All follow the existing `sendRPC(method:params:)` JSON-RPC pattern (`DaemonChannel.swift:73`). conduitd executes git on the host (it already shells out for hooks/dispatch). Conduitd *could* even reuse the same git invocations `GitClient` uses. |
| **CI bridge** | Bridge `push-backend/webhooks.go` ring buffer → conduitd, so `agent.ci.recent` returns real `CIEvent`s. Either conduitd proxies push-backend, or push-backend pushes events to conduitd. | audit #13 names both options. |
| **iOS store** | A `GitStore` (mirror of `WorktreeStore`) that calls the new RPCs and feeds the Loop/Run "Changes" section. Replace `fetchWorktrees()`'s `return []` with a real `agent.worktree.list` call. | `WorktreeStore.refresh()` already iterates connected slots — only `fetchWorktrees()` is hollow. |
| **iOS UI glue** | A "Changes" section on the run/loop detail + a "Ship it" confirmation sheet (reuse approval-sheet styling). Wire PR link + checks into `ProofCardModel`. | No new rendering primitives needed. |

**Decision: client-side `GitClient` over SSH, OR conduitd-side git RPCs?**
The architecture says git runs *on the host via conduitd* (phone = control surface). Two viable paths:
- **(A) conduitd owns git** (recommended): add `agent.git.*` / `agent.worktree.*` RPCs; conduitd runs git/`gh` on the host. Keeps a single host-side chokepoint (consistent with policy/audit/approvals), works through the relay, and `GitClient`'s shell-quoting + porcelain parsers can be **ported into the Go daemon** (or conduitd shells the same commands). `GitClient` then becomes a fallback/local-SSH path.
- **(B) iOS `GitClient` over the SSH command channel** (already built): zero daemon work — the app runs git directly over SSH. Faster to ship a demo, but bypasses conduitd governance (no audit/policy on git ops) and won't work over the pure-relay path where there's no raw SSH command channel.

**Recommendation:** ship v1 read paths (status/diff/changedFiles) via **(A) conduitd RPCs** for governance consistency, and treat the existing `GitClient` as the proven reference implementation to port / as a direct-SSH fallback. The **write path ("Ship it")** *must* go through conduitd so it lands in the tamper-evident audit log and can be policy-gated.

### 3.3 Conduitd RPC sketch (matches existing envelope)

```
// status
→ {"method":"agent.git.status","params":{"workdir":"/repo"}}
← {"branch":"feat/x","upstream":"origin/feat/x","ahead":2,"behind":0,
   "changes":[{"path":"a.ts","code":" M","staged":false}, ...]}

// diff (unified text → DiffKit.UnifiedDiff on device)
→ {"method":"agent.git.diff","params":{"workdir":"/repo","staged":false}}
← {"diff":"diff --git a/... \n@@ ..."}

// ship (the v1 write action — audited, policy-gated)
→ {"method":"agent.git.ship","params":{"workdir":"/repo","message":"feat: ...",
     "openPR":true,"base":"main","title":"...","body":"..."}}
← {"committed":true,"pushed":true,"prURL":"https://github.com/o/r/pull/123"}

// worktree board (v1.5)
→ {"method":"agent.worktree.list","params":{}}
← {"worktrees":[{ Worktree JSON }]}

// CI (already called by iOS; register it on conduitd + bridge push-backend)
→ {"method":"agent.ci.recent","params":{"repo":"o/r","limit":50}}
← {"events":[{ CIEvent JSON }]}
```

---

## 4. Effort / risk + open questions

**Effort (rough):**
- **v1 read (status/diff/changedFiles + UI section):** Low. `GitClient` + `DiffView` exist; ~2 RPCs + a store + a detail section.
- **v1 "Ship it" write:** Low–Medium. One RPC orchestrating commit+push+`gh pr create`; the risk is auth (below) and a good confirmation UX.
- **CI bridge (`agent.ci.recent`):** Medium. Cross-process plumbing (push-backend → conduitd) is the real work; the iOS side already calls it.
- **Worktree board real data:** Low. UI built; one RPC + replace `return []`.
- **Per-hunk staging (v1.5):** Medium. `git apply --cached` of selected hunks is fiddly.

**Risks & open questions:**

1. **PR-creation auth.** `gh pr create` needs `gh` authenticated on the host (audit #2 found *"agent-auth error: No API keys found"* on the live VPS — so `gh` is likely **not** authenticated today). Options: (a) require `gh auth login` on the host as a `conduit doctor` check; (b) route a GitHub token through the **Secrets Broker** (`agent.secret.*`, already built per audit #11) and export `GH_TOKEN` for the `gh` call — keeps the token off the phone and inside conduitd's governance. **Recommend (b) + a doctor check.** Open: per-repo vs per-host token scoping.
2. **Large-diff scaling.** `GitClient.diff()` returns the *entire* unified diff as one string over the channel; a big agent change (or a generated lockfile) can be megabytes. Need: per-file lazy diff (`diff(path:)` already supports it), a size cap with "diff too large — open on host / PR" fallback, and binary-file elision. `DiffView` is `LazyVStack`-based so rendering scales, but transport doesn't.
3. **Monorepo / worktree edge cases.** `workdir` must be the *agent's actual worktree path*, not the repo root — the `Worktree.path` field carries this, but the Loop/Run → workdir mapping must be reliable (ties into audit #6's "Loop needs a producer"). Detached HEAD, multiple worktrees of one repo, and submodules need graceful degradation (status already handles detached `HEAD`).
4. **"Ship" idempotency & partial failure.** commit-ok-but-push-fails, or push-ok-but-`gh`-fails, must surface a precise state (not a generic error) and be safely retryable — mirror the approval-decision idempotency the research backlog already calls for. `GitClient` returns `GitCommandError` with combined stdout/stderr, which helps.
5. **Conflict / dirty-tree on ship.** If the base moved, push is rejected. v1 should *not* auto-rebase; it should report "branch is behind / push rejected — nudge the agent to rebase on the host." (Reinforces "no conflict UI on phone.")
6. **Audit/policy coverage of git writes.** A phone-triggered push/PR is a privileged action; it must land in the hash-chained audit log and ideally be policy-evaluable (e.g., "allow PR to non-main only"). This is the main argument for path (A) over the direct-SSH `GitClient`.

---

## 5. Summary

**Recommended v1 must-have set (≤5):**
1. Changed-files + unified diff per run/loop (reuse `GitClient.diff/changedFiles` → `DiffView`).
2. Agent's branch + git status on the run/loop (reuse `GitClient.status/currentBranch`).
3. One-tap **Ship it** = commit + push + open PR (reuse `GitClient.stage/commit/push/createPullRequest`, via conduitd).
4. PR status + checks on run/loop & Proof Card (reuse `CIEvent`; wire the CI bridge).
5. PR link in the Proof Card.

**Reuse vs build:** The hard parts are already built and unused — `GitClient` (every git primitive, shell-safe), `DiffView`/`DiffKit`, `RecentPatch`, and the `Worktree`/`CIEvent`/`ProofCardModel` models, plus the finished `WorktreeBoardView`. **The entire gap is wiring:** ~5 conduitd RPCs (`agent.git.status/diff/changedFiles/ship`, `agent.worktree.list`, plus registering the already-called `agent.ci.recent`), bridging push-backend CI → conduitd, a `GitStore` that calls them, and a "Changes" section + "Ship it" sheet on the run detail. Write paths go through conduitd for audit/policy coverage; the existing `GitClient` is the reference impl and a direct-SSH fallback. Avoid manual editing, conflict UIs, and blame/history — they fight the "supervision, not IDE" thesis.

**Doc path:** `docs/audit/GIT_SUPPORT_RESEARCH.md`

---

## Sources

- Working Copy (iOS git client): https://apps.apple.com/us/app/git-client-working-copy/id896694807 · https://workingcopyapp.com/users-guide
- GitHub Mobile — PR review/create/merge, checks: https://github.blog/changelog/2025-02-28-mobile-monthly-februarys-general-availability-and-more/ · https://github.blog/changelog/2025-01-21-create-pull-request-from-an-existing-branch-on-github-mobile/ · https://github.blog/changelog/2025-07-08-copilot-code-review-now-generally-available-on-github-mobile/ · https://github.blog/changelog/2026-04-08-github-mobile-research-and-code-with-copilot-cloud-agent-anywhere/ · https://github.com/orgs/community/discussions/110751
- CC Pocket (self-hosted bridge, diff/stage/commit/push, hunk→chat): https://github.com/K9i-0/ccpocket · https://k9i-0.github.io/ccpocket/install/ · https://zenn.dev/k9i/articles/20260304_ccpocket?locale=en
- Omnara (worktrees, auto-PR after session, handoff): https://github.com/omnara-ai/omnara · https://www.omnara.com/ · https://www.fondo.com/blog/omnara-launches
- Cline Kanban (isolated worktree per card, commit/open PR, branch ops, mobile-responsive): https://github.com/cline/kanban · https://docs.cline.bot/usage/kanban · https://cline.ghost.io/announcing-kanban/
- Cursor (cloud/remote agents, worktrees, merge-ready PRs, mobile = approve/review): https://www.buildfastwithai.com/blogs/cursor-remote-agents-any-device-2026 · https://beginnersinai.org/cursor-review/
- Termius (SSH/Mosh mobile terminal — git only via shell): https://docs.termius.com/terminal/mobile-terminal · https://termius.com/index.html
- opencode (mobile + PR review on open): https://opencode.ai/docs/github/ · https://hubtool.ai/opencode
- GitKraken / Tower (desktop-only; no iOS): https://www.git-tower.com/blog/history-of-ios · https://www.softwaresuggest.com/gitkraken-client
- `gh` headless auth (`GH_TOKEN` / `gh auth login --with-token`): https://cli.github.com/manual/gh_auth_login · https://josh-ops.com/posts/gh-auth-login-in-actions/
- Conduit thesis & backlog: `~/Downloads/conduit-competitor-research-feature-backlog-2026-06-14.md`
- Conduit current-state audit: `docs/audit/FEATURE_VERIFICATION_AUDIT.md`
