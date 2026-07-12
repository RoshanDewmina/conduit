# Owner asks ledger — 2026-07-11 session (give this to the new chat to verify + parallelize)

Legend: ✅ done+merged · 🟡 staged/partial (PR open or piece missing) · ❌ not done · 👤 needs you

## Done and merged
| # | Ask | Status / evidence |
|---|---|---|
| 1 | Phase 0: land W0.A, remove wipe worktree, build_sim green | ✅ PR #69 (+ empty-tree commit repair) |
| 2 | CI reviewer on CURSOR_API_KEY, non-Grok model | ✅ claude-review.yml, Opus 4.8, live on every PR. 👤 you never confirmed the Cursor dashboard shows it as PLAN usage not metered — check once |
| 3 | No-metered-billing standing rule | ✅ REVIEW_STANDARDS + state file + memory |
| 4 | Merge #69; drop stashes/checkpoint refs | ✅ |
| 5 | Frontend = Codex Workspaces shell (your screenshots) | ✅ PR #75; SSOT docs corrected |
| 6 | Streaming fix (janky/stucky) | ✅ #79 + #85 pacer; sim-gate proven |
| 7 | Follow-ups + full conversation kept on screen | ✅ #79 (transcript bug found BY the gate) |
| 8 | Raw HTML tags + squashed markdown blocks | ✅ #85 (your screenshots are the test fixtures) |
| 9 | Model picker + default Haiku + remove cloud chip | ✅ #84 for Claude models (+#82 daemon fix it exposed). 🟡 Cursor as a pickable vendor NOT done — needs a cursor-agent adapter in dispatch.go (never laned; sensitive path) |
| 10 | Pairing pain: connect automatically, dev+prod | ✅ #80 keepalive + #81 pair-once identity; proven on prod relay ×6 |
| 11 | Subagent/running-agent visibility | ✅ #86 Agents section. 🟡 your "open conversation directly, not Continue-in-Lancer" fix = punch-list #4, not laned |
| 12 | Study BennyKok/lfg for features | ✅ docs/product/2026-07-11-lfg-study-and-usage-limits.md (MIT; usage collector is portable) |
| 13 | Sim live-loop gate rule (no feature without sim proof / your greenlight) | ✅ codified in 3 docs; enforced all night — caught 4 real bugs |
| 14 | sudo for lancerd? | ✅ answered: no — Full Disk Access instead; codesigning queued so TCC survives updates |

## Staged — PRs open, tests green, need sim gate → merge → one device build
| # | Ask | PR |
|---|---|---|
| 15 | Duplicate command-center workspaces + thread not under repo | #89 |
| 16 | Proof video (Proof Reel + receipt card) | #90 (gate needs a run that emits a receipt) |
| 17 | Flight recorder (step-timeline replay) | #91 |

## Not done — the new chat should lane these (parallelizable ✳ where marked)
| # | Ask | State |
|---|---|---|
| 18 | **Notifications working** (your #1 blocker) | ❌ APNs lock-screen co-test never ran — 👤 needs 5 min: you force-quit the app, agent fires a gated action + traces daemon→conduit-push logs |
| 19 | Thread LIST stale "Working" after daemon marks turns failed | ❌ punch-list #1 — fix first ✳ |
| 20 | Tap agent session → open conversation directly | ❌ punch-list #4 ✳ |
| 21 | Stale pending approvals auto-dropped when their run dies (ghost cards) | ❌ punch-list #5 (hand-purged twice tonight) ✳ |
| 22 | Plan-limits view (Claude/Cursor/Codex 5hr+weekly) | ❌ research DONE (lfg study has the exact endpoints; Cursor infeasible per-device — needs your call to skip it for V1); daemon collector + iOS view not built ✳ |
| 23 | Account switcher + near-limit hotswap (Orca-style) | ❌ queued; 2026-07-04 audit memo has the mechanism ✳ |
| 24 | Text-to-agent/orchestrator in-app messaging | ❌ 👤 you asked me to sanity-check scope with you first — my recommendation: thin thread type, not a new surface. Confirm and it gets laned |
| 25 | In-app bug reporting | ❌ lfg had nothing portable; needs a small design (likely: bug-report sheet → GitHub issue via daemon) ✳ |
| 26 | Artifact support in chat (beyond receipts) | 🟡 receipts staged (#90); general file/image artifact rendering not built ✳ |
| 27 | Deep iOS integration (S27) ASAP | 🟡 S27-0 target raise committed on feat/s27-deep-integration; plan committed (iOS 27 SDK already installed — all packages CAN start). Next: S27-2a Live-Activity restore → S27-2 Siri long-running dispatch ✳ |
| 28 | Cross-device continuation (start on one device, continue on another) | 🟡 plumbing merged long ago; end-to-end proof never run (continuity study §4 has the QA script) ✳ |
| 29 | Tier 0 / 5c device re-proof on current tip | ❌ 👤 checklist ready (docs/test-runs/2026-07-11-tier0-owner-checklist.md); tonight's session covered pairing+loop pieces but not the formal run or 5c |
| 30 | Emergency stop from phone | ❌ unverified on the current shell — must confirm before unattended use |
| 31 | dogfood-log.md entries | 👤 file exists, empty — one line/day is the Phase 1 exit metric |

## Known-open daemon backlog (found tonight, not owner-asked but affects reliability)
- Dispatch racing a relay re-key second can orphan a send (rare; logged)
- Pairing sheet shows stale "waiting for peer" instead of "code expired" (UX)
- lancerd codesigning (stops repeat TCC prompts after daemon updates)
