# Bun's 7 lessons → Lancer commands

Primary source: [Bun in Rust](https://bun.com/blog/bun-in-rust). Secondary methodology audit: [7-lessons gist](https://gist.github.com/michaellady/7e63223d5d72d9ad18a03efa1f376aae). Default-deny prompts, round caps, and IOUs come from the secondary audit of Bun's workflow files, not Bun's official post.

| # | Bun technique | Lancer command / artifact |
|---|---------------|---------------------------|
| 1 | **Facts before plans** — `PORTING.md`, `LIFETIMES.tsv`, verified claims with `file:line` | Scale the artifact to risk: task done-bar for routine work, evidence note for behavioral work, full CONTRACT for high-risk work. |
| 2 | **Implementer + ≥2 adversarial reviewers** at Bun's rewrite scale | One independent review for behavioral work; two plus owner/human sign-off for high-risk work. Never forward implementer reasoning, but do provide contracts, surrounding code, and evidence. |
| 3 | **Default-deny** — `confirmed=false` unless source+target+divergence cited | Literal sentence in reviewer prompts; verdict JSON schema requires `file:line` cites. Unconfirmed claims = fail. |
| 4 | **Fix the workflow** when mistake classes repeat | Edit `docs/ENGINEERING_PROCESS.md`, Fable PASTE brief, or this skill's references — not just the one-off patch. Log the class fix in `orchestrator-state.md`. |
| 5 | **Compiler/errors as work queue; bounded rounds + IOUs** | Cap repair loops (`iou-protocol.md`); write `blocked_on:` into `orchestrator-state.md` instead of spinning. Treat build/test failures as the queue, not noise. |
| 6 | **Language-independent oracle** — TS tests on Zig then Rust | Lancer oracle stack (`oracle-matrix.md`): `lancer-verification-gate` → Simurgh lease + sim live-loop → XCUITest harness → `audit.log` → physical device 5c. Pick the lowest oracle that still falsifies the claim. |
| 7 | **Class fix, then re-audit instances** | After systemic fix (harness, dispatch, relay), re-run the finder pass (grep, UITest suite, miss-scan doc) against current `git rev-parse HEAD`. |

## What we do not copy

Peak 64-agent scale, Claude Code dynamic-workflow JS as SSOT, mechanical whole-codebase ports, Miri-specific Rust gates, or Bun-specific jargon as hard requirements.

Also do not copy Bun's missing human approval gate. Its post-merge security work found missed defects and rejected automated repairs that introduced adjacent bugs. High-risk Lancer work requires explicit owner/human sign-off.

## Quick invocation

```text
1. Pick routine / behavioral / high-risk tier
2. Record the tier-appropriate done-bar, evidence note, or CONTRACT
3. Pilot one slice before fan-out or high-risk commitment
4. Implement + self-verify
5. Review with independent context (1× behavioral; 2× + owner high-risk)
6. Orchestrator runs the union of applicable gates
7. Class bug? fix process + instance, then re-audit
8. Bound rounds; preserve durable evidence for live/security/publish claims
```
