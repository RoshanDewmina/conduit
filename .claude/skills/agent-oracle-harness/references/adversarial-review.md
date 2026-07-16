# Adversarial review — risk-tiered and default-deny

Reviewers never receive implementer chain-of-thought or chat transcripts. They do receive enough independent evidence to inspect system behavior:

- diff against the integration base
- lightweight evidence note or full CONTRACT when required
- relevant surrounding callers/state/architecture and canonical security rules
- exact verification output or evidence paths

Do not send a reviewer an entire repo dump. Provide the smallest context that lets them verify the claim rather than guess from a diff.

## Default-deny rule (include verbatim in every reviewer prompt)

> Set `confirmed=false` for every finding unless you cite the changed code, the relevant contract/invariant or surrounding behavior, and the observable divergence. Speculation without evidence is rejected.

## Reviewer prompt template

```text
You are an adversarial code reviewer. Default-deny.

Input: diff + independent review context below. You do NOT have the implementer's reasoning.

Task: Find regressions, invariant violations, missing tests, security issues, and "looks fine" claims without evidence.

Rules:
1. confirmed=false unless you cite changed code, the governing invariant/behavior, and divergence.
2. Do not approve because the diff "seems reasonable."
3. Flag missing verification if the diff touches behavior but includes no test/build evidence path.
4. Sensitive paths (dispatch.go, policy/, relay, approval hashes): require the full high-risk gate and explicit owner/human sign-off.

Output: JSON matching the verdict schema below. No prose outside JSON.

--- REVIEW CONTEXT START ---
<contract/evidence note, canonical rules, relevant surrounding code, verification evidence>
--- REVIEW CONTEXT END ---

--- DIFF START ---
<paste diff>
--- DIFF END ---
```

## Verdict JSON schema

```json
{
  "reviewer_id": "reviewer-1",
  "model": "cursor-grok-4.5-high",
  "base_ref": "master",
  "verdict": "fail",
  "summary": "One-line overall assessment",
  "findings": [
    {
      "id": "F1",
      "severity": "blocker",
      "confirmed": true,
      "title": "Short title",
      "invariant_cite": "path/to/contract-or-existing:42",
      "target_cite": "path/to/changed:108",
      "divergence": "Contract requires X; diff does Y",
      "suggested_fix": "Optional — orchestrator may ignore"
    },
    {
      "id": "F2",
      "severity": "nit",
      "confirmed": false,
      "title": "Unconfirmed concern",
      "invariant_cite": null,
      "target_cite": null,
      "divergence": "Could not verify without reading full file",
      "suggested_fix": null
    }
  ],
  "verification_gaps": [
    "No XCUITest update for composer send path"
  ],
  "review_approve": false,
  "merge_authorized": false
}
```

### Field rules

| Field | Rule |
|-------|------|
| `verdict` | `pass` \| `fail` \| `pass_with_nits` |
| `severity` | `blocker` \| `major` \| `minor` \| `nit` |
| `confirmed` | `true` only with target + invariant evidence populated |
| `review_approve` | `true` only if zero `blocker`/`major` with `confirmed=true` |
| `merge_authorized` | Reviewers always return `false`; only the orchestrator may authorize merge after required gates and recorded high-risk human sign-off |

## Orchestrator gate

- Behavioral tier: require ≥1 independent reviewer.
- High-risk tier: require ≥2 independent reviewer JSON blobs (different sessions or models) plus explicit owner/human sign-off.
- Verify high-risk sign-off records approver, scope, base/head SHA, timestamp, decision, and evidence link in the CONTRACT. Any head change invalidates it.
- Any `blocker` with `confirmed=true` → return to implementer (counts toward IOU round cap).
- Orchestrator re-runs `lancer-verification-gate` after fixes — reviewer approval is not sufficient alone.

## Swarm wiring

Dispatch reviewers via Cursor CLI or Task subagent with independent review context. Use `lancer-parallel-handoff` for disjoint lanes; serialize hot files. Global swarm patterns: `~/.claude/skills/swarm-orchestrator/` (not the deleted project copy).
