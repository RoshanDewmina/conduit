# Agent changelog

Append-only log of agent-made changes. **Every agent session that lands a change (commit,
PR, deploy, doc edit, config/infra change) appends exactly one line per landed unit of work
BEFORE reporting done** — newest first, under today's date heading. One line: what changed
and why, with the branch/PR/commit as the pointer. No essays — the diff is the detail; this
file exists so humans and future agents can see at a glance what has been happening without
re-deriving it from git archaeology. Do not rewrite or delete old lines.

Format: `- HH:MM <agent> — <what + why> (<branch or PR link>)`

## 2026-07-16

- 07:45 Cursor Grok — desktop past-session open now prefers `attachObservedSession` + ledger fetch (full history) over the 200-line tail `agent.sessions.transcript` path; fallback retained; ShellLiveBridge regression test (`cursor/desktop-history-and-terminal-3510`)
- 07:30 Cursor Composer — Phase 1 interactive SSH terminal: LiveTerminalModel/View (SwiftTerm + inline accessory rail + TOFU host-key sheet), TerminalSessionCoordinator, SSHHostSetupSheet, MachineDetailView; wired Trusted Machines → detail, thread ⋯ → open at cwd, AppRoot fullScreenCover + password prompt; DEBUG `LANCER_DESTINATION=terminal` (`cursor/desktop-history-and-terminal-3510`)

## 2026-07-15

- 21:20 Claude Fable (orchestrator) + Codex 019f6841 — landed risk-tiered agent-oracle-harness skill, corrected publish audit, prompt-skill rerouting; added this changelog + rule (docs/codex-oracle-skill)
- 21:10 Claude Fable + Cursor Grok — Siri M1: donation refresh on 7 real state-change notifications, NSSiriUsageDescription, AppIntentsTesting live-execution test (env-gated: iOS 27 sim linkd rejects sim bundles) (PR #125)
- 20:55 Claude Fable + Cursor Grok — Claude/Cursor-app parity wave 1: thread-row diff stats/liveness/unread/preview (PR #121), review-sheet PR affordances (PR #122), transcript activity/to-dos/table cards (PR #123), background-tasks pill+sheet (PR #124)
- 20:50 Claude Fable + Cursor Grok — composer now morphs in place from the home pill instead of presenting a drawer (owner video feedback) (PR #120)
- Claude Fable + Cursor Grok — desktop-session "Decryption failed" fix: SessionMessage.Role decodes thinking + unknown vendor roles; 3 regression tests; live-proven on paired sim (fix/desktop-session-decrypt, PR pending)
- Codex 019f6841 — audited Cursor research bundle, corrected publish-oracle audit, consolidated prompt/history skills to ~/.agents/skills (report: ~/Downloads/2026-07-15-codex-work-report.md)
- 22:12 Claude Fable — full-app test plan + session report (test-runs/2026-07-15-night-full-app-test-plan.md); STATUS_LEDGER refreshed to the 18-PR night state; device build installed + paired live on owner iPhone (#136 B6 tests, #137 C6 triage merged into the night stack)
