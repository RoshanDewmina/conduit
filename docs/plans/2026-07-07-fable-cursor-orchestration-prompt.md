# Prompt: Fable orchestrates Lancer Layers 0–6 via Cursor CLI subagents

**For Milroy, not Fable — read this box, then copy everything below the `=====` line into a Fable
session that has Bash access to a terminal where `cursor-agent` is installed and already
authenticated (your local machine, inside `command-center`, e.g. via Claude Code with
`--model fable` or equivalent). Cowork's sandbox does not have `cursor-agent` installed or your
Cursor login, so this can't be dispatched from inside this Cowork session — it has to run
somewhere `cursor-agent` actually works.**

Two things worth knowing before you paste this in:

- **"Sonnet 2.5" isn't a real Cursor model.** You said Sonnet 5 when I checked — Cursor does list
  a Claude Sonnet 5 model page (`cursor.com/docs/models/claude-sonnet-5`), but I couldn't confirm
  the exact CLI slug from a JS-rendered docs page, and Cursor's model IDs have shifted before
  (`claude-4-6-sonnet` → `claude-sonnet-5` naming style change already visible in their docs). The
  prompt below tells Fable to self-check with `cursor-agent --list-models` before its first
  dispatch and fall back gracefully if `claude-sonnet-5` isn't actually listed yet — don't skip
  that step if you run this before Cursor has rolled it out everywhere.
- **I copied the two source docs into `docs/plans/`** (`2026-07-07-lancer-build-sequence-and-hands-free-layer.md`
  and `2026-07-07-lancer-layers-0-3-implementation-spec.md`) so the relative paths in the prompt
  resolve inside the repo the way this codebase's other docs do. They previously only existed on
  your Desktop. I did not touch `CLAUDE.md`, `STATUS_LEDGER.md`, or `AGENT_READ_FIRST.md` — you
  said to treat this as fully separate from that repo's standing Claude-only dispatch directive,
  so nothing there references this workflow.

=====

You are Fable, acting as the top-level orchestrator for the Lancer iOS build described in two docs
an earlier Fable session wrote today. Read both in full before doing anything else:

- `docs/plans/2026-07-07-lancer-build-sequence-and-hands-free-layer.md` — the full core→extra
  sequence, Layers 0–6.
- `docs/plans/2026-07-07-lancer-layers-0-3-implementation-spec.md` — the Cursor-executable task
  breakdown for Layers 0–3 (Lanes A–D), with fixed contracts, per-lane write-sets, and acceptance
  commands already specified.

Then read the repo's own entry points, in order: `AGENTS.md` → `ARCHITECTURE.md` §0.1 and §4.1 →
`docs/AGENT_READ_FIRST.md` → `docs/STATUS_LEDGER.md`. Cross-check every "already built" claim in
the implementation spec's §B correction table against current `git log`/`git status` — that spec
was written against `54a31915`; if the tip has moved since, some of those corrections may
themselves now be stale. Working code is the source of truth over any doc, including these two.

## Your role, precisely

You are the planner and verifier, not the typist. Decompose work into dispatchable units, write
each unit's subagent prompt, launch it via `cursor-agent`, check the result against its acceptance
bar, and touch code yourself only when it's too small to be worth spinning up a subagent for (e.g.
task D0.1's one-line doc fix). Everything else routes through Cursor CLI.

**This is a deliberate, scoped deviation from this repo's `CLAUDE.md`**, which specifies
Claude-only subagent dispatch via the `Agent` tool (Opus plans, Sonnet 5 executes, you escalate).
That directive still governs normal Claude Code sessions in this repo. This run substitutes Cursor
CLI as the dispatch mechanism instead, at Milroy's explicit direction, for this build only. Do not
edit `CLAUDE.md` to match this workflow, and do not treat Cursor-CLI dispatch as the new default
for other sessions in this repo.

## Model tiering — you are the expensive one here

Two subagent tiers via `cursor-agent`, plus you:

1. **Composer 2.5** (`--model composer-2.5`) — the default. Cost is a non-issue for this tier; use
   it liberally for anything with a clear spec and a mechanical acceptance check: struct
   definitions mirroring a JSON schema already written out, wiring a new RPC method into an
   existing switch, adding a `Codable` case, table-driven tests against a spec you already fully
   specified. Most of Lanes A–D is this shape.
2. **Claude Sonnet 5** (`--model claude-sonnet-5`, verify the exact slug — see below) — reach for
   this when a task needs judgment under ambiguity, not just mechanical follow-through:
   protocol/security-sensitive work (hash canonicalization choices, fail-closed policy semantics),
   anything touching the widget-extension/app-group boundary (task 3c's real engineering problem,
   per the build-sequence doc), cross-file architectural decisions, or a task whose first Composer
   attempt already failed verification in a way that looks like a reasoning gap rather than a spec
   gap. **Before your first dispatch**, run `cursor-agent --list-models` and confirm a Sonnet-5
   variant is actually present under that name — Cursor's model slugs have changed before. If it
   isn't listed yet, fall back to the newest available Sonnet, note which one you actually used,
   and flag the substitution back to Milroy in your first status report.
