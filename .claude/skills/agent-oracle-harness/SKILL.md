---
name: agent-oracle-harness
description: Use when closing non-trivial Lancer features, running publish-readiness miss-scans, proving live behavior through Simurgh or a physical device, or re-auditing systemic failures.
---

# Agent Oracle Harness

## Overview

Apply Bun's strongest transferable lesson: match independent evidence to the risk of the claim. This skill extends — not replaces — `lancer-verification-gate`, parallel handoff patterns, and Fable orchestration (`docs/plans/orchestrator-state.md`, `docs/ENGINEERING_PROCESS.md`). For swarm dispatch mechanics, use the global `swarm-orchestrator` skill (`~/.claude/skills/`) or `lancer-parallel-handoff`; do not depend on a deleted project-local copy.

## When to invoke

- Closing a non-trivial or cross-system feature
- Owner asks "are we done?" or wants a publish miss-scan
- Post-fix re-audit after a systemic/class bug
- Sim dogfood proof or oracle-pilot scoring
- Repeated agent mistakes → fix the workflow, not just the instance

## When NOT to use

- Copy/layout-only UI change with an obvious build or screenshot bar → `lancer-verification-gate` alone
- One-line fix with known file and verify command → `lancer-verification-gate` alone
- Pure doc typo / status-line update
- Plan-only discovery → `agent-feature-loop` (this skill joins at milestone verify)
- "Give me the next prompt" only → global `prompt-crafting` in `agent-brief` mode

## Choose the rigor tier first

| Tier | Typical work | Required preparation | Review | Evidence |
|------|--------------|----------------------|--------|----------|
| **Routine** | Copy/layout, docs, isolated low-risk logic | No contract; state the checkable done-bar | Existing review policy | `lancer-verification-gate`; screenshot when visual |
| **Behavioral** | User-facing flow, persistence, composer/send, multi-file feature | Lightweight evidence note from `feature-contract.md` | 1 independent reviewer with context | Strongest applicable sim/test/build gates |
| **High-risk** | Security, policy, relay, pairing, approvals, destructive operations, publish/Tier 0, cross-system invariants | Full `CONTRACT.md` | ≥2 independent reviewers **and explicit owner/human sign-off** | Union of every applicable gate, including live/device evidence |

If risk classes overlap, use the **union** of their gates in `oracle-matrix.md`, not one convenient row.

## Evidence loop

1. **Facts** — record the checkable claim, current base ref, invariants, and acceptance evidence at the tier above.
2. **Pilot when warranted** — before fan-out or a risky architecture commitment, take one thin slice or known bug through the real oracle.
3. **Implement** — use the repo's authorized implementation workflow; isolate parallel or collision-prone work.
4. **Independent review** — exclude implementer reasoning and chat, but include the diff, contract/evidence note, relevant surrounding code and canonical security/architecture rules, plus verification evidence. See `references/adversarial-review.md`.
5. **Oracle** — the orchestrator independently re-runs `lancer-verification-gate` plus the union of matching sim/device bars from `references/oracle-matrix.md`.
6. **Human gate** — high-risk changes cannot merge or publish on agent approval alone.
7. **Class vs instance** — fix the immediate defect; if it represents a class, fix the process/codegen/harness and re-audit all instances at the new tip.
8. **Bound and trail** — cap repair rounds per `references/iou-protocol.md`. Land durable `docs/test-runs/<date>-<slug>/` evidence for live, device, security, and publish claims; routine changes do not need a new evidence directory.

## Reference map

| File | Loads when |
|------|------------|
| `references/bun-lessons.md` | Mapping Bun's 7 lessons to Lancer commands |
| `references/adversarial-review.md` | Reviewer prompts + verdict JSON schema |
| `references/feature-contract.md` | CONTRACT.md template (facts before plan) |
| `references/oracle-matrix.md` | Which oracle for which risk class |
| `references/iou-protocol.md` | Round caps + IOU escalation |

## Related skills

- Verify matrix: `lancer-verification-gate`
- Plan/implement split: `agent-feature-loop`
- Parallel lanes: `lancer-parallel-handoff`
- Publish lens (regenerate): `docs/product/2026-07-15-publish-oracle-audit.md`
- Orchestrator dashboard: `docs/plans/orchestrator-state.md`

## Reporting

Report: rigor tier, evidence note/CONTRACT path when required, pilot oracle if used, reviewer verdicts, human sign-off for high-risk work, orchestrator re-gate result, round count, evidence path, and any `blocked_on:` IOUs written.

Do not claim "done" from implementer or reviewer self-reports alone — the orchestrator oracle pass is mandatory.
