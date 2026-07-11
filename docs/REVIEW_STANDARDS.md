# Review standards (living doc)

Seeded 2026-07-11 from `ENGINEERING_PROCESS.md` "What good code means". **Protocol:** every
reviewer correction by the owner or orchestrator appends a rule here (dated, one line, with the
PR/commit that motivated it). Review quality must compound; rules are never deleted, only
superseded with a strikethrough + pointer.

## The bar (all risk classes)

1. Matches an existing pattern in the codebase (bridge→store→repository; don't invent pipelines).
2. Compiles with zero new warnings.
3. Swift 6 strict concurrency clean / `go vet` clean.
4. Versioned wire types for any protocol change.
5. Fail-closed on anything mutating.
6. No force-unwraps in non-test code.
7. Attribution comment on any ported competitor pattern (build-roadmap §0 license rules;
   Orca MIT / Omnara Apache-2.0 = portable with attribution; Happier = patterns only).
8. Evidence pasted, never asserted.
9. UI copy states what was **asked of the agent**, never what is "guaranteed".
10. Never report "all clear" from stale relay data — surface staleness explicitly.

## Standing pipeline constraint — subscription-only billing (owner, 2026-07-11)

No pay-per-use API keys anywhere in the pipeline, ever. Every model call rides the owner's
existing Cursor Ultra or Claude subscription. Any tool requiring metered billing → propose a
subscription-backed alternative and ask the owner. (This is why CI review runs cursor-agent
with `CURSOR_API_KEY`, not an Anthropic API key.)

## Reviewer output contract

Emit structured verdict JSON — one finding per entry:

```json
{"findings": [{"file": "...", "line": 0, "severity": "blocking|major|minor|nit",
  "confidence": "certain|likely|speculative", "summary": "...", "evidence": "..."}],
 "verdict": "approve|fix-then-merge|reject"}
```

- Never a numeric self-score.
- **Noise budget:** `nit` and `minor` never block a merge. `blocking` requires
  `certain|likely` confidence; a `speculative` blocking claim must include a repro command.
- Fix loop is bounded at ONE re-review; after that, escalate to the orchestrator — never a
  third pass.
- Reviews get a **dependents map**: the call sites of every changed public symbol are included
  in the review prompt (rg output), so review reasons beyond the diff.

## Risk classes → deep-review routing

| Class | Paths / nature | Deep review |
|---|---|---|
| `sensitive` | `daemon/lancerd/dispatch.go`, `policy/`, approval/content-hash, `Security*`, relay protocol | Full diff by strongest model (Sonnet/Fable), mandatory; `dispatch.go` also requires `vendor-cli-adapter-audit` |
| `ui` | User-visible screens/copy | Owner eyeballs the app, batched |
| `low` | Docs, tests, mechanical refactors | Auto-merge when stages 1–4 clean |

## Appended rules

- 2026-07-11 (owner correction, dogfood round 2): **sim live-loop gate.** A feature PR without
  end-to-end simulator evidence against a live daemon (screenshot + runtime log of the actual
  flow) is NOT mergeable, regardless of green builds/tests — un-simulatable features need an
  explicit owner greenlight instead. Three UI lanes merged "green" on 2026-07-11 while send,
  follow-up, and streaming were broken live; builds and unit tests cannot stand in for driving
  the flow.

- 2026-07-11 (PR #70, Opus CI reviewer correction): validity/expiry guards on policy rules must
  be **effect-aware** — on corrupt/unparseable data, an allow rule becomes inactive but a deny
  rule stays active. "Fail closed" means failing toward the more restrictive outcome per rule
  effect, not uniformly skipping the rule.

- 2026-07-11 (Phase 0 repair, `1c102940`): before committing, verify `git status` shows the
  files you expect as *modified*, not the whole tree as untracked — a wiped index silently
  produces an empty-tree commit that records deletion of every file. `git cat-file -p HEAD`
  tree `4b825dc642cb...` is the empty-tree signature.
