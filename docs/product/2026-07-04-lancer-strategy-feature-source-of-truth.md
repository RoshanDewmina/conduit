# Lancer Strategy and Feature Source of Truth

Prepared: 2026-07-04  
Compiled: 2026-07-05T01:50:27Z  
Status: single-source synthesis for July 4 strategy, feature, competitor, and readiness work  
Scope: product strategy and backlog only; not an implementation plan and not a transcript dump

> **Superseded 2026-07-05** by `docs/product/2026-07-05-lancer-feature-master-plan.md` — kept for
> historical record only. That doc is now the canonical feature source of truth.
>
> **Away Mode pivot descoped 2026-07-06:** "Away Mode with proof" positioning below is historical.
> See `docs/_archive/away-mode-2026-07/README.md`.

## Executive Thesis

Lancer should not compete as a generic mobile agent client, a mobile IDE, or "Claude/Codex on your
phone." Those categories are now crowded by first-party and direct competitors with stronger
distribution.

The sharpest product is:

> Lancer lets developers leave agents working on their own machines, then govern, inspect, prove,
> annotate, and safely finish that work from the phone.

The durable edge is the combination of three things, not any one feature alone:

1. **Own-machine execution** - agents run where the user's repo, credentials, services, and weird
   local environment already live.
2. **Governance below the vendor UI** - policy, audit, risk gates, emergency stop, and vendor-neutral
   dispatch sit under Claude Code, Codex, OpenCode, Kimi, and future CLIs.
3. **Mobile proof and decision loop** - the phone is not a tiny IDE; it is where the user sees what
   changed, answers compressed questions, checks proof, annotates failures, and decides what happens
   next.

The report consensus across Codex and Claude Code was blunt: **proof alone is not enough**, because
Cursor iOS, Codex mobile, Factory, and other incumbents are already moving toward artifact review,
diffs, screenshots, logs, and mobile merge. **Governance alone is also not enough**, because it is
too abstract to sell until it is packaged around a concrete away-from-desk workflow. The sellable
position is **Away Mode with proof and risk control**.

## Current Product Truth

Source type: current repo verification, mostly `ARCHITECTURE.md`, `docs/PUBLISH_READINESS_CHECKLIST.md`,
`docs/competitive-intelligence/reports/current-product-baseline.md`, and
`docs/product/2026-07-04-codex-verification-results.md`.

Lancer already has more than a prototype:

- V1 architecture is relay-first: iOS app -> E2E blind relay/APNs backend -> resident `lancerd`.
  SSH exists but is legacy/power-user for V1.
- `lancerd` already owns policy, audit, dispatch, approvals, and session state on the host.
- Multi-vendor dispatch exists for Claude Code, Codex, OpenCode, and Kimi, including continue/resume
  paths, though vendor CLI flags must be re-audited before adapter changes.
- The full app-closed physical-device APNs approval loop passed on 2026-06-23.
- TestFlight has been uploaded; release remains gated on validation, App Review/store operations,
  StoreKit proof, remote-host E2E, and owner actions.
- Cross-device conversation continuation landed on 2026-07-03 with host-owned execution truth,
  GRDB local mirror, CloudKit private mirror, and observed-session import. Two-device CloudKit QA
  and silent-push delivery are still unverified on hardware.
- The biometric approval gate was reinstated on 2026-07-04 via commit `695d2440`, risk-tiered for
  high/critical and unknown-risk decisions. Low/medium approvals intentionally remain one-tap.

Known current gaps:

- `BiometricGate` still degrades open when the device has no passcode configured. This directly
  weakens the reinstated high-risk approval gate.
- Emergency stop is client-orchestrated per run, not an atomic daemon-side stop-all primitive.
- The Watch app is built/tested but not embedded in the current iOS app target, so it does not reach
  real TestFlight users through the parent app.
- JWT verification in `push-backend` is HS256-only; there is no JWKS/RS256 path.
- The audit hash chain has no external checkpoint anchor; it proves local self-consistency, not
  resistance to a fully compromised host that regenerates history.
