# Agent changelog

Append-only log of agent-made changes. **Every agent session that lands a change (commit,
PR, deploy, doc edit, config/infra change) appends exactly one line per landed unit of work
BEFORE reporting done** — newest first, under today's date heading. One line: what changed
and why, with the branch/PR/commit as the pointer. No essays — the diff is the detail; this
file exists so humans and future agents can see at a glance what has been happening without
re-deriving it from git archaeology. Do not rewrite or delete old lines.

Format: `- HH:MM <agent> — <what + why> (<branch or PR link>)`

## 2026-07-16

- 11:05 Claude Sonnet 5 (orchestrator) — full-diff reviewed + merged `fix/first-send-approval-race` into `integration/2026-07-16-untested-sweep` (`4e45dbaa`); `go build && go test ./... -race` green post-merge (lancerd, policy, terminal). Noted one non-blocking edge case (possible double-delivery of the same approvalID if `resendPendingApprovals` also fires during the retry window) — not fixed, low severity.
- 10:45 Claude Sonnet 5 — fix first-send-after-pairing approval race: `e2eRouter.sendApproval` (e2e_router.go) now retries with short bounded backoff when the relay client isn't paired at delivery time, instead of dropping once and waiting solely on the next unrelated peer_joined; root cause was a relay identity-change re-pair (resident.go's startRelayWatch→connectRelay) that can take well over a minute to re-settle after an already-paired session is torn down (observed live: 09:48:57 connected → 09:50:55 paired in a 2026-07-16 repro). Regression test `TestE2ERouterSendApprovalSurvivesFirstSendRace` (daemon/lancerd/e2e_router_test.go), `go test ./daemon/lancerd/... -race` green.
- 10:52 Claude Sonnet 5 — Lane A2 XCUITest re-verification of governance candidates (docs only): #2 Policy editor + #3 Audit feed **FAIL** (both require an SSH `DaemonChannel`, relay-only pairing hits "requires an SSH host session" — a real scope gap in Settings advertising them as reachable); #24 Agents tap-through **PASS** (opens a real continuable thread); #1 Emergency Stop inconclusive (harness timing). `docs/test-runs/2026-07-16-untested-feature-sweep/LA2-report.md`
- 10:50 Claude Sonnet 5 — Lane E terminal + desktop-history live sweep (docs only): terminal surface **FAIL** — daemon never confirms pairing the phone believes completed (`e2e: paired with phone` never logged despite phone-side `.paired` state), blocking all 4 candidates in scope. `docs/test-runs/2026-07-16-untested-feature-sweep/LE-report.md`
- 10:40 Claude Sonnet 5 — Fix lane F2 verdict: `fix/addrepo-name-cwd-truncation` (545574a7) claimed a leaf-truncation bug that isn't reproducible in the pre-fix code (name/cwd were already separate params); its only real effect is unrelated trailing-slash micro-hardening. Recommend dropping the branch — no PR opened.
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
