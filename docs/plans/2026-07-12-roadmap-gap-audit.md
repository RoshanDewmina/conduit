# Roadmap gap audit — 2026-07-10 plan vs master (2026-07-12 evening)

Source plan: `docs/product/2026-07-10-lancer-agent-build-roadmap.md` (owner's Downloads copy is
identical vintage). Statuses: ✅ done+evidenced · 🔶 partial · ❌ not started · 🅿 parked by design.

## Phase 0 — git hygiene → ✅ DONE (2026-07-11, ledger evidence)

## Phase 1 — dogfood MVP (weeks 1–2) → ~80%, on track

| Item | Status | Evidence / gap |
|---|---|---|
| 1.1 streaming dual-throttle + overlay | ✅ | ChatStreamingTextPacer/Smoother; live streaming proven (#82/83, sim gates) |
| 1.1 auto-scroll policy | 🔶 | basic follow exists; Orca 48pt near-bottom + jump-to-latest not ported |
| 1.1 tool-call cards | ❌→lane queued | THE visible gap (owner screenshots 2026-07-12): live path persists tool artifacts but no view renders them; imported path flattens structure at the daemon. Full study done (see 2026-07-12 rendering research in orchestrator-state) — unified normalization design in brainstorm with owner |
| 1.1 markdown preprocessing | ✅ | preprocessor + fixtures (#83 wave); memoization + degenerate-input guard (#101) |
| 1.1 stop ladder + derived-offline | 🔶 | honest statuses landed (#93/#97); Happier 3-tier stop ladder not ported; emergency stop still client-orchestrated |
| 1.2 push approvals incl. lock screen | ✅ (re-proof pending) | device-proven 07-08 (`732071a7`) + C2 06-23; **needs fresh Tier-0 re-proof on current tip — that IS the upcoming on-device test** |
| 1.3 composer + thread list | ✅ | dogfooded end-to-end today (real fix dispatched from composer, PRs #95–#99 hardened list/bucketing/backfill) |
| 1.4 dogfood log | ✅ exists, 🔶 unused | `docs/dogfood-log.md` has no entries — needs owner habit, not code |

## Phase 2 — hands-free + trust (weeks 3–4) → ~50%

| Item | Status | Notes |
|---|---|---|
| 2.1 Siri Phase 1 (26-safe) | ✅ merged | polish-against-use pending (dogfood) |
| 2.2 Live Activities in daily loop | 🔶 | core merged + device-proven 06-23; work packages LA-1 (token churn), LA-2 (8h refresh), LA-3 (content state), LA-4 (device proof) NOT done. LA-4 = part of the on-device test day |
| 2.3 receipt card + contract echo | ✅ | Proof card + Proof Reel shipped (#90), receipts live-proven repeatedly today; placement move to Flight Recorder backlogged (owner 2026-07-12) |
| 2.4 context/budget sheet | ❌ | not started (small) |
| 2.5 sync refinements | 🔶 | notify-then-re-read effectively in place (list merge + fetch-since-seq, #99/#101 pagination); ephemeral-event split not done |

## Phase 3 (Aug–Sept) → 🅿 correctly not started, with two exceptions

- S27 deep Siri: Phase 2 branch (`cursor/siri-phase2-fixes-9257`) implemented + device-tested,
  parked on the iOS 26→27 target decision (S27-0). Owner phone is on 27 — decision now unblocked.
- Loop supervision / PR surface / fork: not started (per plan).
- LAUNCH-1..4: not started. **LAUNCH-4 says external TestFlight ~Aug 25** — see verdict below.

## Not-in-plan work absorbed this week (same-phase interrupts, all shipped)
Cwd/bucketing P0 (#95–#98) · fresh-install backfill (#99) · long-transcript import + rendering
(#100–#101) · relay stability fixes (earlier in week: #80–#94 punch list) · designs approved:
hot-swap + identity badges, Orca terminal port map, readiness audit.

## Verdict — distance to milestones

**On-device test (Tier-0 re-proof + LA-4): READY NOW except one blocker.**
The relay session lifecycle (phone slot churn on reconnect/re-pair; backend slot TTL; first-send
race) is the single flakiest surface — it interrupted THIS audit's sim pass. It's owner-visible
("machine didn't respond", pairing losses) and would poison a tester's first hour.
→ Fix-before-testers: **REL-1 relay session robustness lane** (backend slot handling + client
identity re-pair + first-send retry) — sensitive, needs its own spec; ~1–2 lanes.

**To tester onboarding (small external TestFlight), remaining critical path:**
1. REL-1 relay robustness (blocker, above)
2. Tool-call/thinking rendering lane (owner P0 today; unified normalization design → 2 lanes: daemon schema + iOS cards)
3. On-device test day: Tier-0 + 5c + LA-4 (owner-gated, ~half a day)
4. Onboarding smoke on a CLEAN machine (curl installer → pair → first run) — the tester's actual first hour; `lancer-onboarding-smoke` skill exists
5. TestFlight build refresh + review-notes stub (LAUNCH-3 minimum, not full App Review)
Everything else (context sheet, stop ladder, S27, uploads, terminal, hot-swap) improves retention but does not block first testers.

**Estimate at current velocity (this week shipped ~20 gated PRs): items 1–2 ≈ 2–3 working days;
3–5 ≈ 2 days including owner time. Realistic tester-ready: ~1 week — well ahead of the plan's
Aug 25 TestFlight ramp.**
