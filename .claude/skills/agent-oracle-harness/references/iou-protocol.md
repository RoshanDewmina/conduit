# IOU protocol — bounded repair loops

Prevent unbounded implement → review → fix cycles. When capped, escalate to owner/Fable with an explicit IOU.

## Round caps

| Phase | Max rounds | Then |
|-------|------------|------|
| Implementer self-fix (same task) | 2 | Escalate or split scope |
| Adversarial review → fix loop | 2 per reviewer tranche | IOU |
| Orchestrator re-gate failures | 2 | IOU |
| Full feature (pilot → ship) | 5 total IOU-eligible rounds | Hard stop — owner decision |

A **round** = one implementer attempt + verification run. Reviewer passes do not consume a round; reviewer-requested fixes do.

## IOU format

Write into `docs/plans/orchestrator-state.md` under the active session:

```markdown
### IOU — <slug>
- **blocked_on:** <owner | Fable | credential | device re-pair | external dependency>
- **round:** N of cap
- **last_failure:** verbatim error or test name
- **evidence:** docs/test-runs/YYYY-MM-DD-<slug>/
- **ask:** <one concrete decision or unblock step>
```

## Escalation rules

1. Never spin silently past the cap — write the IOU and stop coding.
2. `blocked_on: owner` for: phone re-pair, APNs, TestFlight, production deploy, scope cut.
3. `blocked_on: Fable` for: architecture fork, security policy exception, multi-lane arbitration.
4. Distrust agent **repairs** — orchestrator re-runs gates; optional second agent asks "new adjacent bug?"
5. Preserve methodology trail — do not squash away `docs/test-runs/` or closed checklist items.

## Consumer phase (after IOU resolved)

1. Re-read the evidence note or CONTRACT at current tip when the tier requires one.
2. Re-run oracle from `oracle-matrix.md` (not just the failed sub-step).
3. If the blocker was a **class** bug, re-audit instances (grep, UITest, miss-scan).
4. Clear IOU section in `orchestrator-state.md` only after oracle PASS + evidence landed.

## Related

- Dashboard: `docs/plans/orchestrator-state.md`
- Fable brief shape: `docs/ENGINEERING_PROCESS.md` (explicit ask, blocker, verbatim evidence, done-bar)
- Parallel lanes: `lancer-parallel-handoff`