- `lancerd` has exactly one relay pairing slot system-wide; new daemon-side pairing can orphan an
  existing phone.
- There is still iOS 27 vs. iOS 26 target drift: `ARCHITECTURE.md` says iOS 27, while project
  settings still point at iOS 26 in verification notes.
- StoreKit one-time IAP appears dormant as a feature gate, while separate hosted/cloud Stripe
  entitlement gates real hosted-agent functionality. Billing needs one product decision, not three
  partially overlapping mechanisms.

## Competitive Edge

Source type: current competitive dataset, July 4 consolidation docs, Claude subagent reads of
competitor repos, and Codex verification.

The competitive environment changed the pitch:

- **OpenAI Codex mobile** and **Cursor iOS** already make artifact review, screenshots/logs/diffs,
  follow-up, and mobile merge feel close to table stakes.
- **GitHub Agent HQ** weakens any broad claim that "nobody does cross-vendor mobile orchestration."
  The narrower Lancer claim still holds: Lancer can run whatever CLI is installed locally, including
  OpenCode and Kimi, without requiring a GitHub integration deal, GitHub-hosted repo, or Copilot
  subscription.
- **Factory/Slack-style workflows** show that team/incident thread ingestion and result videos are
  not blue ocean. Lancer should still support these paths, but should not assume video proof alone
  wins.
- **Happy/Happier** have real E2E encryption and cross-device/mobile surfaces, but the local repo
  research found no comparable governance/policy/audit layer.
- **Omnara** and peers cover mobile supervision and approvals, but the local repo evidence does not
  show Lancer's blind relay + hash-chained audit + policy simulator + host-enforced governance stack.
- **Vibe Kanban/OpenCode/Orca** validate multi-agent/local orchestration patterns, but still do not
  collapse the Lancer wedge if Lancer stays focused on governed away-work rather than a generic
  dashboard.

The clearest edge is not "mobile approvals." It is:

> A vendor-neutral agent firewall, flight recorder, and proof cockpit for own-machine agent work.

This should be the north-star phrasing for future design and implementation reviews.

## July 4 Discussion Log

Source type: named Codex sessions, Claude Code session `6ca8a207-be32-4400-aafd-5eee1970c012`,
Claude side artifacts, and generated docs.

### Codex `019f2dec-b131-7fa2-b96a-ca5dca31b095`

The first thread started from a second opinion on a prior Claude conversation. It moved through:

- generic mobile control plane is crowded;
- governance/policy/audit is real but too abstract alone;
- "competitors have these points too" forced a sharper wedge;
- the useful product became **Away Mode with proof**;
- the loop was decomposed from `input -> progress -> output -> validation` into a fuller flow:
  `capture -> clarify -> contract -> dispatch -> execute -> steer -> prove -> decide -> handoff -> learn`;
- Live Activity lock-screen capabilities were constrained: structured actions are viable, free-form
  text inside a Live Activity is not the model; typed replies need notifications or app deep links;
- Builder.io Clips, `lancer.proof`, proof timelines, mobile QA annotation, and paid validation
  framing entered the conversation.

The thread also produced the paid-pilot target that keeps recurring: by 2026-07-21, aim for
10 qualified users contacted/onboarded, 5 completing 3 real away decisions in 7 days, 3 paying
pilots, and at least 1 team/agency-style customer.

### Codex `019f2ebf-513f-73e0-91ff-13cd74e0a412`

The second thread continued the feature-by-feature pruning. Important decisions:

- **Evidence Inbox** was cut as a standalone feature. The model/composer should absorb messy input;
  Lancer should support attachments and share-sheet intake without making users sort evidence first.
- **Mission Draft** was cut if it means "the agent's plan." The kept version is a thin
  **Away Launch Contract**: host/repo, do-not-touch, interrupt rules, done criteria, proof expected.
- **Big Agent Router** was cut. Kept: **Smart Default Target** using the last successful
  machine/repo/agent, with manual override.
- **Progress** should be minimal by default: phase, elapsed time, last meaningful milestone, and
  whether user action is needed. The richer timeline belongs one layer deeper in Work Thread.
