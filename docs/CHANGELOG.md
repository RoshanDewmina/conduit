# Agent changelog

Append-only log of agent-made changes. **Every agent session that lands a change (commit,
PR, deploy, doc edit, config/infra change) appends exactly one line per landed unit of work
BEFORE reporting done** — newest first, under today's date heading. One line: what changed
and why, with the branch/PR/commit as the pointer. No essays — the diff is the detail; this
file exists so humans and future agents can see at a glance what has been happening without
re-deriving it from git archaeology. Do not rewrite or delete old lines.

Format: `- HH:MM <agent> — <what + why> (<branch or PR link>)`

## 2026-07-15

- 21:20 Claude Fable (orchestrator) + Codex 019f6841 — landed risk-tiered agent-oracle-harness skill, corrected publish audit, prompt-skill rerouting; added this changelog + rule (docs/codex-oracle-skill)
- 21:10 Claude Fable + Cursor Grok — Siri M1: donation refresh on 7 real state-change notifications, NSSiriUsageDescription, AppIntentsTesting live-execution test (env-gated: iOS 27 sim linkd rejects sim bundles) (PR #125)
- 20:55 Claude Fable + Cursor Grok — Claude/Cursor-app parity wave 1: thread-row diff stats/liveness/unread/preview (PR #121), review-sheet PR affordances (PR #122), transcript activity/to-dos/table cards (PR #123), background-tasks pill+sheet (PR #124)
- 20:50 Claude Fable + Cursor Grok — composer now morphs in place from the home pill instead of presenting a drawer (owner video feedback) (PR #120)
- Claude Fable + Cursor Grok — desktop-session "Decryption failed" fix: SessionMessage.Role decodes thinking + unknown vendor roles; 3 regression tests; live-proven on paired sim (fix/desktop-session-decrypt, PR pending)
- Codex 019f6841 — audited Cursor research bundle, corrected publish-oracle audit, consolidated prompt/history skills to ~/.agents/skills (report: ~/Downloads/2026-07-15-codex-work-report.md)
- 21:45 Claude Fable + Cursor Grok — desktop-decrypt fix live-proven + PR (#127); integration/2026-07-15-night stack created (merges #120–#126); docs stale purge: 32 deletions, 17 corrections (#128)
- 22:05 Claude Fable + Cursor Grok — wave 2 on integration branch: fake-control removal (#129), first-run onboarding (#130), mid-run feedback queue + permission pill (#131), integration rollup PR (#132), state honesty (#133), thread-list filters/customize (#134), Emergency Stop/policy/audit wiring (#135); B4 verified done + B7 audit recorded on #128; integration gates green (761+62+13 tests, app build 0)
