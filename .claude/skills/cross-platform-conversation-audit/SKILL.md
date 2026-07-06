---
name: cross-platform-conversation-audit
description: Use when the user asks for a multi-day or open-ended review of prior Claude Code, Codex, and Cursor conversations on this project — reconciling decisions, plans, attempts, and outcomes into a verified audit report. Distinct from single-session lookups; builds on $agent-session-history-reader for store discovery.
---

# Cross-Platform Conversation Audit

## Overview

Use this skill to mine **N days** of local agent conversations across **Claude Code, Codex, and Cursor** on the Lancer repo, reconcile overlapping threads, and produce a durable audit report. This is a **read-only transcript workflow** plus a **mandatory live-repo verification pass** — not implementation work unless the user separately asks for fixes.

**Do not duplicate** `$agent-session-history-reader`. That skill covers fast session discovery, single-session lookups, and store gotchas for OpenCode/Kimi. This skill owns the **multi-day ledger → full read → independent verification → reconciled report** pipeline.

## When to Use

Invoke when the user asks variations of:

- "Review our conversations over the last N days and tell me X"
- "What did we decide, attempt, ship, or abandon across Claude/Codex/Cursor?"
- "Audit recurring themes / duplicate work / stale plans from recent agent sessions"
- "Reconcile findings across platforms into one report"

**Do not invoke** for:

- A single known session ID or one-off "what happened in chat Y?" → `$agent-session-history-reader`
- Pure code review with no transcript mining
- Implementation or fixes (unless scoped separately after the audit)

## Inputs to Confirm Up Front

Lock these before building the ledger:

| Input | Default | Notes |
|---|---|---|
| **Day window** | 7 | User may say "past week", "since Monday", etc. |
| **Repo anchor** | `/Users/roshansilva/Documents/command-center` | Include git worktrees under the same repo when cwd matches |
| **Platforms** | Claude Code, Codex, Cursor | Add OpenCode/Kimi only if the user asks |
| **Report destination** | Chat summary + optional file in `Downloads/` | Only write to `Downloads/` when asked |

Read `/Users/roshansilva/.hermes/knowledge-base/AGENTS.md` before durable work. Redact secrets, tokens, and personal details from evidence quotes.

## Workflow (Two-Pass — Non-Negotiable)

### Pass 0 — Session ledger (inventory)

Build a **per-platform session ledger** before reading transcripts in depth.

1. Run `agent-session-history-reader/scripts/list-agent-sessions.sh <days> <repo-path>` for a fast cross-tool index.
2. For each platform in scope, run the **ledger queries** in `references/platform-ledger-queries.md` to enumerate every in-scope session in the window.
3. Record per row: platform, session/composer ID, path or DB key, title/first-user-hint, mtime/created_at, cwd/worktree, line-count or message-count estimate, stub flag, fork parent (if any).

**Stub sessions (Claude Code):** near-empty top-level `*.jsonl` files (typically &lt;5 non-metadata lines or no user messages). **Inventory them** but **exclude from deep-read** unless the user explicitly wants full coverage of empty shells.

**Fork sessions:** never assume duplicate content. Claude subagent side dirs, Cursor `forkedFromComposerId`, and Codex `forked_from_id` each need explicit checks (see references).

### Pass 1 — Primary read-through (parallel, exhaustive)

Dispatch **one sub-agent per platform** (Claude / Codex / Cursor). Each agent:

- Reads **every** ledger row assigned to that platform **in full** — no sampling, no "representative sessions"
- Extracts candidate findings with verbatim evidence quotes
- Notes cross-session duplicates within that platform
- Does **not** treat its own synthesis as verified fact about repo state

Load `references/finding-schema.md` for required fields. Use `references/report-template.md` for draft structure.

**Parallelism rule:** one platform per agent; agents must not write the same output file. Merge into a single draft ledger after all three return.

### Pass 2 — Independent verification (the critical step)

A **separate** agent (or the lead session, if quota is tight) re-checks Pass 1 claims against **live repo state**, not against other transcripts:

- `git log --oneline -n 50` and `git log --since=<window-start> --oneline`
- `git status`, relevant `git diff`, branch name
- `gh pr list` / `gh pr view` when PRs are cited
- **Actual file contents** at cited paths (Read tool or `rg`), not memory or prior reports
- `$lancer-verification-gate` commands when a finding claims "built" or "tests pass"

**Why this pass exists:** the 2026-07-06 audit's primary pass repeated a stale claim across three sessions; only live-repo checks caught that the code had already changed.

For each Pass 1 finding, set `status` and `confidence` from **later sessions plus live repo evidence**. Never default to `unresolved` without checking both.

### Pass 3 — Reconcile and report

1. Deduplicate across platforms (`related/duplicate findings`)
2. Resolve contradictions (prefer live repo &gt; later session &gt; earlier session)
3. Produce the final report per `references/report-template.md`
4. Call out: repeated audits of the same topic, abandoned threads, verified ships, and open gaps

## Delegation When Claude Quota Is Tight

Pass 2 (and optionally Codex/Cursor Pass 1 legs) may be delegated to:

```bash
cursor-agent --print --model composer-2.5
```

**Run sequentially, not in parallel.** Concurrent `cursor-agent` processes race on shared `~/.cursor/cli-config.json` (confirmed twice). **Do not** isolate via separate `$HOME` — that breaks Keychain auth.

Acceptable pattern: Claude runs Claude Pass 1 → `cursor-agent` runs Codex Pass 1 → `cursor-agent` runs Cursor Pass 1 → one verifier runs Pass 2 (Claude or `cursor-agent`, still sequential).

## References

| File | Load when |
|---|---|
| `references/platform-ledger-queries.md` | Building the per-platform session ledger |
| `references/finding-schema.md` | Extracting or verifying individual findings |
| `references/report-template.md` | Writing the final reconciled report |
| `../agent-session-history-reader/references/session-stores.md` | Baseline store paths; OpenCode/Kimi if in scope |

## Anti-Patterns

- Sampling "a few representative sessions" instead of full ledger coverage
- Trusting a generated report or memory summary as ground truth
- Skipping Pass 2 because Pass 1 "already checked the code" in transcript
- Treating forked/subagent sessions as duplicates without reading fork metadata
- Running multiple `cursor-agent` processes concurrently
- Dumping full transcripts into chat — use IDs, paths, and short verbatim quotes
