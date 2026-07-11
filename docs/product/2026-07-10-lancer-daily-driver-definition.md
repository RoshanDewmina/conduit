# Lancer — daily-driver product definition (owner session, 2026-07-10)

**Status: OWNER-CONFIRMED direction.** This supersedes the *framing* of the 07-07 verdict/roadmap
docs and the Jul 21 validation gate. It does not change architecture or backend scope.
Agents: read this before citing any strategy doc dated before 2026-07-10.

---

## How this was decided

Owner Q&A, 2026-07-10. Key admissions, verbatim in spirit:

1. **Contact with reality: none.** No external users, no interviews, and the owner does not
   dogfood daily. The Jul 21 gate (10 contacted / 5 repeat / 3 paying / 1 team) has zero
   evidence behind it.
2. **Why no daily use:** "it's not there yet" — but "usable" was never defined, which let the
   bar drift (chat parity → polish → shell rebuild → scorched wipe, each moving dogfood further away).
3. **Core loop (owner-picked):** full chat-driven agent from the phone. Chat is the **vehicle**,
   not the wedge — the strategy docs were right that chat depth is commoditized, but wrong to
   conclude the product can avoid it. Nobody drives an agent through approve buttons alone.
4. **Origin differentiator (the honest one):** owner uses OpenCode; Omnara didn't support it;
   owner wanted agents on **his own machines under his own subscriptions**, not a hosted wrapper.
   "Governance wedge" (06-24) and "proof wedge" (07-07) were post-hoc narratives layered on this itch.
5. **The fork, decided: personal daily-driver first.** Not a startup yet. Not a portfolio piece.
   Success metric for the next 60 days is binary: *did the owner dispatch and review real work
   through Lancer today?*
6. **Rebuild path, decided (owner, later in session, supersedes the earlier "hybrid" answer):
   keep the current frontend.** The W0.A shell on `feat/chat-overhaul-w0a` is "pretty good, just
   needs finesse." The scorched-wipe worktree (`feat/frontend-scorched-wipe`, uncommitted) is
   **abandoned — do not resume it**. The scorched-wipe HANDOFF doc was superseded by this doc
   and deleted in the 07-10 purge; no agent may delete frontend chrome without a fresh owner ask.

---

## Differentiation (owner addendum, later in session)

**The reason to choose Lancer over Omnara / Orca / Happier: they are remote chat windows — built
for watching your agent. Lancer is built for the time you're NOT watching.** The substance is the
governance layer none of them has (policy + risk tiers + content-hash approvals + hash-chained
audit + fail-closed + atomic kill switch); the surface is the deepest iOS-native integration
(lock screen, Live Activities, Siri/App Intents, Spotlight — act without opening the app).
The two are load-bearing on each other: hands-free is only safe because of governance; governance
is only felt through hands-free. Tagline candidate: **"Don't watch your agents — govern them."**

Consequences (owner-directed): deep iOS/Siri integration is core identity, not a deferred lane.
The 26-safe Siri slice (entities, status/deny/pause/stop, voice-answer — already merged) moves
to **Phase 2**. The iOS-27-gated deep layer (LongRunningIntent dispatch, semantic search,
Foundation Models copilot) cannot ship before GA (~Sept 14) — Phase 3 preps in August and ships
day-one at GA as the launch story. Caveat: thesis must survive the dated competitive re-check
(all three competitors are OSS and moving; Omnara ships a Watch app).

## One-sentence definition

> Lancer lets me drive, approve, and review the AI coding agents running on my own machines —
> any vendor, my own subscriptions, from my phone, with a governed kill-switch-and-approval
> layer I actually trust.

## Target user & job-to-be-done

**Initial target user: the owner.** Generalized later (only with usage evidence): developers who
run multiple CLI coding agents (OpenCode, Claude Code, Codex, Kimi) on their own hardware under
their own subscriptions, and are away from the desk while work is in flight.

**JTBD:** "When agent work is in flight and I'm not at my desk, let me keep it moving — answer,
approve, steer, stop — from my phone, and let me trust what happened while I wasn't looking."

## Core user journey (MVP)

```
desk: start agent work (or dispatch from phone)
  → leave
  → push arrives (approval / question / failure / done)
  → open thread, read context in chat
  → approve/deny (incl. lock screen) · answer · follow-up turn
  → agent continues on the Mac
  → return: thread shows what happened; continue on desktop (copyable resume command)
```

## MVP (dogfood bar — nothing else until owner uses it daily)

| # | Piece | State |
|---|-------|-------|
| 1 | Pairing + trusted machines | engine kept; minimal UI |
| 2 | Thread list, needs-you-first ordering (basic) | attention model exists; simple list UI |
| 3 | Chat thread: multi-turn continue, markdown, streaming, tool cards, **inline approval card** | landed on W0.A — finesse, don't rebuild |
| 4 | Composer: prompt + agent/model/machine pick | engines exist |
| 5 | Push approvals incl. lock-screen approve/deject | proven on device 07-08; re-prove on tip |
| 6 | Emergency stop | daemon latch merged |

**MVP exit bar:** owner completes the full journey on a physical phone with a real task,
5 days out of 7, without reaching for the laptop to unblock the agent.

## Explicitly excluded from MVP (backend stays; UI/effort deferred)

