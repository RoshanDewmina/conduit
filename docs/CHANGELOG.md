# Agent changelog

Append-only log of agent-made changes. **Every agent session that lands a change (commit,
PR, deploy, doc edit, config/infra change) appends exactly one line per landed unit of work
BEFORE reporting done** — newest first, under today's date heading. One line: what changed
and why, with the branch/PR/commit as the pointer. No essays — the diff is the detail; this
file exists so humans and future agents can see at a glance what has been happening without
re-deriving it from git archaeology. Do not rewrite or delete old lines.

Format: `- HH:MM <agent> — <what + why> (<branch or PR link>)`

## 2026-07-17

- 18:10 Claude Sonnet 5 — reconciled `docs/PUBLISH_READINESS_CHECKLIST.md` against live repo evidence (last reconciled 2026-07-15, had drifted): closed B3 (app-target BUILD SUCCEEDED, PR #164), B7/B11b (Emergency Stop implemented `d68de81e` + live-FAIL/fix via PR #160/#161), updated C2/D3 (pairing confirmed live, APNs daemon fix deployed, only lock-screen owner-check remains), closed D4 as moot (sslip.io superseded by the 2026-07-13 Fly cutover — `conduit-push.fly.dev` verified as the live default in `RelaySettings.swift`/`project.yml`), refreshed §A with the PR #154-#164 chain, and added a new "Path to App Store submission" section (`docs/publish-checklist-reconcile`, doc-only)
