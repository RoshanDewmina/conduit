# Git Worktrees + Mobile Agent Control: Research Report

**Date:** 2026-06-16  
**Context:** Lancer iOS app — remote control for AI coding agents (Claude Code, Codex CLI, Gemini CLI) running on user's own host via SSH/E2EE relay. Phone screen: 402pt wide. 3-tab IA: Fleet, Inbox, Settings.

---

## Executive Summary

Git worktrees are the consensus isolation primitive for running multiple AI coding agents on one repo. Every major tool in the 2025-2026 parallel-agent ecosystem — Conductor, Nimbalyst/Crystal, Vibe Kanban, Claude Squad, Omnara, Claude Code itself (`--worktree` flag) — uses worktrees as the "one worktree per agent per branch" pattern. The phone presents a hard design constraint: you cannot replicate a desktop orchestrator's terminal panes, file trees, or side-by-side diffs at 402pt. The fit is instead governance-first: Lancer's existing Fleet tab maps naturally to a worktree/agent list, and the Inbox is the right place to surface per-agent diffs + approval requests + merge-back confirmation. V1 should expose exactly four git operations: (1) create worktree/agent, (2) review diff, (3) approve+merge, (4) clean up. Everything else (interactive rebase, cherry-pick, stash management, granular staging) is YAGNI on a phone. The single biggest UX risk is accidental merge of un-reviewed agent output into a protected branch — solve with a mandatory Face-ID gate on merge-back and a diff-summary confirmation screen that forces the user to see what changed.

---

## 1. Git Worktrees — The Mechanism

### 1.1 The Problem They Solve

`git worktree` (shipped in Git 2.5, July 2015) lets you check out multiple branches of one repo into *separate directories simultaneously*, sharing a single `.git` object store. Each worktree has its own working directory, its own index, and its own branch checkout — but all share commits, refs, and config.

**Why worktrees win for parallel agents, vs. alternatives:**

| Approach | Speed | Disk space | Shares .git | Branch isolation | Agent-safe? |
|---|---|---|---|---|---|
| Branch-in-place (stash/switch) | Fast | None | Yes | No — files change on disk mid-agent | ❌ |
| Full repo clone | Slow | Full copy per clone | No | Yes | ✅ but wasteful |
| Container (Docker) | Medium | Image + FS layers | No | Yes | ✅ but heavy |
| **Git worktree** | **Instant** | **Working files only** | **Yes** | **Yes — directory-level** | **✅** |

**Core constraint:** A branch can only be checked out in one worktree at a time — Git enforces this at the ref level. This means each agent *must* get its own branch.