- **Question Cards** were kept as a genuinely Lancer-side mobile adaptation: compress long desktop
  agent questions into 2-4 choices plus a short risk/context line and a full-context escape.
- **Apple local models** were accepted as useful for private compression when available, with
  fallback to the active coding agent or server-side summary if unavailable.
- **Proof Suite, Mobile QA Annotation, Error Autopsy, Away Digest, Git/PR/Merge, Flight Recorder,
  Repo Playbook, Agent Readiness Check, Run Mode, Run Budget, Light Automations, and Provider
  Capability Badges** were all retained or placed on the V1/time-permitting list.

The strongest product sentence from this session was:

> Lancer is the mobile proof and shipping cockpit for agent work.

That sentence is useful, but incomplete unless governance stays in the sentence too.

### Codex `019f2f6d-e4d8-7c11-aa1f-532e5d28c506`

This was the independent verification pass. It confirmed 21 fact-checking items with nuances:

- biometric gate reinstated;
- degrade-open gap still exists;
- emergency stop is non-atomic;
- Watch app not embedded;
- JWT is HS256-only;
- audit chain has no external anchor;
- daemon has one pairing slot;
- StoreKit paywall is dormant but separate cloud entitlement gates real features;
- iOS 27/26 target mismatch persists;
- competitor repos still do not show Lancer's exact policy + hash-chain + emergency-stop stack;
- no local evidence shows the validation gates have run.

This thread is the main guardrail against treating July 4 brainstorm docs as build-ready truth.

### Claude Code `6ca8a207-be32-4400-aafd-5eee1970c012`

The Claude session read Codex `019f2ebf` first, then expanded and challenged it:

- produced `docs/_archive/away-mode-2026-07/2026-07-04-second-opinion-away-mode-v1.md`;
- expanded into the full `docs/_archive/away-mode-2026-07/2026-07-04-away-mode-master-consolidation.md`;
- used subagents to study Omnara, OpenCode, Vibe Kanban, competitor repo availability, governance
  hardening, and prior Codex threads;
- created or referenced the visual artifact
  `/Users/roshansilva/.claude/projects/-Users-roshansilva-Documents-command-center/6ca8a207-be32-4400-aafd-5eee1970c012/tool-results/artifact-4c313d75-1783203171-d4ed.html`;
- produced the whole-app extension at `docs/product/2026-07-04-lancer-whole-app-consolidation.md`;
- found that proof and mobile merge are closer to parity than first assumed;
- pushed back that Cross-Vendor Second-Agent Review and Proof Becomes Regression were dismissed too
  quickly;
- identified whole-app risks: Watch packaging, atomic emergency stop, audit anchoring, pairing
  slot ceiling, billing confusion, and broad roadmap conflicts.

## Accepted Feature Set

Source type: July 4 Codex/Claude discussion plus generated product docs.

### V1 Core

These are the strongest "build next" candidates because they serve the paid Away Mode loop without
turning the phone into a desktop:

- **Away Launch Composer + thin launch contract** - one normal input surface, with lightweight
  boundaries and proof/interrupt defaults.
- **Share Sheet / Universal Link Intake** - send GitHub/Linear/Jira/Sentry/Clips/Loom/Jam/Safari
  content into a prefilled composer. No separate integration dashboard for V1.
- **Smart Default Target** - last successful machine/repo/agent as the default, visible as a chip.
- **Away Mode Setup** - progressive per-repo setup checklist, not a blocking wizard.
- **Repo Playbook** - operational defaults: machine/cwd, default agent, test/build/lint commands,
  dev server/preview port, PR branch, protected zones, proof expectations, interruption defaults.
- **Agent Readiness Check** - machine online, daemon reachable, agent available, repo valid,
  notifications on, proof/test path present.
- **Run Mode** - Strict, Normal, Hands-off until proof, possibly Ask First, mapped to policy and
  interruption behavior rather than a separate permission universe.
