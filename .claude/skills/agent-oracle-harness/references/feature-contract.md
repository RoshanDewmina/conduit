# Evidence note or feature contract

Use the smallest artifact that makes the claim falsifiable.

- **Routine:** no new artifact; state the done-bar in the task or PR.
- **Behavioral:** lightweight evidence note containing goal, base ref, key invariants, risks, and acceptance commands.
- **High-risk:** full CONTRACT using the template below before implementation.

## Location

Behavioral evidence note:

```text
docs/plans/YYYY-MM-DD-<slug>-EVIDENCE.md
```

Full high-risk contract, preferably beside the plan:

```text
docs/plans/YYYY-MM-DD-<slug>-CONTRACT.md
```

Or at feature root for small slices:

```text
docs/plans/YYYY-MM-DD-<slug>/CONTRACT.md
```

## Lightweight evidence note

```markdown
# EVIDENCE — <feature slug>

**Base ref:** `<sha>`
**Goal:** <one checkable outcome>
**Invariants:** <short cited list>
**Risks:** <affected risk classes from oracle-matrix.md>
**Acceptance:** <exact commands and live/screenshot evidence>
```

## Full CONTRACT template

```markdown
# CONTRACT — <feature slug>

**Date:** YYYY-MM-DD
**Owner:** <name or agent session id>
**Base ref:** `git rev-parse HEAD` at contract time
**Plan:** link to Plan.md if separate

## Goal (one sentence)

<What user-visible outcome ships?>

## Non-goals

- <Explicit exclusions>

## Call-site inventory

| Area | File:line | Role |
|------|-----------|------|
| | | |

## Invariants (must not regress)

1. <Invariant> — cite `file:line` or doc
2. ...

## Acceptance commands (done-bar)

Run these in order; paste stdout in PR / `docs/test-runs/`:

1. `<exact command or MCP tool>`
2. ...

## Oracle tier

From `oracle-matrix.md`: <e.g. sim live-loop + XCUITest>

## Risks / sensitive paths

- [ ] dispatch.go
- [ ] relay / pairing
- [ ] approval / policy
- [ ] other: ___

## Evidence trail

`docs/test-runs/YYYY-MM-DD-<slug>/`

## Decision log

| Date | Decision | Rationale |
|------|----------|-----------|
| | | |

## High-risk owner/human sign-off

Required before merge or publish for high-risk work:

| Approver | Decision | Scope | Base SHA | Head SHA | Timestamp | Evidence |
|---|---|---|---|---|---|---|
| | approve / reject | | | | ISO-8601 | link to review/device evidence |
```

## Rules

1. Every invariant should cite `file:line` or a canonical doc — no ungrounded claims.
2. Done-bar must be **checkable** (a command, test name, or screenshot path) — not "should work."
3. For high-risk work, if inventory is incomplete, stop and explore before implementing.
4. CONTRACT updates when scope shifts; bump `Base ref` and log in Decision log.
5. High-risk sign-off is valid only for the recorded scope and exact head SHA; a later code change requires renewed sign-off.

## Handoff

- Plan session produces the tier-appropriate evidence note or CONTRACT alongside Plan.md (`agent-feature-loop`).
- Implement session reads it first; reviewers receive it plus relevant code and evidence, but never implementer reasoning or chat.
