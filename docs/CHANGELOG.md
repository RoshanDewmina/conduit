# Agent changelog

Append-only log of agent-made changes. **Every agent session that lands a change (commit,
PR, deploy, doc edit, config/infra change) appends exactly one line per landed unit of work
BEFORE reporting done** — newest first, under today's date heading. One line: what changed
and why, with the branch/PR/commit as the pointer. No essays — the diff is the detail; this
file exists so humans and future agents can see at a glance what has been happening without
re-deriving it from git archaeology. Do not rewrite or delete old lines.

Format: `- HH:MM <agent> — <what + why> (<branch or PR link>)`

## 2026-07-17

- 16:50 Claude Fable (orchestrator) — LancerWidgets signing fixed: Xcode had NO Apple ID signed in (owner action, one-time); once signed in, App Groups capability auto-registered and all 3 signing errors cleared. Debug device build now SUCCEEDS with LancerWidgets.appex embedded, installed+launched on owner's physical iPhone (both Lancer + LancerWidgets processes confirmed running)
- 16:57 Claude Fable (orchestrator) — TestFlight build 3 UPLOADED (delivery `b942714a`, tip `aaf265ad`) — first build to include widgets/Live Activity extension
- 17:20 Claude Sonnet 5 — iOS 27 Siri/App Intents research + ranked feature ideas written (docs/product/2026-07-17-ios27-siri-opportunities.md, branch docs/ios27-siri-ideas); key finding: deep LongRunningIntent path already shipped in code, unverified live; App Schemas has no matching Apple domain yet
