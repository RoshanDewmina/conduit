# Lancer — V1 Validation Cycle (kill-or-continue test)

> Created 2026-06-24. Source: the verdict memo on the ChatGPT deep-research report. This is the
> **decision gate** for whether to continue Lancer as a paid niche utility or sunset it. It is a
> *validation* phase, not a feature phase — do not build new surfaces until this returns a signal.

## Why this exists

The market for "mobile control plane for coding agents" is validated but commoditized (OpenAI Codex
Remote, GitHub Agent HQ, Claude Code auto mode) and a funded open-source competitor — **Omnara**
(YC S25: iOS + Apple Watch, multi-provider push approvals, worktrees) — already ships Lancer's
headline differentiator. Lancer's only defensible inch is the **policy + audit + emergency-stop
governance layer** for agents on your own machines across providers. This cycle tests whether that
inch is real demand or wishful thinking — **before** spending more runway.

## The single question we're answering

> Do people running agents on their own machines, across more than one host or provider, feel enough
> pain around **approvals, policy, and audit** that they would install a daemon and pay for a
> dedicated supervisor — *instead of* native tools or Omnara?

If yes → continue, narrow to the governance wedge. If no → sunset via the open-source/SDK salvage path.

## Design partners — who to recruit

- **10–15 partners.** Quality over count; 10 sharp interviews beat 30 shallow ones.
- **All** must use Claude Code, Codex, or an equivalent agent **weekly**.
- **≥ half** must run **more than one host** OR **more than one provider** (the wedge only exists for
  these people; single-vendor solo devs are explicitly the *weak* segment).
- Bias toward the two best-fit segments from the memo: **power users running several agents/hosts**,
  and **small teams with security/audit needs**. Skip pure single-vendor solo devs.
- Sources: your network, agent-tooling Discords/subreddits, Claude Code / Codex power-user circles,
  indie-hacker + devtools communities. Avoid people who'd say yes just to be nice.

## Outreach blurb (copy/paste, edit to taste)

> I'm testing a small tool for people who run AI coding agents (Claude Code / Codex / etc.) on their
> own machines or servers. It's not another chat app — it's a supervisor: set policy once, then
> approve/stop risky actions and get a tamper-evident audit trail across all your hosts and providers,
> from your phone. I'm doing 20-min calls with people who use agents weekly (especially across >1
> machine or >1 provider) to find out if this is a real pain or not. No pitch, no slides — I mostly
> want to hear how you handle approvals and oversight today. 20 minutes this week?

## Interview script (~20 min)

Keep it about *their* current behavior, not your product. Don't demo until the last 5 minutes.

1. **Setup (2m):** Which agents do you run, on how many machines/providers? How autonomous do you let
   them run (manual approve everything / auto mode / fully unattended)?
2. **Pain discovery (8m) — do NOT lead:**
   - Walk me through the last time an agent did something you wish it hadn't, or you had to stop it.
   - How do you currently decide what an agent is allowed to do without asking? Where does that live?
   - When you're away from your desk, what happens to a run that needs a decision?
   - If something went wrong across your machines, could you reconstruct *what each agent did and why*?
     How? (probe for: do they want an audit trail, or not care)
   - How often per week does an approval/stop/"what happened" moment actually cost you time?
3. **The kill question (3m) — ask explicitly:**
   - "Omnara already does mobile approvals across Claude Code and Codex, for free / open-source. If you
     wanted phone approvals, why wouldn't you just use that?" — **Listen hard.** If they have no reason
     to want more than Omnara, that's a kill signal for this person.
   - Then: "Would *policy presets + a durable cross-provider audit trail + team-owned emergency stop*
     change that answer? Why / why not?"
4. **Willingness (5m):** Show the narrowed concept (policy → approve/stop → audit). Ask:
   - Would this save you real time? Roughly how much/week?
   - Would you install a daemon on your machines for it? (a hard no here is decisive)
   - Would you pay for it? At what per-host / per-seat price does it become a no-brainer vs. a no?

## Success / failure thresholds (decide in advance — don't move them after)

**CONTINUE if all three hold:**
- ≥ **5** partners say a dedicated **policy/audit** supervisor would save real time, **and** give a
  concrete reason they'd pick it over Omnara/native (not just politeness).
- ≥ **3** agree to a **paid pilot** (even a small one).
- ≥ half confirm real multi-host / multi-provider usage (the wedge's precondition exists).

**SUNSET if any of these dominate** (salvage to open-source/SDK, per the memo):
- Most say native mobile/web + their current setup is "good enough."
- Multi-provider / multi-host usage is rarer than assumed.
- Approval/stop/audit moments are too infrequent to justify a dedicated app.
- Partners won't install another daemon — for governance or anything else.

**Ambiguous (mixed signal):** run 5 more interviews skewed harder toward small teams with
security/audit needs before deciding; do not start building on a maybe.

## Logistics

- One tracking sheet: partner, segment, #hosts, #providers, pain frequency, "why not Omnara" answer,
  would-install (y/n), would-pay (y/n + price). One row per call.
- Timebox the whole cycle to ~2 weeks. The point is a decision, not a perfect study.
- Owner-run: recruiting + the calls are yours. Everything in this doc is the prep.