- **Run Budget** - time, retry, and provider-exposed cost/token limits where available.
- **Minimal Away Status** - phase, elapsed time, last milestone, user-action-needed state, and one
  details affordance.
- **Question Cards + Question Ladder** - compressed structured decisions, escalating from glance
  through lock-screen chips, evidence reveal, typed instruction, and contract update.
- **Proof Suite base layer** - proof cards, test result cards, changed-file summaries, screenshot or
  preview evidence, proof timeline.
- **Mobile QA Annotation** - pause proof/preview at a frame, mark or tap the issue, dictate a note,
  send back to the agent.
- **Error Autopsy** - failed run card with last successful step, failed command/proof/test, likely
  cause, and actions.
- **Away Digest as Home** - needs-you-first ordering across blocked questions, failed validation,
  approvals, ready proof, and clean progress.
- **Git/PR/Merge Actions** - needed for the app to complete the loop, but must be governed and proof
  conditioned.
- **Flight Recorder + Work Search** - durable history of missions, decisions, proof, and handoffs.
- **Web Preview / Preview Cockpit** - lets the user personally inspect the app from the phone before
  accepting the result.
- **Contextual Command Cards** - one-tap commands for proof rerun, restart preview, re-run tests,
  stop, pause, retry.
- **Changed Files Review** - review diffs and send scoped feedback without a full editor.
- **Voice Everywhere** - short dictation for launch notes, replies, QA annotations, and proof notes.
- **Light Automations** - remind me later, rerun proof, notify on CI fail, check PR later, pause until
  morning. Not a broad automation builder.
- **Provider Capability Badges** - time permitting; show when a provider cannot handle images, exact
  resume, cost reporting, structured questions, PR creation, etc.

### Strong Fast-Follows

These should remain visible in the roadmap because they are more differentiated:

- **Cross-Vendor Second-Agent Review** - one-tap independent check by another installed CLI. Revisit
  earlier than originally planned because single-vendor competitors cannot copy the local-any-CLI
  version cleanly.
- **Proof Becomes Regression / Regression Watchlist** - make proof compound over time.
- **Time-Travel Scrubber + Fork From Timestamp** - inspect the real repo state at a point in the
  mission and fork a new mission from there.
- **Clips integration + `lancer.proof` schema** - Clip-in to mission, Clip-out as proof, and a
  portable agent-readable proof format.
- **Run Comparison** - rerun one mission with a tweaked constraint and compare attempts.
- **Weekly Away Mode Digest** - retention feature: show whether Lancer is actually paying off over
  time.
- **Siri status query / Siri-answerable Question Cards** - useful when gated carefully, but should
  be an enhancement, not the reason to require iOS 27 at launch.
- **StandBy / full-screen proof widget** - mobile-native polish for "proof ready" or "decide now."
- **True Handoff** - return to the exact diff/proof/hunk on Mac, not merely a summary packet.
- **Team and Client Proof Layer** - likely money long-term, but after the solo loop proves value.
- **Watch packaging and Smart Stack relevance** - current code is valuable only if it actually ships.

## Rejected or De-Scoped Ideas

Source type: July 4 feature pruning, `ARCHITECTURE.md` non-goals, and whole-app consolidation.

- **Standalone Evidence Inbox** - redundant with composer + attachments + share sheet.
- **Heavy Mission Draft / plan-mode clone** - underlying agents already plan; Lancer should define
  boundaries, not duplicate implementation planning.
- **Big Agent Router / send to best agent** - premature. Keep smart defaults first.
- **Return-to-Desk Packet as a separate surface** - fold into Work Thread and Flight Recorder.
- **Full mobile code editor / Micro Editor** - violates the no-phone-IDE constraint. Scoped line or
  hunk feedback is fine; general editing is not.
- **Developer App Drawer** - contradicts the locked sidebar IA and reintroduces the multi-root clutter
  already rejected.
- **Broad Automations for Code** - keep Light Automations; do not build a Zapier-style rule engine.
- **Deploy/Release from phone for V1** - defer. Too high-risk for the first paid workflow.
- **Terminal as primary V1 surface** - code exists, but V1 should keep it as an escape hatch, not a
  root.
