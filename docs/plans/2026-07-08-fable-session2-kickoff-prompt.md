# Prompt: Fable session 2 — Lancer Layer 4+ kickoff

**For Milroy — read this box, then copy everything below `=====` into a fresh Fable session.**
Starting a new chat makes sense here: the first session's context is already large (two planning
docs, a multi-bug debugging pass, a full report), and everything load-bearing from it is now
captured in files rather than chat memory — this doc, the updated
`2026-07-08-lancer-layer-4-6-lane-proposal.md`, and the original
`2026-07-07-fable-cursor-orchestration-prompt.md` are the persistent record. A fresh session
reading those three plus the repo's own entry points should need nothing carried over from the old
chat.

I proposed a priority order below (see "Suggested priority") — it's a draft, reorder or rewrite it
before sending; I don't know your actual constraints (time, what you want demoable when) well
enough to lock it for you.

=====

You are Fable, continuing the Lancer orchestration work from the first session — new chat, same
mandate. Read, in order: `docs/plans/2026-07-07-lancer-build-sequence-and-hands-free-layer.md` →
`docs/plans/2026-07-07-lancer-layers-0-3-implementation-spec.md` →
`docs/plans/2026-07-07-fable-cursor-orchestration-prompt.md` (your operating rules — model tiering,
dispatch mechanics via `cursor-agent`, verification discipline, hard constraints; all still in
force, not restated here) → `docs/plans/2026-07-08-lancer-layer-4-6-lane-proposal.md` **(the
current source of truth for scope — read its "Owner decisions — answered 2026-07-08" section
first, then the lanes above it)** → `AGENTS.md` → `ARCHITECTURE.md` §0.1/§4.1 →
`docs/AGENT_READ_FIRST.md` → `docs/STATUS_LEDGER.md`. Then re-verify current state against
`git log`/`git status` before dispatching anything — don't trust any doc's claims, including this
one, over the live repo.

## What changed since the first session (context, not new instructions)

Layers 0–3 are built and merged (`spec/receipt-daemon`, `spec/receipt-ios`, `spec/home-attention`,
`spec/siri-entities`), plus a separate debugging pass found and fixed three stacked relay/iOS bugs
that were causing silent approval-delivery loss. Ten commits sit on
`codex/user-ready-tier0-tier1-2026-07-07`, possibly still unpushed — check and push/PR if so.
**D0.2 (owner physical-device run) may or may not be done yet — check
`docs/test-runs/` for a result before assuming it's still open; it was the one gate blocking
Layers 0–3 from being fully closed.**

The Layer 4+ scope changed from the first proposal: Lane F (Return-to-Desk) is paused — spec kept,
do not dispatch. Two lanes were added: Lane H (Proof Reel, structured-replay only, elevated to a
priority feature, not interview-gated) and Lane I (iOS 27 App Intents, approved to start now
rather than waiting for September — single-app/availability-gated architecture, deployment target
stays iOS 26). Watch embedding is cut from scope entirely, not just deferred. Full detail, write-sets,
and acceptance commands for all of this are in the updated proposal doc — this section is a pointer,
not a restatement.

One thing worth your attention specifically: **Lane I1 asks you to check whether the already-built,
device-tested Siri Phase 2 branch (`cursor/siri-phase2-fixes-9257`, PRs #16/#24) can be re-landed
now under `@available(iOS 27, *)` without raising the deployment target**, rather than assuming the
existing repo note ("revisit when deployment target moves to 27.0+") is still correct. If it
re-lands cheaply, that's real progress before any new iOS-27 code gets written.

## Suggested priority (Milroy: confirm or reorder before sending)

1. L0 leftovers (A4, D2, D3, deep-link fix) — small, mostly done except this, unblocks Siri.
2. Lane I1 — resurrect the Siri Phase 2 branch. Possibly near-free; check first.
3. Lane H (Proof Reel structured replay) and Lane I3 (new iOS 27 App Intents surface) in
   parallel with each other and with #4 below — both are now headline/marketing-relevant and
   don't obviously block each other.
4. Lane E (Question Cards) and Lane G (ship actions, non-merge) — the core Layer 4 buildout,
   parallel to each other if write-sets stay disjoint from #3.
5. Lane I4 — the Live Activity/Dynamic Island confirmation pass (cheap; these already work, this
   is verification, not build) — can run anytime, doesn't block or get blocked by anything else.

Report back at the same cadence as before: layer/lane boundaries, exit-bar results with actual
command output, and the running Composer/Sonnet/Fable-direct tally.
