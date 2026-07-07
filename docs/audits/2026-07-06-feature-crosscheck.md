# Feature cross-check — SSOT pass 2026-07-06

Cross-check of Codex sessions `019f2dec`, `019f2ebf`, `019f2f6d`, `019f3763` against  
[`docs/product/2026-07-05-lancer-feature-master-plan.md`](../product/2026-07-05-lancer-feature-master-plan.md) §5–§8 and  
[`docs/product/FEATURE_BACKLOG.md`](../product/FEATURE_BACKLOG.md).

## Sources merged

| Source | Section used |
|--------|----------------|
| Master plan §5 | MVP feature table (33 rows) |
| Master plan §6 | Post-MVP fast-follows |
| Master plan §7 | Correctness gaps |
| Master plan §8 | Rejected features |
| Strategy doc §Accepted Feature Set | V1 core + fast-follows cross-check |
| Away consolidation §4 | Stage catalog CARRIED items |
| Codex `019f3763` | Tier 0 engineering gate rows |

## Completeness result

**`missing_from_backlog: []`** — all finalized V1 features from the owner-flagged Codex chain appear in `FEATURE_BACKLOG.md` sections 1–7.

### Spot checks (sample)

| Feature | In backlog section | Wireframe linked |
|---------|-------------------|------------------|
| Question Ladder | §2 V1 core | `05-work-thread.html` |
| Interruption Budget | §2 V1 core | `04-launch-setup.html` |
| Mobile QA Annotation | §2 V1 core | `05-work-thread.html` |
| Clips + `lancer.proof` | §4 Post-MVP | — (deferred) |
| Cross-Vendor Second-Agent Review | §4 Post-MVP | `07-fast-follows.html` |
| Tier 0 live dispatch | §1 Tier 0 | `04-launch-setup.html` |
| BiometricGate P0 | §5 Correctness | — |
| Needs-Me Queue restructure | §7 Rejected | — |

## Notes

- `019f2f6d` contributes verification status, not new feature rows — mapped to §5.
- `Session-survives-disconnect UI signal` from `019f2dec` consolidation §4 — added explicitly in §2 (not in master plan §5 table verbatim).
- Business rows (pricing, Jul 21 gate) in §6 per plan requirement.

## Verifier follow-up

Independent subagent should confirm live-repo claims in STATUS_LEDGER (P0 fix branch, Siri not on master, wireframe paths exist on disk).