- **Team/collaboration as V1 core** - defer until the solo away loop proves demand, except for
  future-proofing proof artifacts and audit export.
- **Hosted-cloud execution as V1 story** - code retained, not wired into V1 positioning.
- **Pure proof-only positioning** - proof is necessary parity plus some room for differentiation;
  governance must remain part of the product promise.

## Implementation Priority

This is not a full implementation plan, but it should guide the next plan.

### Before Building Product Features

1. Run or explicitly schedule the validation gates. The repo has no local evidence that the
   design-partner interviews or 10/5/3/1 paid Away Mode gate have happened.
2. Fix product-truth drift before implementation planning: decide iOS 26 vs. iOS 27 launch target,
   billing model, Watch packaging stance, and the exact first paid promise.
3. Clean up critical governance gaps: no-passcode biometric degrade-open, atomic emergency stop,
   single pairing slot strategy, audit external anchor, and JWT algorithm support.

### First Build Slice

Build the smallest complete paid loop:

1. Away Launch Composer with thin contract and Smart Default Target.
2. Repo Playbook + Agent Readiness Check, minimal first version.
3. Away Status + Home/Away Digest ordering.
4. Question Cards and Interruption Budget for structured decisions.
5. Proof object base layer: test result, changed files, screenshot/preview proof, validation state.
6. Error Autopsy failure state.
7. Git/PR decision actions only when proof and policy allow.

### Second Build Slice

Add the differentiated layer:

1. Mobile QA Annotation and preview feedback loop.
2. Device Matrix Proof where the existing Apple Device Hub/devicectl workflow can support it.
3. Cross-Vendor Second-Agent Review.
4. Time-Travel Scrubber / Fork From Timestamp prototype.
5. `lancer.proof` schema and Clips-compatible proof import/export.

### Third Build Slice

Polish, retention, and platform-native leverage:

1. Weekly Away Mode Digest.
2. Siri/App Intent status query and question answering where available.
3. StandBy/full-screen proof widgets and Dynamic Island mission strip.
4. True Handoff.
5. Team/client proof links after solo loop validation.

## Product Rules Going Forward

- The first screen should remain the governed away-work loop, not a marketing page and not a
  terminal.
- Home should answer "what needs me now?" before it shows chronology.
- Work Thread is the canonical mission timeline. Raw logs and terminal are subordinate.
- Every feature must answer one of: capture, bound, run, interrupt, prove, decide, hand off, learn.
- If a feature can be done as a composer attachment, a Work Thread card, or a Settings/Playbook
  default, do not add a new root.
- If a feature duplicates the agent's plan mode, cut it or reduce it to a Lancer-side boundary.
- If a feature weakens the governance promise, it cannot be V1.
- Proof should be structured, searchable, portable, and eventually reusable as regression evidence.
- User-visible claims must distinguish proven code, code-complete but unverified hardware behavior,
  generated research, and external claims.

## Source Index

### Named Sessions

- Codex `019f2dec-b131-7fa2-b96a-ca5dca31b095`: `/Users/roshansilva/.codex/sessions/2026/07/04/rollout-2026-07-04T12-18-34-019f2dec-b131-7fa2-b96a-ca5dca31b095.jsonl`
- Codex `019f2ebf-513f-73e0-91ff-13cd74e0a412`: `/Users/roshansilva/.codex/sessions/2026/07/04/rollout-2026-07-04T16-08-38-019f2ebf-513f-73e0-91ff-13cd74e0a412.jsonl`
- Codex `019f2f6d-e4d8-7c11-aa1f-532e5d28c506`: `/Users/roshansilva/.codex/sessions/2026/07/04/rollout-2026-07-04T19-19-19-019f2f6d-e4d8-7c11-aa1f-532e5d28c506.jsonl`
- Claude Code `6ca8a207-be32-4400-aafd-5eee1970c012`: `/Users/roshansilva/.claude/projects/-Users-roshansilva-Documents-command-center/6ca8a207-be32-4400-aafd-5eee1970c012.jsonl`
- Claude side artifacts: `/Users/roshansilva/.claude/projects/-Users-roshansilva-Documents-command-center/6ca8a207-be32-4400-aafd-5eee1970c012/subagents/`, `tool-results/`, `workflows/`

