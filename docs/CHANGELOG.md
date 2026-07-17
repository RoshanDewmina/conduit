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
- 15:06 Claude Fable (orchestrator) — **TestFlight build UPLOADED** (UPLOAD SUCCEEDED, delivery `2c17f676`, tip `639ba8da`, Xcode 27A5218g + Metal Toolchain component 27A5218h which the fresh beta lacked); appears in ASC → TestFlight after processing (`scripts/release-ios-testflight.sh`)
- 14:30 Claude Fable (orchestrator) — App-Store push session close-out: fresh Release IPA built+signed at `5f4f1181`, TestFlight upload blocked ONLY on ASC 90534 (Xcode 27 beta 1 local vs beta 2+ required — owner updates Xcode, re-runs `scripts/release-ios-testflight.sh`); STATUS_LEDGER updated (`master`)
- 14:20 Claude Fable (orchestrator) — fix Release-config archive: DEBUG-seam leaks (WorkspacesView terminalCoordinator @Environment inside #if DEBUG but used unconditionally; ProofReelView debug scrub/autoplay seams called outside DEBUG) — Release device build now SUCCEEDS (`master`)
- 14:05 Claude Fable (orchestrator) — App-Store push: s27 iOS-27 target raise merged (#167, full gates); rel1 proven ALREADY-MERGED as PR #110 (REL1_REBASE_NOTES.md) — branch deleted not re-applied; TestFlight release script committed (scripts/release-ios-testflight.sh); salvaged reconnect-10x BLOCKED evidence bundle + 07-07 fable research brief (`release-prep docs`)
- 18:10 Claude Sonnet 5 — reconciled `docs/PUBLISH_READINESS_CHECKLIST.md` against live repo evidence (last reconciled 2026-07-15, had drifted): closed B3 (app-target BUILD SUCCEEDED, PR #164), B7/B11b (Emergency Stop implemented `d68de81e` + live-FAIL/fix via PR #160/#161), updated C2/D3 (pairing confirmed live, APNs daemon fix deployed, only lock-screen owner-check remains), closed D4 as moot (sslip.io superseded by the 2026-07-13 Fly cutover — `conduit-push.fly.dev` verified as the live default in `RelaySettings.swift`/`project.yml`), refreshed §A with the PR #154-#164 chain, and added a new "Path to App Store submission" section (`docs/publish-checklist-reconcile`, doc-only)
