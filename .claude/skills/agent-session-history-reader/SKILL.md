---
name: agent-session-history-reader
description: Use when the user asks to inspect, verify, mine, summarize, or learn from prior local AI-agent conversations on this Mac, especially Claude Code, Codex, OpenCode, or Kimi Code sessions, or when an agent needs to get up to speed from recent chats before creating plans, skills, handoffs, or reports.
---

# Agent Session History Reader

## Overview

Use this skill to find and summarize local agent conversations without dumping private transcript data into chat. It is read-only by default and is optimized for Roshan's local macOS agent stores.

## Workflow

1. Read `/Users/roshansilva/.hermes/knowledge-base/AGENTS.md` before durable work. Do not read raw files under `secure/`; use the personal KB MCP for personal/PII facts.
2. Start from the user's concrete anchors: repo path, date range, agent name, session title, task terms, or a report path.
3. Run `scripts/list-agent-sessions.sh <days> <repo-path>` for a fast index across Claude, Codex, OpenCode, and Kimi.
4. Inspect structure before transcript content: types, schemas, counts, IDs, cwd, titles, timestamps, and paths.
5. Open only the few most relevant session files or database rows. Prefer exact paths, session IDs, timestamps, titles, and short evidence snippets over broad transcript reading.
6. Summarize findings as claims backed by local paths. Separate "verified from session data" from "inferred from surrounding context."
7. Redact secrets, tokens, passwords, auth paths, private prompts, and personal details that are not required for the task.

## Store Map

Load `references/session-stores.md` when you need exact commands or format details.

- Claude Code: `~/.claude/projects/<escaped-cwd>/*.jsonl`; side data can live under per-session subagent/tool-result folders.
- Codex: `~/.codex/session_index.jsonl` plus `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
- OpenCode: `~/.local/share/opencode/opencode.db` SQLite database
- Kimi Code: `~/.kimi-code/session_index.jsonl` plus `~/.kimi-code/sessions/wd_<workspace>_<hash>/session_*/state.json`

## Evidence Rules

- Use `rg` first for text search, then structured parsing where available.
- For OpenCode, use SQLite read-only connections; do not copy or mutate the database.
- Do not use `cat` on large JSONL or log files. Use `jq`, `rg`, `tail`, `head`, `sqlite3`, and type/count queries.
- Do not read auth, OAuth, credential, token, or device files.
- Do not treat a generated report as ground truth. Verify against actual sessions and current CLI/docs when the claim can drift.
- When producing a durable report, save it directly to `/Users/roshansilva/Downloads/` only if the user asked for a Downloads artifact.
