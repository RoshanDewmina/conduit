# Agent changelog

Append-only log of agent-made changes. **Every agent session that lands a change (commit,
PR, deploy, doc edit, config/infra change) appends exactly one line per landed unit of work
BEFORE reporting done** — newest first, under today's date heading. One line: what changed
and why, with the branch/PR/commit as the pointer. No essays — the diff is the detail; this
file exists so humans and future agents can see at a glance what has been happening without
re-deriving it from git archaeology. Do not rewrite or delete old lines.

Format: `- HH:MM <agent> — <what + why> (<branch or PR link>)`

## 2026-07-17

- 15:14 Cursor Grok 4.5 — POST /feedback on push-backend creates GitHub issues (rate-limited, env-gated, httptest-tested) (`feat/feedback-backend`)