Sources:
- [gitworktree.org — complete guide](https://www.gitworktree.org/)
- [Git Worktree vs Clone comparison](https://www.gitworktree.org/compare/worktree-vs-clone)
- [DevToolbox — worktree parallel development](https://www.dev-toolbox.tech/tools/git-cheat-sheet/examples/git-worktree-parallel)

### 1.2 Concrete Lifecycle

```
# Create (with new branch)
git worktree add -b feature/add-auth ../myapp-feat-auth  main

# Create (existing branch)
git worktree add ../hotfix  hotfix/login-bug

# List
git worktree list
# → /Users/me/project          abc1234 [main]
# → /Users/me/project-hotfix   def5678 [hotfix/login-bug]

# Lock (GC protection)
git worktree lock ../hotfix

# Prune (clean stale metadata after manual directory deletion)
git worktree prune

# Remove
git worktree remove ../hotfix
# Force remove (uncommitted changes):
git worktree remove --force ../hotfix
```

### 1.3 Gotchas at Scale

- **Shared `.git`:** The main repo's `.git` directory contains absolute paths to each linked worktree. Moving the main repo breaks all worktrees — requires `git worktree repair`.
- **Hooks are shared:** Post-checkout hooks in `.git/hooks/` run in every worktree. Useful for auto-init submodules, but can surprise.
- **Dependencies duplicated per worktree:** `node_modules/`, `vendor/`, `target/`, `.build/` are *not* shared — each worktree has its own copy. This is the #1 disk-space trap. Mitigation: pnpm's content-addressable store (hard links), cargo's shared cache, or symlink strategies.
- **Submodules:** Worktrees require `git submodule update --init --recursive` *per worktree*. Submodule state is per-worktree. Removing a worktree with submodules requires `--force`. (Source: [gitworktree.org submodule guide](https://www.gitworktree.org/guides/submodules))
- **LFS:** LFS pointer files are checked out, but actual LFS content must be fetched per-worktree via `git lfs pull`. (Source: [gitworktree.org LFS guide](https://www.gitworktree.org/guides/large-repos))
- **GC:** `git gc` in any worktree is visible to all — safe but can surprise.
- **Disk space math:** For a project with 2GB `node_modules`, 5 worktrees = 10GB of dependency duplicates (40GB without pnpm/cargo). With pnpm's store, ~2.25GB for 3 worktrees. (Source: [GitCheatSheet — disk space management](https://gitcheatsheet.dev/docs/advanced/worktrees/disk-space-management/))

### 1.4 Agent Loop Integration

The canonical pattern across all tools surveyed:

```
1. Task arrives         → lancerd creates branch + worktree
2. Agent starts         → launched in that worktree directory
3. Agent works          → edits files, commits locally (auto-commit per iteration)
4. Agent finishes/needs input → lancerd reads worktree state
5. User reviews diff    → via Lancer phone UI (unified diff)
6. User approves merge  → lancerd merges to main / pushes PR
7. Cleanup              → lancerd removes worktree + deletes branch
```

Source: [Parallel AI Agents architecture](https://www.gitworktree.org/ai-tools/parallel-agents)

---

## 2. Who Uses Worktrees for Agents (Verified)

### 2.1 Conductor (conductor.build)

**Status:** Active, funded ($2.8M seed → $22M). macOS app.  
**Mechanism:** Each "workspace" = one `git worktree` on its own branch. Click "New Workspace" → auto creates worktree, starts Claude Code/Codex inside it.  
**Diff/merge:** Built-in diff viewer, one-click merge to main.  
**Cleanup:** Worktree removed on workspace close.  
**Naming scheme:** Auto-generated branch per workspace. Integration with Linear issues.  
**Used by:** Engineers at Linear, Vercel, Ramp, Notion, Stripe.  
**Notable:** 250% MoM growth. No mobile companion app — desktop only.  
Sources: [conductor.build](https://www.conductor.build/), [CodePick guide](https://codepick.dev/en/guides/conductor-build-intro/), [agentsroom.dev comparison](https://agentsroom.dev/compare)

### 2.2 Crystal (stravu/crystal) → Nimbalyst

**Status:** Crystal deprecated Feb 2026 (final v0.3.5). Superseded by Nimbalyst (MIT, active).  
**Mechanism:** Same — `git worktree add -b <branch> ../<worktree-dir>` per session. Run Claude Code or Codex in each worktree.  
**Diff/merge:** Built-in diff viewer, squash+rebase UI, then merge to main.  
**Cleanup:** Remove worktree on session close.  
**Naming scheme:** Auto-generated session branch names.  
**Notable:** 3.1k GitHub stars on Crystal repo. Nimbalyst continues with cross-platform support.  
Sources: [GitHub stravu/crystal](https://github.com/stravu/crystal), [Ry Walker research](https://rywalker.com/research/crystal), [Nimbalyst comparison](https://nimbalyst.com/blog/best-git-worktree-tools-ai-coding-2026)

### 2.3 cmux (manaflow-ai/cmux)

**Status:** Active, YC S24, 21.6k GitHub stars. macOS-only (Ghostty-based).  
**Mechanism:** Not a worktree *manager* per se — a terminal *multiplexer* designed for running many agent panes. Users create worktrees manually or via shell scripts. cmux provides "notification rings" (blue ring on panes needing input) and vertical tab sidebar showing git branch, working dir, ports.  
**Notable:** Claude Code Teams integration via tmux shim. No built-in diff viewer — relies on agent CLI output.  
**Worktree handling:** User-managed. cmux surfaces worktree info in sidebar but doesn't auto-create/remove.  
Sources: [cmux.com docs](https://cmux.com/docs/getting-started), [oflight.co deep dive](https://www.oflight.co.jp/en/columns/cmux-manaflow-ai-agent-terminal-2026), [DEV review](https://dev.to/arshtechpro/cmux-the-native-macos-terminal-built-for-running-ai-coding-agents-in-parallel-52il)

### 2.4 Vibe Kanban (BloopAI/vibe-kanban)

**Status:** Active, open source.  
**Mechanism:** Kanban board (To Do → In Progress → Review → Done). Drag a card to "In Progress" → auto-creates branch `vk/<hash>-<slug>`, spins up worktree, launches agent. Real-time WebSocket logs.  
**Diff/merge:** Card lands in "Review" column with diff viewer. Line comments send back to agent.  
**Cleanup:** Card to "Done" → worktree removed.  
**Notable:** `npx vibe-kanban` — runs locally, opens browser. Agents as parallel workers, not chatbots.  
Sources: [vibekanban.online](https://vibekanban.online/), [virtuslab blog - deep architecture dive](https://virtuslab.com/blog/ai/vibe-kanban/)

### 2.5 Omnara

**Status:** Active, YC S25, 10k+ installs on mobile. iOS + Android + Web + Watch.  
**Mechanism:** CLI wrapper runs on host, relays agent output to cloud. Mobile app shows diffs, logs, approval requests. Sessions can migrate to cloud if laptop goes offline. Voice input/output.  
**Worktree handling:** "Sessions run in worktree-isolated environments" per their docs. Diffs are mobile-optimized with "rich diff visualization."  
**Pricing:** Free tier (10 sessions/mo), $9/mo unlimited.  
**Notable:** Direct competitor to Lancer's phone-control concept. The "cloud migration" feature (session survives laptop sleep) is a differentiator — Lancer's SSH/E2EE approach avoids the privacy tradeoff of cloud relay.  
Sources: [omnara.com](https://www.omnara.com/), [Omnara mobile diff review docs](https://omnaradocs.com/task/blog/mobile-app-review-git-diffs-autonomous-coding-agents), [revuo.ai review](https://www.revuo.ai/category/coding-agent-remotes/omnara)

### 2.6 Claude Code Native (`--worktree` flag)

Claude Code v2.1+ (Jan 2026) ships a `--worktree [name]` flag that auto-creates a worktree for isolated execution. Source: [Arantic docs on Claude Code CLI flags](https://docs.arantic.com/claude-code/flags). Also supports `--tmux` (tmux session for the worktree) and `--bg` (background agent). This is the clearest signal that Anthropic considers worktrees the standard isolation primitive.

### 2.7 Worktrunk

CLI-only (Rust). `wt switch feat` to switch worktrees by branch name. Hooks for create/merge/remove. LLM commit messages. `wt list --full` shows CI status and AI-generated summaries per branch. Designed specifically for parallel agent workflows. Sources: [worktrunk.dev](https://worktrunk.dev/)

### 2.8 Other notable

- **grove** (captainsafia/grove) — CLI for worktree-based workflows. Author's thesis: "use worktree in place of branches."
- **Claude Squad** — Terminal-based orchestrator, uses worktrees for per-agent isolation.
- **DIY scripts** — Numerous blog posts showing the same pattern (e.g., 371 worktrees anecdote, Nx blog, MindStudio guide).

### 2.9 The Emerging "Fan-Out, Review, Merge Winner" Pattern

The consistent UX pattern across all tools:

```
                    ┌─────────────────────┐
                    │   User defines task   │
                    │   (problem statement) │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
     ┌────────▼───┐   ┌───────▼────┐   ┌───────▼────┐
     │ Worktree 1  │   │ Worktree 2 │   │ Worktree 3 │
     │ Agent A     │   │ Agent B    │   │ Agent C    │
     │ (approach 1)│   │(approach 2)│   │(approach 3)│
     └────────┬───┘   └───────┬────┘   └───────┬────┘
              │                │                │
     ┌────────▼────────────────▼────────────────▼───────┐
     │              Review all diffs                     │
     │   (side-by-side or sequential unified diffs)      │
     └───────────────────────┬───────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │ Merge winner OR │
                    │ cherry-pick     │
                    │ from multiple   │
                    └─────────────────┘
```

This is explicit in Conductor's "compare agent outputs" and Vibe Kanban's review column. It is *implicit* in worktree-based workflows: worktrees make it trivial to discard a failed approach (just remove the worktree).

Sources: [agentmaxxing guide](https://vibecoding.app/blog/agentmaxxing), [Nimbalyst comparison](https://nimbalyst.com/blog/best-git-worktree-tools-ai-coding-2026), [DEV — parallel worktree agents](https://dev.to/battyterm/how-to-use-git-worktrees-to-run-multiple-ai-agents-on-the-same-repo-1on8)

---

## 3. Adapting Git to a Mobile Touch Screen

### 3.1 Survey of Existing Mobile Git Clients

#### Working Copy (iOS) — The Benchmark

Working Copy is the most mature iOS git client (3.6K ratings, 4.9★). Key design choices:

- **Repository-first navigation:** List view of repos → drill into file tree → file detail with diff overlay. Not branch-first.
- **Diff viewer:** Unified (not split). Syntax-highlighted per-file diffs. Tap line numbers to stage/unstage. Horizontal scrolling for long lines.
- **Branch management:** List branches from repo detail view. Create/switch/merge/delete. No visual branch graph on iPhone (iPad has one).
- **Merge conflicts:** Dedicated "resolve" tool — shows conflict markers, tap to pick one side or edit inline.
- **Staging:** Granular — select individual lines or hunks. Not a primary phone workflow.
- **What's painful:** File tree navigation at 402pt is cramped. Commit message entry without keyboard shortcuts. No worktree awareness at all. No multi-repo overview.

Sources: [Working Copy app store](https://apps.apple.com/us/app/git-client-working-copy/id896694807), [Working Copy users guide](https://workingcopyapp.com/users-guide), [Appshunter reviews](https://appshunter.io/ios/app/896694807)

#### GitHub Mobile

- PR review is the #1 use case. Unified diff with line comments. Squash/merge/rebase buttons.
- **No git operations** (no local commit, no branch create/switch, no worktree).
- Designed as a remote-control for GitHub.com, not a local git client.
- 2025 update: Copilot agent sessions viewable from mobile.
- Source: [GitHub Mobile changelog 2025-09](https://github.blog/changelog/2025-09-14-github-mobile-now-supports-ios-26-with-refined-visuals-and-smoother-navigation/)

#### Other clients (GitKraken, Tower, Pocket Git)

- GitKraken: No mobile app.
- Tower: No mobile app.
- Pocket Git: Minimal — commit, push, pull, branch switch. No diff review. No worktree support.

### 3.2 What Belongs on a Phone vs. What Doesn't

**Yes, on phone (Lancer v1 scope):**

| Operation | Why on phone | Pattern |
|---|---|---|
| Create worktree + agent | Core loop: user sees a task, dispatches an agent | Tap "New Agent" → branch name + prompt → lancerd creates worktree + launches agent |
| Review diff | The #1 mobile activity after "is it done?" | Unified diff, per-file scroll, tap lines to expand |
| Approve + merge | Governance gate | Face ID + "Merge to main" confirmation |
| Clean up worktree | Post-merge hygiene | Auto-delete worktree after merge (with undo window) |
| List active worktrees/agents | Visibility into what's running | Fleet tab shows cards (one per worktree/agent) |
| View agent status | Running / waiting approval / done / error | Card shows status badge, branch name, last action |
| View per-agent inbox | Approval requests, error notifications | Consolidated in Inbox tab |

**Maybe, v2 or v3:**

| Operation | Rationale |
|---|---|
| Compare diffs across agents | High value for "fan-out, pick winner" workflow. Hard UI — needs side-by-side or multi-tab diffs at 402pt. Consider swipe-between-agents. |
| Manual branch create (no agent) | Low frequency. Settings > Advanced. |
| Conflict resolution | Rare but high-value. Working Copy proves it's possible on iOS. Delegate to v2. |
| Commit message editing | Agent auto-commits. Manual message editing is edge case. |
| Push to remote | Useful but not core to agent workflow. Agent typically creates local commits; lancerd can push automatically on merge. |

**No, YAGNI on phone (desktop/terminal only):**

| Operation | Why not |
|---|---|
| Interactive rebase | Too complex for touch. No good visual model at small screen. |
| Cherry-pick | Power-user operation. Frequency too low. |
| Stash management | Worktrees eliminate most stash need. |
| Granular staging (per-line) | Too fine-grained for 402pt touch targets. |
| Git blame | Text-heavy, wide-table operation. |
| Submodule management | Worktrees + submodules already complex on desktop. |
| `git gc`, `git fsck` | Maintenance operations. lancerd handles silently. |
| Reflog exploration | Debug-only. |

### 3.3 Mobile Diff View Design (402pt Wide)

Lancer has already chosen unified diff — correct choice. Design constraints:

- **Single file per screen.** File list above (scrollable vertical list of changed files), diff content below. No side-by-side at this width.
- **Syntax highlighting is critical.** Agent diffs are large. Highlighting helps the user quickly find meaningful changes vs. whitespace/import reordering.
- **Collapsible hunks.** Default = collapsed to one-line "file changed" summary. Tap to expand hunk. This is how GitHub Mobile works and users expect it.
- **Line numbers:** Show on scroll but small. Not primary tap targets at 402pt.
- **Color coding:** Green insertion / red deletion per unified diff convention. Add a *purple* tint for AI-generated code (differentiator — user knows this came from an agent, not a human).
- **Tap-to-expand inline:** Tapping an unchanged line reveals the full context around it. Essential for understanding diff in isolation.
- **Max line length:** Truncate with horizontal scroll indicator if >80 chars. Agent code can be verbose.
- **Per-file approval checkbox:** User marks each file as reviewed. "Merge all reviewed" action at top.

**Pattern reference:** Omnara claims "rich diff visualization on mobile screens prevents errors and eliminates extensive scrolling" — but specifics are behind their UI. Working Copy's unified diff is the closest public reference. Source: [Omnara diff docs](https://omnaradocs.com/task/blog/mobile-app-review-git-diffs-autonomous-coding-agents)

### 3.4 Worktree/Agent Visualization on Fleet Tab

The Fleet tab already shows hosts + running agents. Extending for worktrees:

**Card-based layout (one card per worktree/agent):**

```
┌─────────────────────────────────────┐
│  feat/add-oauth                     │ ← branch name
│  ● In Progress   (Claude Code)      │ ← status + agent type
│  ─────────────────────────────────  │
│  Agent is refactoring auth module   │ ← latest action (truncated)
│  ┌──────────────────────────────┐   │
│  │  3 files changed (+127 -14)  │   │ ← diff summary
│  └──────────────────────────────┘   │
│  [View Diff]  [Stop]               │ ← primary actions
└─────────────────────────────────────┘
```

**Key design rules:**
- One card per worktree = one agent.
- Fixed-width unread badge slot (preserving PixelBox alignment — as already established in DebugGalleryView convention).
- Cards are the worktree list. No separate "worktree" navigation.
- Branch name as primary identifier (that's what users will refer to).
- Status color = agent state (thinking green, waiting approval yellow, error red, done gray).
- Swipe-to-delete worktree (with Face ID confirmation if branch has unmerged changes).

**Metaphor:** "Each agent has its own branch and its own copy of the code." This maps cleanly to the existing Fleet concept — an agent *is* a worktree in this model.

### 3.5 Branch/Worktree Switcher

On Fleet tab, a segmented control or picker at top: "Active" | "Completed" | "All". Default = Active (worktrees with running agents or unmerged changes).

Pull-to-refresh fetches latest `git worktree list` and `git branch` state via lancerd.

---

## 4. The Governance Angle

### 4.1 Why Worktrees + Parallel Agents Multiply Blast Radius

In a single-agent workflow, the blast radius is: one branch, one working tree, one agent's actions. With N parallel worktrees, the blast radius becomes N× — each agent can independently:
- Edit overlapping files (conflict at merge time, but user doesn't discover until merge)
- Introduce security vulnerabilities (harder to catch across N agents)
- Each agent requests approval independently → approval fatigue

### 4.2 Approval/Policy Composition

**Per-worktree policy inheritance:** When lancerd creates a worktree, it should apply the host's current policy set (allowed tools, file-scope restrictions, max-turns). This is *delegated policy* — the agent inherits the parent repository's rules. Conductor and Omnara do not appear to offer per-agent policy — they apply host-level constraints equally.

**Approve-once-per-agent:** The emerging pattern (Conductor, Vibe Kanban) is that an agent runs until it needs human input (approval for a risky tool call, clarification of intent, or final merge approval). The user isn't approving each edit — they're approving the *merge*. This is the right model for Lancer: agents run with the same permission model as single-agent mode, but the approval Inbox is *consolidated across all agents* and sorted by urgency.

**Consolidated Inbox:** The Inbox tab shows approval requests from *all* running agents in one stream, with agent/branch attribution on each item:

```
┌─────────────────────────────────────┐
│  ● Agent wants to edit package.json │ ← approval request
│    feat/add-oauth — Claude Code    │ ← source agent + branch
│  [Approve] [Deny] [View Context]   │
├─────────────────────────────────────┤
│  ● feat/add-oauth: ready for merge │ ← merge request
│    3 files, +127/-14               │
│  [View Diff] [Approve Merge]       │
├─────────────────────────────────────┤
│  ● Agent wants to run `rm -rf /`   │ ← high-risk tool call
│    hotfix/login — Claude Code      │
│  [Deny (always)] [Approve Once]    │
└─────────────────────────────────────┘
```

### 4.3 Prior Art for Agent-to-Main Merges

**No direct prior art found.** None of the surveyed tools (Conductor, Nimbalyst, Vibe Kanban, Omnara) treat merge-to-main as a separately governed approval step. They typically:
- Conductor: One-click merge from the review pane. No Face ID or second-factor gate.
- Nimbalyst/Crystal: Squash+rebase+merge UI. Policy is implicit (user controls when to click merge).
- Vibe Kanban: Card moves to "Done" after review. Merge happens then.
- Omnara: User approves diffs from phone. No description of a merge gate.

This is Lancer's differentiator — a genuine governance gap in the market.

**Design for governed merge-back:**

```
User reviews diff on phone
  → taps "Approve & Merge"
  → Face ID prompt (mandatory for merge-to-protected-branch)
  → lancerd runs: git checkout main && git merge <agent-branch> --squash
  → if conflict: notify user on phone, provide option to cancel or view conflicts
  → if clean: push to remote, remove worktree, archive session
  → audit log entry: "User [name] merged [branch] → main at [time], Face-ID verified"
```

### 4.4 Audit Chain

Each worktree lifecycle event should be recorded in the tamper-evident chain:
- Worktree created (which branch, which agent, which user, timestamp)
- Agent started / stopped
- Tool calls approved / denied per agent
- Diff generated (hash of diff)
- Merge initiated / completed (with Face-ID attestation if available)
- Worktree removed

This is already Lancer's architecture — the addition of worktrees simply adds a `worktree_id` dimension to the audit schema.

Sources: [Blast radius engineering](https://activewizards.com/blog/blast-radius-engineering-tool-permission-design-for-ai-agents/), [Claude agent containment](https://open-techstack.com/blog/anthropic-claude-agent-containment-architecture-2026/), [PuppyOne agent compliance](https://www.puppyone.ai/en/blog/compliance-management-ai-agents-governance)

---

## 5. Recommendation

### 5.1 V1 Feature Set (Value/Effort Ranked)

| # | Feature | Value | Effort | Location | Notes |
|---|---|---|---|---|---|
| 1 | **Agent = worktree card in Fleet** | High | Low | Fleet tab | Each agent session creates a worktree. Card shows branch, status, agent type, diff summary. This *is* the worktree list. |
| 2 | **One-tap "New Agent" = create worktree + launch** | High | Medium | Fleet tab "+" | lancerd runs `git worktree add -b <name> <path>`, starts agent in that directory. User provides task prompt. |
| 3 | **Unified diff review (read-only)** | High | Medium | Inbox tab (per-item) | Per-file unified diff. Color coding. Collapsible hunks. Purple tint for AI code. Mark-file-reviewed. |
| 4 | **Approve + merge (governed)** | High | Medium | Inbox tab | Face ID gate. `git merge --squash`. Conflict detection (not resolution). Audit log. |
| 5 | **Consolidated approval Inbox** | High | Medium | Inbox tab | All agents' approval requests + merge-ready notifications in one stream, sorted by urgency. |
| 6 | **Worktree cleanup (auto + manual)** | High | Low | Background + Fleet swipe | Auto-remove on merge. Manual swipe-to-delete (Face ID if unmerged). |
| 7 | **Worktree list with status** | Medium | Low | Fleet tab | Card shows: branch name, agent status, elapsed time, diff summary. |
| 8 | **Stop agent (kill worktree process)** | Medium | Low | Fleet card button | Send SIGTERM to agent process, leave worktree for review. |
| 9 | **Per-worktree audit trail** | Medium | Low | Settings / audit export | Extend existing audit schema with worktree_id dimension. |

### 5.2 IA Placement

- **Fleet tab:** Becomes the "active worktrees" view. Each card = a worktree/agent pair. The existing "hosts" section folds into a header/collapsible since worktrees are per-host.
- **Inbox tab:** All agent-generated events. Approval requests, merge-ready notifications, agent error alerts. Sorted by timestamp. Filterable by agent/worktree.
- **Settings tab:** Worktree-related config: auto-cleanup toggle, merge-to-protected-branch policy, default merge strategy (squash vs merge commit), max parallel agents.

No new tabs needed. The 3-tab IA survives.

### 5.3 The Single Biggest UX Risk

**Accidental merge of unreviewed agent output.** If the user can tap "Merge" without seeing the diff, the phone's speed-convenience becomes a liability.

**Mitigation:** The merge flow *must* force a diff summary screen:
1. User taps "Approve Merge" in Inbox
2. Screen shows: "3 files changed (+127 / -14)" with file list
3. User must scroll through the summary (or tap "View Full Diff" for each file)
4. Acknowledgment checkbox: "I have reviewed the changes"
5. Face ID prompt
6. Execute merge

This is non-negotiable. The same pattern should apply to high-risk tool call approvals (e.g., modifying package.json, running destructive shell commands).

### 5.4 What to Deliberately NOT Build (YAGNI)

| Don't build | Why |
|---|---|
| Interactive rebase UI | Desktop-only power feature. lancerd handles squash via `--squash` merge. |
| Per-line staging | Too granular for 402pt. Agent output is all-or-nothing per file. |
| Git blame on phone | Text-heavy. Extremely wide. Low value in agent context. |
| Worktree-aware file browser | Users should not be browsing worktree files on a phone. That's what the desktop/terminal is for. |
| Cherry-pick UI | Frequency too low. Exceptionally complex touch UI for branch selection. |
| Submodule init/update | Rare. Delegate to desktop or auto-handle in lancerd's worktree-create hook. |
| Multiple remotes management | Single origin is sufficient. Configure once on desktop. |
| SSH key management | Already handled by lancerd's SSH setup. Not a phone task. |
| Real-time terminal scrollback | Omnara offers this; users report it's noisy. Structured diffs + summaries win on mobile. |

### 5.5 Claude Code 2.1 `--worktree` Flag — Note

Claude Code v2.1+ has native `--worktree` support. lancerd should detect whether the agent CLI supports this flag and use it when available, falling back to manual `git worktree add` for agents that don't (Codex CLI, Gemini CLI). This is a *host-side* detail — the phone UI is the same regardless of which mechanism created the worktree.

---

## Sources Index

| Source | URL |
|---|---|
| Git Worktree Complete Guide | https://www.gitworktree.org/ |
| Worktree vs Clone | https://www.gitworktree.org/compare/worktree-vs-clone |
| Worktree Best Practices | https://www.gitworktree.org/guides/best-practices |
| Worktree + Submodules | https://www.gitworktree.org/guides/submodules |
| Worktree + LFS | https://www.gitworktree.org/guides/large-repos |
| Parallel Agents Architecture | https://www.gitworktree.org/ai-tools/parallel-agents |
| Conductor | https://www.conductor.build/ |
| Conductor deep guide | https://codepick.dev/en/guides/conductor-build-intro/ |
| Crystal (GitHub) | https://github.com/stravu/crystal |
| Crystal research | https://rywalker.com/research/crystal |
| cmux | https://cmux.com/docs/getting-started |
| cmux deep dive | https://www.oflight.co.jp/en/columns/cmux-manaflow-ai-agent-terminal-2026 |
| Vibe Kanban | https://vibekanban.online/ |
| Vibe Kanban architecture | https://virtuslab.com/blog/ai/vibe-kanban |
| Omnara | https://www.omnara.com/ |
| Omnara mobile diff review | https://omnaradocs.com/task/blog/mobile-app-review-git-diffs-autonomous-coding-agents |
| Omnara review | https://www.revuo.ai/category/coding-agent-remotes/omnara |
| Omnara App Store | https://apps.apple.com/us/app/omnara-ai-command-center/id6748426727 |
| Agentmaxxing guide | https://vibecoding.app/blog/agentmaxxing |
| Nimbalyst comparison | https://nimbalyst.com/blog/best-git-worktree-tools-ai-coding-2026 |
| Worktrunk | https://worktrunk.dev/ |
| Working Copy iOS Git | https://workingcopyapp.com/users-guide |
| GitHub Mobile changelog | https://github.blog/changelog/2025-09-14-github-mobile-now-supports-ios-26-with-refined-visuals-and-smoother-navigation/ |
| Parallel agent book review | https://dev.to/battyterm/how-to-use-git-worktrees-to-run-multiple-ai-agents-on-the-same-repo-1on8 |
| pnpm + git worktrees | https://pnpm.io/git-worktrees |
| Disk space management | https://gitcheatsheet.dev/docs/advanced/worktrees/disk-space-management/ |
| Blast radius design | https://activewizards.com/blog/blast-radius-engineering-tool-permission-design-for-ai-agents/ |
| Claude agent containment | https://open-techstack.com/blog/anthropic-claude-agent-containment-architecture-2026/ |
| Claude Code `--worktree` flag | https://docs.arantic.com/claude-code/flags |
| Parallel agents dev workflow | https://www.dev-toolbox.tech/tools/git-cheat-sheet/examples/git-worktree-parallel |
| Remote coding full stack | https://dev.to/stevengonsalvez/remote-coding-running-ai-agents-from-anywhere-the-full-stack-4lji |
| Claude Code team setup | https://ai.sulat.com/the-claude-code-team-just-revealed-their-setup-pay-attention-4e5d90208813 |
| Nx blog on worktrees + AI | https://nx.dev/blog/git-worktrees-ai-agents |
| Mobile UX touch targets | https://www.forasoft.com/blog/article/mobile-app-ux-design-best-practices-in-2026 |
| Agent compliance & governance | https://www.puppyone.ai/en/blog/compliance-management-ai-agents-governance |
| `git worktree` official docs | https://git-scm.com/docs/git-worktree |
