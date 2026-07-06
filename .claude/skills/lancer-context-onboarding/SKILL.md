---
name: lancer-context-onboarding
description: Use when starting any non-trivial Lancer task in /Users/roshansilva/Documents/command-center, including planning, reviews, implementation, verification, issue triage, reports, or when the user asks an agent to get up to speed from repo context and prior work.
---

# Lancer Context Onboarding

## Overview

Use this skill to build a current, repo-grounded mental model before planning or editing Lancer. Favor current files and verified local state over stale reports or remembered decisions.

## Required Pass

1. Read `/Users/roshansilva/.hermes/knowledge-base/AGENTS.md` for local workflow rules.
2. Read `docs/agent-contract.md` for repo invariants before durable changes.
3. Read `CLAUDE.md` when the task involves agent workflow, Swift/iOS verification, or parallel execution.
4. Read `README.md` and `ARCHITECTURE.md` when product scope, module layout, or non-goals matter.
5. Run `git status --short` and treat existing changes as user/other-agent work. Do not revert them unless explicitly asked.
6. Open only task-relevant docs from `docs/product/FEATURE_BACKLOG.md`, `docs/KNOWN_ISSUES.md`, `docs/PUBLISH_READINESS_CHECKLIST.md`, `docs/validation-playbook.md`, and `docs/test-runs/`.
7. If memory is available and the task depends on prior decisions, do a quick memory pass before deeper repo exploration.

## Current Product Direction

Load `references/current-lancer-map.md` for the compact map.

- Chat is the default first surface.
- Sidebar-first navigation is the active V1 direction.
- Fleet is important but secondary; it opens related chat/thread detail.
- Inbox remains the system of record for approvals.
- Activity/history should not return as a root tab; useful pieces belong in Recent Threads, Needs Attention, and audit details.

## Output Standard

- Say which files are current evidence and which are older reports or plans.
- Note that there is no root `AGENTS.md` in the Lancer repo unless one is later added; scoped `AGENTS.md` files under subprojects apply only to those scopes.
- For planning, produce lane-ready tasks with owners, touched files, dependencies, and verification gates.
- For implementation, keep edits scoped to the module boundaries in `docs/agent-contract.md`.
- For review, lead with bugs, risks, regressions, and missing tests.