### Primary Repo Sources

- `ARCHITECTURE.md`
- `docs/PUBLISH_READINESS_CHECKLIST.md`
- `docs/KNOWN_ISSUES.md`
- `docs/LIVE_LOOP_RUNBOOK.md`
- `docs/LAUNCH_AUDIT-2026-06-18.md`
- `docs/validation-cycle-v1.md`
- `docs/competitive-intelligence/reports/current-product-baseline.md`
- `docs/competitive-intelligence/data/competitors.jsonl`
- `docs/_archive/away-mode-2026-07/2026-07-04-away-mode-master-consolidation.md`
- `docs/product/2026-07-04-lancer-whole-app-consolidation.md`
- `docs/_archive/away-mode-2026-07/2026-07-04-second-opinion-away-mode-v1.md`
- `docs/_archive/away-mode-2026-07/2026-07-04-v1-paid-away-workflow-spec.md`
- `docs/product/2026-07-04-lancer-mobile-primary-pivot-feature-inventory.md`
- `docs/product/2026-07-04-codex-verification-brief.md`
- `docs/product/2026-07-04-codex-verification-results.md`
- `docs/_archive/away-mode-2026-07/2026-07-04-away-mode-feature-brainstorm.md`

### Competitor Repos and Local Research Inputs

- `research_repos/omnara`
- `research_repos/opencode`
- `research_repos/vibe-kanban`
- `research_repos/happy`
- `research_repos/happier`
- `research_repos/orca`

### External Links Carried From Local Docs

These were not refreshed during this report implementation; they are included because the July 4
source docs cite them as supporting material.

- Apple Live Activities essentials: `https://developer.apple.com/videos/play/wwdc2026/223/`
- Apple Foundation Models: `https://developer.apple.com/documentation/foundationmodels`
- Apple WWDC26 Foundation Models: `https://developer.apple.com/videos/play/wwdc2026/241/`
- Apple SpeechAnalyzer: `https://developer.apple.com/documentation/speech/speechanalyzer`
- Apple UIActivityViewController: `https://developer.apple.com/documentation/UIKit/UIActivityViewController`
- Apple App Schemas / content transfer: `https://developer.apple.com/videos/play/wwdc2026/240/`
- Apple Device Hub: `https://developer.apple.com/videos/play/wwdc2026/260/`
- Apple TextKit session: `https://developer.apple.com/videos/play/wwdc2026/370/`
- OpenAI Codex mobile article: `https://openai.com/index/work-with-codex-from-anywhere/`
- Cursor iOS blog: `https://cursor.com/blog/ios-mobile-app`
- GitHub Copilot app / Agent HQ: `https://github.blog/news-insights/product-news/github-copilot-app-the-agent-native-desktop-experience/`
- GitHub Copilot agents: `https://github.com/features/copilot/agents`
- Factory Slack: `https://factory.ai/product/slack`
- Builder.io Clips / Agent Native: `https://github.com/BuilderIO/agent-native`
- Builder Clips announcement: `https://www.builder.io/blog/clips-loom-alternative`
- Anthropic Remote Control coverage: `https://venturebeat.com/orchestration/anthropic-just-released-a-mobile-version-of-claude-code-called-remote`

## Final Decision Frame

Lancer is compelling if it commits to this:

> Start real agent work, walk away, get only the right interruptions, prove what changed, annotate or
> accept the result, and leave behind an audit trail across the agents and machines you actually use.

It is not compelling if it becomes another remote chat client, another mobile terminal, another proof
viewer without governance, or another broad dashboard full of unvalidated surfaces.

The next product plan should therefore be narrow: **Away Mode with proof and risk control**, then
validation, then only the differentiated mobile-native layers that strengthen that loop.