Receipt card UI (daemon keeps emitting `lancer.proof/v0`; surface in Phase 2) · Proof Reel ·
Return-to-Desk screen · all Siri/App Intents work · Live Activity polish · iOS 27 lane ·
CoreSpotlight · git/PR ship-action UI · voice answer · question **Ladder** UI (plain question
cards stay) · Watch (cut 07-08) · hosted-cloud (V2) · pricing/billing/StoreKit reconciliation ·
team tier · Away Launch Composer contract chips.

## Feature disposition (important? phone-better? strengthens loop? when?)

| Feature | Important problem | Phone meaningfully better | Strengthens core loop | Verdict |
|---|---|---|---|---|
| Chat multi-turn | yes — driving is the loop | yes (away) | is the loop | **NOW** |
| Push + lock-screen approvals | yes — unblocking | yes, uniquely | yes | **NOW** |
| Emergency stop | yes — trust floor | yes | yes | **NOW** |
| Question cards (plain) | yes — agents block on questions | yes | yes | **NOW** |
| Needs-you ordering (basic) | yes at >2 threads | yes | yes | **NOW (simple)** |
| Receipt card | yes — trust the result | yes | yes, after usage exists | **LATER (Phase 2)** |
| Contract chips on dispatch | medium | neutral | with receipts | **LATER** |
| Live Activities | yes — glanceable away-state | yes | yes (hands-free wedge) | **PHASE 2** |
| Siri Phase 1 (26-safe: entities, status/deny/pause/stop, voice-answer) | yes — wedge surface | yes, uniquely | yes | **PHASE 2 (already merged; polish + dogfood)** |
| Deep Siri (iOS 27: LongRunningIntent, semantic search, FM copilot) | wedge headline | yes | yes | **PHASE 3 — Apple-gated to ~Sept 14 GA; prep Aug** |
| Return-to-Desk packet | medium | no — desk feature | marginal | **LATER** |
| Proof Reel | low | no | no | **NEVER (v0 form)** |
| Ship actions (merge from phone) | dangerous > useful now | questionable | no | **LATER/maybe NEVER** |
| Voice answer / Ladder | low | mixed | no | **LATER** |
| Team/compliance/pricing | not yet a product | — | no | **POST-FORK only** |
| Watch, hosted-cloud | — | — | — | **CUT / V2 (unchanged)** |

## Major risks

1. **Process thrash (highest).** Solo owner + agent swarm produced 3 wedge pivots, a rebuild,
   and a same-day scorched wipe in one week. Mitigation: this doc is the scope freeze; owner
   changes it, agents don't; daily dogfood is the regression signal.
2. **Definition drift on "usable."** Mitigated by the MVP exit bar above — it is checkable.
3. **Competitive erosion of the own-stack gap.** Omnara is OSS and could add OpenCode any week;
   Orca/Happier were unknown at project start. Action: dated competitive re-check from
   `research-repos/` clones before any product-fork decision.
4. **Chat-parity treadmill.** Chat is table stakes, not the wedge — polish stops at "owner can
   work," not "matches Omnara."
5. **Premise risk.** If after a working MVP the owner still doesn't reach for it, that is
   *signal about the product premise*, not an execution failure. Log it honestly.
6. **Git fragility right now.** The abandoned wipe sits uncommitted on a worktree; W0.A rides a
   stash + checkpoint branch; a stale handoff doc still tells agents to continue the wipe. One
   wrong cleanup — or one obedient agent — loses days. Phase 0 exists to defuse this.

## Validation plan (replaces the Jul 21 gate)

- **Weeks 1–4: personal usage log** (a small `docs/dogfood-log.md`): per day — dispatches,
  approvals from lock screen, follow-up turns from phone, and every moment the owner reached
  for the laptop instead (each is a bug or a scope insight).
- **Competitive re-check** (dated, from the local clones + fresh web): does anyone now cover
  own-subs + own-machines + OpenCode + governed approvals?
- **Only after ≥4 weeks of genuine retention:** revisit the fork (product vs tool). Outreach to
  ~5 own-stack developers happens then, not before. Pricing work stays frozen until then.

## Phased roadmap

- **Phase 0 — git hygiene (a day).** Land the in-flight W0.A work on `feat/chat-overhaul-w0a`
  (commit or stash-pop deliberately); remove the wipe worktree (`git worktree remove`, delete
  `feat/frontend-scorched-wipe`) or park it clearly as abandoned; mark the 07-10 wipe HANDOFF
  superseded; `build_sim` green on the kept frontend.
- **Phase 1 — dogfood MVP (weeks 1–2).** The 6 MVP pieces; re-prove Tier 0 + 5c on tip; owner
  starts the daily log. Fix only what the log surfaces.
- **Phase 2 — hands-free + trust surfaces (weeks 3–4).** The wedge made visible: Siri Phase 1
  polish (26-safe slice, already merged) + Live Activities into the daily loop; receipt card +
  contract echo (backend already done); needs-you ordering matured; whatever the log demanded.
- **Phase 3 — Sept lane + the fork (Aug–Sept).** Prep the iOS-27 deep-Siri layer in August
  (LongRunningIntent dispatch, semantic search, FM copilot — Apple-gated), ship day-one at GA
  (~Sept 14) as the launch story. In parallel, with usage evidence + competitive re-check,
  revisit the fork: product (govern-don't-watch wedge → outreach & pricing) or tool
  (open-source/portfolio framing).