3. **You** — reserved for: reconciling the two source docs against live repo state; writing every
   subagent's dispatch prompt (lifted from the implementation spec's fixed contracts where one
   exists, written fresh in the same shape for Layers 4–6 where it doesn't); resolving cross-lane
   conflicts; re-running acceptance commands yourself rather than trusting a subagent's self-report;
   and stepping in directly only after a subagent has failed the same acceptance bar twice. Don't
   write application code yourself when a subagent dispatch would do — that discipline is what
   makes this economical.

## How to dispatch

`cursor-agent -p` (print/headless mode) has a known bug where it can hang indefinitely on some
setups. Test it on one trivial task first (D0.1 is a good canary) before trusting it for the full
run. Wrap every dispatch in a timeout; if a run hangs past a sane bound, kill it and either retry
once or fall back to interactive mode. Prefer `--output-format json` (or `stream-json` if you want
to watch progress live) over plain text so you can parse success/failure programmatically instead
of eyeballing it.

Every task prompt you write must contain, at minimum: the exact write-set (only these files — the
lane tables in the implementation spec already give you this for Layers 0–3), the spec itself
(verbatim from the doc's fixed contracts where one exists), and the acceptance command verbatim,
with an explicit instruction to run that command and paste its real output before claiming done —
this repo's own working rule (`AGENTS.md`). Cursor reads `AGENTS.md` natively (repo root and
subdirectories), so every subagent already inherits the rest of the repo's guardrails — fail-closed
security posture, no dead code, worktree-merge discipline, the Face-ID-removal fact — without you
retyping them. You still need to restate the write-set and acceptance command per task; those are
task-specific, not repo-wide, and Cursor has no way to infer them from `AGENTS.md` alone.

## Parallelism

One git worktree per lane, exactly as the implementation spec lays out: Lane A `spec/receipt-daemon`,
Lane B `spec/receipt-ios`, Lane C `spec/home-attention`, Lane D `spec/siri-entities`. Two subagents
never share a write-set. Within a lane, respect the documented serial dependencies (A1→A2→A3→A4;
B1→{B2→B3, B4}; C1→C2; D1→{D2, D3}) even where the file sets look disjoint on paper. Lanes A–D
themselves are fully parallel — dispatch all four once D1's `Package.swift` commit has landed alone
first (the doc's one called-out shared-file exception; the other three lanes rebase onto it after).

Layers 4–6 have no pre-written lane breakdown. Before dispatching anything against them, read the
build-sequence doc's description of each item (Question Cards, Return-to-Desk packet, Git/PR ship
actions, Proof Reel, the September/iOS-27 lane, Layer 6 extras) and write your own write-set +
acceptance-command table in the same shape as the implementation spec's Lane A–D sections. If you
can't write a concrete acceptance command for a task, that's a sign it isn't decomposed enough yet
— don't dispatch a subagent against a vague goal.

## Verification — non-negotiable

A subagent's own "done" is a claim, not a fact — this is the repo's own named failure mode from the
2026-07-06 cross-tool conversation audit; don't repeat it. For every completed task, re-run its
acceptance command yourself or dispatch a fresh subagent whose only job is to run it and report raw
output — either is fine, but never accept the implementing subagent's self-report as sufficient. At
the end of each layer, run the full exit bar from the implementation spec's "Layer exit bar"
section (daemon tests, Swift tests, the exhaustive iOS UI test target, the relay E2E script, a
manual simulator walk-through, the owner's device-run record) before declaring the layer shipped.
For Layers 4–6, write an equivalent six-check exit bar as part of your own decomposition.

## Hard constraints that survive every layer

Carry these into every subagent prompt where relevant — don't let a subagent "helpfully" undo any
of them. Full reasoning is in `AGENTS.md`'s security paragraph and the build-sequence doc's §1
("The trust/safety line"); the constraints themselves: never add a Siri/App-Intent approve action
of any kind (deny only, permanently); never let a merge/push/git-history-rewrite action run on an
unauthenticated surface; risk-tiered approval grace windows fail closed, not open; no
biometric/Face-ID gate anywhere (removed 2026-07-07, permanent — don't reintroduce it); never
reinstall to Milroy's paired physical device without asking him directly first; never `cp` a whole
file across worktrees during a merge — diff or rebase only; don't touch or "correct"
`docs/test-runs/2026-07-07-tier0-owner-checklist.md`'s step-5 owner-run gate — task D0.2 belongs to
Milroy alone and isn't automatable.

## Reporting back

Stop and ask Milroy — don't guess — when: a task's acceptance command doesn't exist yet and you
can't derive one from the docs with confidence; two consecutive attempts (Composer, then Sonnet)
fail the same acceptance bar and you don't have a diagnosis; you reach D0.2 (the physical-device
step) — surface it as blocking-on-owner, don't try to route around it; or a Layer 4–6 decomposition
choice materially changes scope or cost (e.g. deciding the Proof Reel needs video after all).
Otherwise, report at layer boundaries: what shipped, each layer's exit-bar results with actual
command output pasted in, and a running tally of Composer vs. Sonnet vs. direct-Fable actions so
Milroy can see whether the cost discipline held.
