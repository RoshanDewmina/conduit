# Away-Mode Feature Brainstorm — 2026-07-04

Running log of the feature brainstorm following Codex session `019f2dec-b131-7fa2-b96a-ca5dca31b095`
("Review Claude Code conversation"), which itself followed up on the Claude Code competitive audit
session `fedf09b9-d5eb-4795-b35d-3cb3aa1a61cb` (see [[project_competitive_audit_2026-07-03]] in
Claude memory — 37-agent audit vs 22 OSS + 22 closed-source competitors).

This doc is a working list, not a spec. Ideas get added, validated against the live repo, and
marked keep/hold/reject as we talk through them one at a time. Nothing here is committed to a
roadmap yet.

## Positioning thread (from Codex session)

Codex's arc across the session: generic "mobile agent client" → "governance/policy/audit" →
(owner pushback: "competitors have these points too, we need something more unique") →
**"Away Mode with proof"**: don't just supervise agents remotely, prove their work actually
works, on the phone, in under 30 seconds.

> Lancer lets you leave agents running, then shows you proof they actually did the work.

## Ideas — status as of this session

### Keep / in progress

| Idea | Source | Status | Notes |
|---|---|---|---|
| **Mission Contract** | Codex | Refined | Natural-language input, not a form. App parses into goal/allowed-zones/denied-zones/done-criteria, asks ONE follow-up question in natural language if ambiguous (missing test command, no rollback path, touches unlisted risk zone), shows a compact confirm card before starting. |
| **Proof Reel** | Codex (via Cursor cloud-agent video-proof flow) | Refined | On finishing a mission: show a one-line verdict + static thumbnail first ("✅ Checkout flow verified — tap to watch (0:24)"). Full video is a tap away. Optimized for scanning multiple missions in Away Digest before committing to watch one — not autoplay-full-screen. |
| **Away Digest** | Codex | Refined | Home screen after being away. Ordering = **needs-you-first**: anything blocked on a decision or that failed verification goes to the top unconditionally; clean successes sink to the bottom. Not chronological, not grouped by repo (revisit repo/machine grouping once multi-repo usage is common). |
| **Quarantine / Emergency Stop** | Codex | Refined | One-tap stop = kill process + snapshot (git stash/diff) **only**. Auto-revert to last-known-good is explicitly NOT automatic — reverting files is a separate, deliberate second step after you've looked at what happened. Never auto-discard work. |
| **Photo-in mission start** | New (this session) | Keep | Snap a photo of a bug on a screen (or another device) + short voice note to kick off a mission. No typing. Genuinely mobile-native input, not a shrunk-down desktop flow. |
| **Voice-narrated Proof Reel** | New (this session) | Keep, per owner: "these are great" | Agent narrates before/after over the proof video instead of silent footage — "Here's checkout before my fix, it crashes at payment. Here's after, completes in 1.2s." Works via AirPods while walking/driving without looking at the screen. |
| **Second Opinion, one tap** | New (this session) | Keep, per owner: "these are great" | After a Proof Reel, one button sends the same mission to a second agent/vendor to independently try to break it. Leverages Lancer's cross-vendor position — no single-vendor competitor (Cursor, Devin) can do this. |
| **Interruption Budget** | New (this session) | Keep, per owner: "these are great" | Setting: "only interrupt me for money/security/prod-breaking risk, queue everything else for when I'm back." Targets the notification-fatigue complaint expected to show up in mobile-agent-app reviews (pending X/Reddit research, see Open Research below). |

### On hold

| Idea | Source | Status | Notes |
|---|---|---|---|
| **Agent Firewall / Repo Risk Map** | Codex | **Hold — owner decision 2026-07-04** | Turns out most of the enforcement already exists: `daemon/lancerd/policy/` has a real rule engine (YAML rules, `pathPattern`/`repo`/`Kind`/`minRisk`/`maxRisk`, deny/ask/allow effects, presets) and `blast.go` already computes blast radius (git/network touches, diffed files) per approval. The two real gaps identified — (a) auto-generating risk-zone rules from a repo scan instead of hand-written YAML, (b) translating `MatchedRule` into a plain-English approval reason on the phone instead of a rule ID — are explicitly **parked, not being worked on right now**. Revisit later. |
| **Repo trust score / streak** | New (this session) | **Rejected** | Glanceable badge that climbs with clean missions, earning more autonomy over time. Owner: doesn't land — feels like gamification bolted onto a serious tool rather than something that actually helps the away-from-desk job. |

### Not yet discussed this session (carried over from Codex, un-triaged)

Autonomy Levels, Team/Client Mode, Agent Readiness Check, Proof Timeline, Visual Diff Review,
Device Matrix Proof, Multi-Agent Showdown, Done Means Verified, Auto Bug Replay, Lock-Screen
Progress, Follow-Up quick actions, Team Review Link, Comeback Mode, Ask Another Agent To Verify,
Proof Becomes Regression Test.

## Side finding (not a feature — flagging for the positioning conversation)

An unmerged branch `fable/approval-security-hardening` (commit `447b99bf`, gates green, **not
merged into master**) reinstates a biometric decision gate for high/critical + unknown-risk
approve/reject decisions (low/medium risk stays exempt, matching the existing no-client grace
design). This directly contradicts Codex's advice to avoid pitching "biometric-gated approvals"
as a differentiator, since Codex read that claim off the *current merged* `ARCHITECTURE.md`
("biometric gate/app-lock removed for V1"). Owner decision 2026-07-04: **note only, don't merge
or act on this yet** — revisit once the feature brainstorm and positioning conversation catch up
to it. See Claude memory [[project_approval_security_hardening_2026-07-04]].

## Open research (in progress, paused on account session limit — resume after ~4:10pm America/Toronto 2026-07-04)

Three parallel research agents were dispatched and hit the account-wide session limit before
returning usable findings. To resume:

1. **Desktop/CLI agent-harness loyalty** — why developers stick with Cursor, Windsurf, Warp Agent
   Mode, Devin, Aider, opencode, Claude Code; unattended-agent trust signals from HN/Reddit/X.
2. **Proof/verification harness deep-dive, mobile lens** — Stagehand/Browserbase session replay,
   Maestro cloud dashboard, Replay.io time-travel debugging, BrowserStack/Firebase/Xcode Cloud
   mobile-friendly summaries, Vercel preview-comment toolbar — each translated into a concrete
   "on the phone, Lancer would ___" feature idea, explicitly beyond what Codex's Proof
   Reel/Timeline/Visual Diff/Device Matrix already cover.
3. **X/Reddit/HN real user sentiment** — Happy, Happier, Omnara, Orca, CC Pocket reviews and
   complaints; trust/anxiety themes about unattended agents; head-to-head comparison signals.

None of these produced results yet — the account hit its session limit mid-search on all three.
Re-dispatch after reset.
