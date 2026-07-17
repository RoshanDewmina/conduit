# Lancer engineering process — feature → merged (2026-07-10)

**Last updated: 2026-07-15.**

How every feature gets built. Applies to humans and agents. Companion:
[`plans/orchestrator-state.md`](plans/orchestrator-state.md)
(living session state) and the `swarm-orchestrator` skill (generic mechanics).
(Point-in-time Fable paste briefs were purged 2026-07-15 — git history only.)

## Model routing (owner policy, 2026-07-10 — supersedes prior CLAUDE.md tiers)

| Role | Model / tool | When |
|---|---|---|
| Orchestrate, spec, decompose, arbitrate, high-risk review | **Fable 5** (main session) | Always the brain, never the routine coder — token budget is the constraint |
| **Default coder** | **Cursor CLI · Grok 4.5 (high)** — `agent -p "<spec>" --model <grok-slug> --output-format json` | Features, bug fixes, tests, refactors. Best agentic profile per current benchmarks (Terminal-Bench 83.3, SWE-bench Pro 64.7) at $2/$6 per M tokens |
| Mechanical / small tasks + first-pass review | **Cursor CLI · Composer 2.5** | Renames, boilerplate, doc updates, test scaffolds, diff-review summaries — ~4× cheaper ($0.50/$2.50), very fast, weaker on hard problems (don't give it novel architecture) |
| Fallback + sensitive paths | **Claude Sonnet 5 (high)** via Agent tool | (a) Grok failed the gate twice on the same task; (b) work needing repo skills / XcodeBuildMCP (simulator screenshots, UI test evidence); (c) security-sensitive paths (below) |
| Verify slugs at session start | `agent models` / `agent --list-models` | Model names drift; never hard-code without checking |

**Simulator routing lane — Simurgh lease discipline** (simulator work only; required before
XcodeBuildMCP simulator operations or other `simctl` use — not physical-device builds):
call `pool_status`, then `lease_acquire` before simulator work — never pick a booted device or
raw `simctl` UDID. Route every `xcodebuild` through `simurgh exec <lease-id> -- …` so
isolation flags merge and the lease auto-renews during long builds; bare `xcodebuild` risks
mid-run reclaim. Use the returned UDID with isolated DerivedData, SwiftPM, and module-cache
bindings; for XcodeBuildMCP simulator operations, use the per-lease XcodeBuildMCP adapter bound
to that lease. Call `lease_renew` when work spans multiple steps and may outlast TTL. Confirm
`lease_status` before starting; always `lease_release` in cleanup/finally; check `pool_status`
after. One lease per parallel agent.

**Security-sensitive paths — Grok may draft, but Sonnet-5-high or Fable must review the full
diff, no exceptions:** `daemon/lancerd/dispatch.go` (+ run `vendor-cli-adapter-audit` skill),
`daemon/lancerd/policy/`, `approval.go`/content-hash code, `Packages/**/Security*`,
E2E relay protocol types, anything touching keychain/pairing/audit chain.

## The lifecycle — 11 steps, no skips

1. **Pick** the next work package from
   [`product/2026-07-10-lancer-agent-build-roadmap.md`](product/2026-07-10-lancer-agent-build-roadmap.md)
   (phase order is law; dogfood-log items outrank everything in their phase).
2. **Spec** (Fable, ≤1 page): goal · exact write-set (files) · contracts/types touched ·
   acceptance commands (the literal commands that prove done) · risk class (`low | ui | sensitive`)
   · reference implementation pointer (port map / roadmap citation). No spec, no dispatch.
3. **Branch + worktree**: `git worktree add .worktrees/<slug> -b feat/<area>-<slug> master`
   (or `agent -w <slug> --worktree-base master`). One agent per worktree; **write-sets of
   parallel agents must be disjoint** — enforced at spec time, `Package.swift`-style shared
   files land first as their own tiny commit.
4. **Implement** (routed per table). Tests land in the same PR as the code — a work package
   without tests is incomplete unless the spec explicitly waives it with a reason.
5. **Self-verify**: the coder runs the spec's acceptance commands and pastes real output.
6. **Gates** (mechanical, non-negotiable, in this order — fail = back to 4):
   - iOS: `swift test` (LancerKit) → app-target `build_sim` → affected UITests
   - Go: `cd daemon/lancerd && go test ./...`
   - Cross-cutting: `relay-approval-e2e.sh` when touching relay/approval/receipt paths
   - **Sim live-loop gate (owner rule 2026-07-11):** any user-facing PR additionally requires
     driving the affected flow end-to-end in the simulator app against a live `lancerd`
     (screenshot + runtime-log evidence in the PR). Un-simulatable (APNs registration, lock
     screen, device-only) → explicit owner greenlight instead. Sim pairing occupies the
     daemon's single relay slot — re-pair the owner's phone afterward and note it in the PR.
7. **Cross-model review (v2 — full spec: `.claude/skills/swarm-orchestrator/references/verification-pipeline.md`)**:
   a FRESH Cursor session reviews read-only — `git diff master...HEAD | agent -p "<checklist>"
   --mode=ask --model <grok-or-composer>`. The prompt includes the spec, the diff, a
   **dependents map** (rg'd call sites of every changed public symbol — review beyond the
   diff), and `docs/REVIEW_STANDARDS.md` (living rules file; every reviewer correction appends
   a rule). Output: structured verdict JSON — per-finding `severity` (blocking/major/minor/nit)
   × `confidence` (certain/likely/speculative). Blocking or major+certain = fix; minors/nits
   never block. Fix loop is bounded: ONE re-review (scoped to findings), then automatic
   escalation — never a third pass. `anthropics/claude-code-action` runs on the PR as the
   independent third reviewer; orchestrator arbitrates blocking disagreements by reading code.
8. **PR**: `gh pr create` from the branch. Body must contain: spec, gate outputs (pasted, not
   claimed), review verdict, risk class, screenshots for anything visual. Never push to `master`
   directly (docs-only commits by the orchestrator are the sole exception).
9. **Orchestrator verify** (Fable): re-run the gates itself (trust nothing), read the review
   verdict + the diff *stat*; read full diffs only for `sensitive` risk class or gate flakiness.
   A subagent's "done" without pasted evidence is not done.
10. **Owner gate** (only when risk class is `ui` or `sensitive`, or the change alters the daily
    loop): owner eyeballs the PR / TestFlight build. Everything else auto-merges after 9.
11. **Merge + clean**: merge PR, delete branch, `git worktree remove`, update
    `STATUS_LEDGER.md` current-priority table and `FEATURE_BACKLOG.md` row, log in the
    orchestrator state file. Physical-device re-proof steps go to the owner checklist.

## Branching rules

- `master` = always green, protected. Feature branches only, one work package per branch,
  small PRs (target < ~600 changed lines; split larger).
- Worktrees live under `.worktrees/`; never share one between agents; never whole-file `cp`
  across worktrees (diff/rebase only).
- Long-running lanes rebase on `master` daily; integration conflicts are the orchestrator's
  job, not the coder's.

## What "good code" means here (review bar)

Matches an existing pattern in the codebase (bridge→store→repository; don't invent pipelines) ·
compiles with zero new warnings · Swift 6 strict concurrency clean / `go vet` clean · versioned
wire types for any protocol change · fail-closed on anything mutating · no force-unwraps in
non-test code · attribution comment on any ported competitor pattern (per build-roadmap §0
license rules) · evidence pasted, never asserted.

## Token-efficiency rules (Fable-specific, owner priority)

Fable never reads what a cheaper model can summarize · specs cite `file:line`, never paste code
blocks · use `--output-format json` and parse only the final result · batch independent
dispatches in one message · continue existing subagents (SendMessage) instead of respawning ·
keep the orchestrator state file current so compaction never forces re-derivation.
