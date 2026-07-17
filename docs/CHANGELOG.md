# Agent changelog

Append-only log of agent-made changes. **Every agent session that lands a change (commit,
PR, deploy, doc edit, config/infra change) appends exactly one line per landed unit of work
BEFORE reporting done** — newest first, under today's date heading. One line: what changed
and why, with the branch/PR/commit as the pointer. No essays — the diff is the detail; this
file exists so humans and future agents can see at a glance what has been happening without
re-deriving it from git archaeology. Do not rewrite or delete old lines.

Format: `- HH:MM <agent> — <what + why> (<branch or PR link>)`

## 2026-07-17

- 17:20 Claude Sonnet 5 — iOS 27 Siri/App Intents research + ranked feature ideas written (docs/product/2026-07-17-ios27-siri-opportunities.md, branch docs/ios27-siri-ideas); key finding: deep LongRunningIntent path already shipped in code, unverified live; App Schemas has no matching Apple domain yet
