# Agent changelog

Append-only log of agent-made changes. **Every agent session that lands a change (commit,
PR, deploy, doc edit, config/infra change) appends exactly one line per landed unit of work
BEFORE reporting done** — newest first, under today's date heading. One line: what changed
and why, with the branch/PR/commit as the pointer. No essays — the diff is the detail; this
file exists so humans and future agents can see at a glance what has been happening without
re-deriving it from git archaeology. Do not rewrite or delete old lines.

Format: `- HH:MM <agent> — <what + why> (<branch or PR link>)`

## 2026-07-16

- 10:45 Claude Sonnet 5 — fix first-send-after-pairing approval race: `e2eRouter.sendApproval` (e2e_router.go) now retries with short bounded backoff when the relay client isn't paired at delivery time, instead of dropping once and waiting solely on the next unrelated peer_joined; root cause was a relay identity-change re-pair (resident.go's startRelayWatch→connectRelay) that can take well over a minute to re-settle after an already-paired session is torn down (observed live: 09:48:57 connected → 09:50:55 paired in a 2026-07-16 repro). Regression test `TestE2ERouterSendApprovalSurvivesFirstSendRace` (daemon/lancerd/e2e_router_test.go), `go test ./daemon/lancerd/... -race` green. NOT merged — left on `fix/first-send-approval-race` (`.worktrees/fix-first-send-approval-race`) for Fable/Sonnet full-diff review per relay-protocol sensitivity.
- 06:27 Cursor Grok — fix pairing UX: Remove no longer races NavigationLink (alert vanished / stuck offline host); MachineDetail Remove; keep pairing-sheet errors sticky across socket close; brief paired confirmation before dismiss (`cursor/desktop-history-and-terminal-3510`)
- 06:02 Cursor Grok (orchestrator) — daily-use workflow audit on `integration/2026-07-15-night` @ b17b6172: sim L1 PASS, L2–L4 evidence, GAP_LIST + L6 BLOCKED (phone orphaned); docs only (`docs/test-runs/2026-07-16-daily-use-audit/`)
- 07:55 Cursor Grok — replace Phase 1 phone-SSH terminal with Orca 1:1 daemon-owned PTY: `lancerd/terminal` Host+Session (creack/pty), relay `terminalCreate/Send/Resize/Close/Subscribe` + Orca stream frames, iOS `RelayTerminalModel` over E2E; deleted SSH LiveTerminalModel/password/host-setup (`cursor/desktop-history-and-terminal-3510`)
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
