# Task: redesign Onboarding, implement directly in SwiftUI

Lancer is mobile mission control for AI coding agents (Claude Code, Codex,
OpenCode, Kimi) running on the user's own machine via a resident daemon. The
phone steers and approves; it is not a phone IDE.

**Attached separately:** the consolidated design-audit report (also in-repo
at `docs/design-audit/2026-07-01-final-report-and-next-steps.md`, which
links every underlying doc — the original audit packet, all six per-workflow
findings docs, the Mobbin research log, and the independent verification
pass) and the project's design system. Read both before starting.

**Then explore the codebase yourself** — don't rely on prose descriptions
here. Start with `AGENTS.md` and `ARCHITECTURE.md` §0.1/§4.1 for product
ground truth, then `Packages/LancerKit/Sources/OnboardingFeature/` for the
actual onboarding implementation, and the real current-state screenshots in
`docs/design-audit/screenshots/current/`.

## Scope

Six workflows are queued for this redesign pass: Onboarding → Work Thread →
Review/Approvals → Machines → Home & Settings. **Start with Onboarding only**
— the others are context, not today's task.

## The problem (Onboarding step 1 — "Value + Pair")

Both audits agree on two real issues, detailed in the workflow doc
(`docs/design-audit/workflows/01-onboarding-pairing.md`):

1. The user never sees the actual product before being asked to trust it
   with machine access — the current value-proposition content is abstract,
   not proof.
2. Pairing failures are easy to miss — the error isn't visually tied to the
   code field it explains.

How you solve both is genuinely open. The workflow doc has ideas already
considered (not decided, not the only options) if you want a starting
point — but propose your own if you see something stronger.

## If you want more reference material

Use the Mobbin MCP yourself and decide what's actually useful — don't just
carry over the citations already in the workflow doc without checking they
still apply.

## Before you write any code

Ask me whatever clarifying questions you have.

## Verification (don't skip)

This repo's bar for "done": the XcodeBuildMCP app-target simulator build,
not just `swift build` (which silently skips `#if os(iOS)` code and will
false-green real bugs). See the `lancer-verification-gate` skill and
`docs/agent-contract.md` before claiming anything works.
