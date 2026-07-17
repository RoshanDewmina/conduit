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
- 16:32 Claude Fable (orchestrator) — TestFlight build 2 UPLOADED at `f5de66e3` (adds Send Feedback UI; supersedes build 1 for owner smoke run)
- 15:55 Claude Fable (orchestrator) — push-backend DEPLOYED to Fly with /feedback (live: /health 200, /feedback 503 feedback_unconfigured fail-closed until owner PAT set); private repo github.com/RoshanDewmina/lancer-feedback created with bug/feature/other labels
- 15:58 Claude Fable (orchestrator) — Siri/App Intents test workflow written (docs/test-runs/2026-07-17-siri-test-workflow.md): iOS-27 deep path (LongRunning/ProgressReporting) is in the uploaded TestFlight build; 5-step device test ladder; approve-by-voice deliberately absent
- 15:14 Cursor Grok 4.5 — POST /feedback on push-backend creates GitHub issues (rate-limited, env-gated, httptest-tested) (`feat/feedback-backend`)
