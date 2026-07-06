---
name: lancer-parallel-handoff
description: Use when the user asks to dispatch, parallelize, hand off, split, delegate, or coordinate Lancer work across multiple AI agents, including Claude Code plus OpenCode/deepseek executors, Codex subagents, or lane-based implementation plans.
---

# Lancer Parallel Handoff

## Overview

Use this skill to split Lancer work into independent agent lanes with explicit file ownership and verification. Parallelism is useful only when write scopes do not collide.

## Dispatch Rules

1. First run the context pass from `$lancer-context-onboarding`.
2. Decompose by dependency order, not by equal-sized chunks.
3. Give every worker an exclusive write set or a separate worktree/branch. Before creating a new
   one, run `scripts/check-worktree-sprawl.sh` — worktrees reduced from 32 to 2 on 2026-07-04 had
   regrown to 14 by 2026-07-06 with no automated check, contributing to a 67GB DerivedData
   disk-exhaustion incident. Remove worktrees for merged/abandoned branches before adding more.
4. Tell every worker that other agents may be editing the repo and they must not revert unrelated changes.
5. Keep shared files serialized unless each agent has a separate branch/worktree and a clear merge owner.
6. The planner/verifier must review outputs before treating worker work as done.

## Hot Files

Coordinate or serialize edits to these files:

- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift`
- `Packages/LancerKit/Sources/AppFeature/NewChatTabView.swift`
- `Packages/LancerKit/Sources/AppFeature/LancerSidebarView.swift`
- `Packages/LancerKit/Sources/AppFeature/SidebarShellState.swift`
- `daemon/lancerd/dispatch.go`
- `daemon/lancerd/server.go`

## Handoff Shape

Load `references/handoff-template.md` when drafting prompts.

Each lane needs:

- objective
- explicit in-scope and out-of-scope files
- required docs to read
- acceptance checks
- commands to run
- collision warnings
- final reporting format

## Lancer V1 Order

Default wave order:

1. Durable chat history/search/continuation foundation
2. Chat artifacts and sidebar shell
3. Fleet routing into threads
4. Launch hardening and final verification

