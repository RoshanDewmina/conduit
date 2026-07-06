# V1 Paid Away Workflow Spec

> **Superseded for scope decisions** by [`2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md). Keep for workflow narrative and stage detail; use [`FEATURE_BACKLOG.md`](FEATURE_BACKLOG.md) for status.

Prepared: 2026-07-04  
Compiled: 2026-07-04T18:08:02Z  
Status: product spec draft, awaiting owner review  
Scope: V1 paid workflow; not an implementation plan

## One-line Thesis

Lancer's first paid workflow is **Away Mode with proof**: a developer can leave
their desk while an agent fixes a real issue, then use the phone to steer,
verify, and decide the work without feeling like they compromised by being
mobile.

This is not "Cursor on a phone" and not a mobile terminal. The paid promise is:

> Leave your desk. Lancer keeps the agent moving, interrupts only when your
> judgment matters, and shows proof before you trust the result.

## Paid Buyer

The first paid buyer is an individual developer or small technical team already
using Claude Code, Codex, OpenCode, Cursor, or similar agents on real repos.

They will pay if Lancer solves a recurring high-friction moment:

- They start an agent task on their machine.
- They need to step away.
- They do not trust the agent enough to leave it unattended.
- Existing mobile options show chat/status but not enough context, proof, or
  validation to safely decide from the phone.

The paid value is confidence, not raw runtime. Lancer sells the ability to keep
work moving while away without opening a laptop every time the agent gets
blocked.

## Primary Scenario

The V1 paid workflow is one scenario:

> "I am leaving my desk for 45 minutes. An agent should fix this bug, avoid
> risky areas, ask me only high-leverage questions, prove the fix, and hand me a
> clean decision when I check my phone."

Example mission:

> Fix the checkout crash from this screenshot. You may edit checkout UI and
> tests. Do not touch Stripe config, migrations, or billing schema. Done means
> the checkout regression test passes and I can see proof of the flow working.

## Workflow

### 1. Start Mission

The user starts from messy mobile or desktop input:

- pasted error, issue, PR comment, log, or stack trace
- screenshot or screen recording
- short voice note
- existing agent thread
- GitHub/Linear/Jira/Sentry link

Lancer converts this into a Mission Contract. The contract is natural-language
first, not a long form.

Required contract fields:

- goal
- repo or host
- allowed scope
- do-not-touch scope
- done criteria
- validation command or validation expectation
- interruption rules
- stop conditions
- proof requirement

If a critical field is missing, Lancer asks one clarifying question before
starting. It should not turn mission start into a wizard.

### 2. Run While Away

The agent runs on the user's machine or server. Lancer tracks meaningful state,
not token-by-token noise.

State captured:

- current phase
- files touched
- commands run
- tests and previews
- approvals requested
- questions asked
- failures and retries
- cost/time budget
- artifacts and proof

The phone presents this as a Work Thread and Live Activity. The Live Activity is
for glanceable state and structured actions only; deeper review opens the app.

### 3. Interrupt Only When Useful

The default mobile rule is **needs-you-first**.

Lancer interrupts for:

- policy/risk approval
- blocked agent question
- validation failure after retry
- budget/time limit
- mission contract violation
- completed work requiring decision

Lancer does not interrupt for:

- routine command output
- every file edit
- low-value status messages
- agent self-narration
- clean progress when no user decision is needed

Lock Screen Question Cards support structured answers such as:

- "Use existing pattern"
- "Add a regression test"
- "Keep scope smaller"
- "Pause"
- "Open details"
- "Ask second agent"

Free-form answers open the app. Text input notification actions may be explored
for low-risk replies, but they are not the V1 default for sensitive decisions.

### 4. Produce Proof

The agent's output is not complete until Lancer can show proof against the
Mission Contract.

Initial V1 proof types:

- test result card
- command output summary
- changed-file summary
- screenshot before/after where available
- preview link or local preview status
- agent-readable evidence bundle for second-pass review

Proof Reel is the first expansion after the proof object exists. It is a concise
artifact, not a full screen recording dump:

- one-line verdict
- static thumbnail first
- 15-45 second optional video
- before/after or problem/fix framing
- validation result attached
- voice narration optional later, not required for the first slice

### 5. Decide

When the user opens Lancer after time away, the Away Digest orders work by what
needs action, not chronology.

Digest order:

1. blocked questions
2. failed validation
3. high-risk approvals
4. completed work awaiting decision
5. clean successes
6. routine progress

Decision actions:

- approve result
- ask for another pass
- request smaller diff
- run validation again
- ask second agent to review
- pause mission
- stop and snapshot
- open on desktop

Approving a result is distinct from approving a risky command. Result approval
means "this mission is done enough for me to accept or continue on desktop."

### 6. Return To Desk

The handoff packet must make desktop re-entry instant.

It includes:

- mission summary
- branch or working tree state
- changed files
- commands run
- tests passed/failed
- unresolved risks
- proof artifacts
- open questions
- next recommended command or action
- continuation ID for the vendor agent where supported

The user should be able to sit down and know exactly where the work stands.

## Product Surfaces

### Mission Contract Card

Compact card shown before launch and editable after launch.

Fields:

- goal
- allowed scope
- do-not-touch
- done means
- validation
- interrupt me for
- stop if

The card becomes the source of truth for validation and later review.

### Work Thread

The canonical timeline for one mission.

It contains:

- phase summaries
- questions
- approvals
- files changed
- validation events
- evidence cards
- proof cards
- final decision

Raw logs are available, but collapsed by default.

### Lock Screen Question Card

Live Activity state for glanceable decisions.

Rules:

- show redacted summary only
- never show secrets or full diff
- use structured answers
- bind action to a current event ID
- expire stale actions
- open app for free-form answers or sensitive detail

### Away Digest

The first screen after time away.

It answers:

- what changed?
- what needs me?
- what is proven?
- what failed?
- what is risky?
- what should I do next?

### Proof Reel

Optional proof artifact for visual or UI-facing missions.

It should be short, skimmable, and tied to validation. It is not a generic Loom
clone inside V1. Agent-readable video metadata and Clips-style import are a
future expansion after the core proof object exists.

### Return-To-Desk Packet

A handoff artifact for the desktop session.

It can live inside the Work Thread first. Export/share can come later.

## Paid Packaging

V1 paid packaging should be framed around away-work reliability, not artificial
feature locks.

Free or trial:

- pair one machine
- run local/basic missions
- receive basic status and approvals
- limited recent history

Paid:

- Away Mode missions
- Mission Contracts
- Away Digest
- Lock Screen Question Cards
- proof artifacts and history
- multi-machine or team-ready history
- second-agent review where vendor credentials are available
- longer retention of proof and audit trail

Metered or future:

- hosted compute
- cloud video/proof storage beyond local retention
- team seats
- enterprise policy/export

Do not position safety as a paid upsell. Basic approvals, emergency stop, and
privacy-preserving notifications remain baseline trust features.

## Non-goals For This V1 Spec

- full mobile IDE
- long-form phone code editing
- generic mobile terminal positioning
- hosted cloud execution as the main V1 promise
- auto-reverting user code without explicit review
- fully agent-native Loom replacement
- full team admin console
- building every proof harness before shipping the workflow
- raw Live Activity text entry

## Required Current-Code Alignment

The spec builds on existing Lancer strengths:

- relay-first V1 direction
- governed approvals
- APNs and Live Activity path
- app-closed lock-screen approval proof
- vendor continuation support
- Work Thread and conversation persistence
- policy/audit spine

Known alignment risks to verify before implementation planning:

- Live Activity relay-dispatch behavior must remain visually confirmed on a
  physical device.
- Question Cards must not bypass the approval hash-binding/security model.
- Local notifications and Watch surfaces must follow the same redaction policy
  as remote APNs payloads.
- Proof artifacts need a durable model; they should not be loose strings in a
  chat transcript.
- Mission Contract rules must integrate with existing policy rather than
  creating a parallel safety system.

## Success Metrics

User-value metrics:

- user can start an away mission in under 60 seconds
- user can understand current mission state in under 10 seconds
- user can answer a blocked question from Lock Screen or app in under 15 seconds
- user can decide a completed mission in under 60 seconds after opening digest
- fewer than one unnecessary interruption per routine mission

Trust metrics:

- every completed mission has at least one proof artifact
- every risky action has an auditable decision event
- stale Lock Screen actions are rejected
- proof and approval payloads do not expose secrets on locked surfaces

Business metrics:

- trial user starts at least one Away Mode mission
- user returns to inspect an Away Digest
- user accepts or redirects work from phone
- user connects more than one repo/host or repeats a mission within seven days
- paid conversion happens after a proof moment, not before setup

## Implementation Slices

This is not the implementation plan, but the spec should be built in this order:

### Slice 1: Contract And Digest Skeleton

- Mission Contract data model
- start mission with contract summary
- Work Thread contract attachment
- Away Digest needs-you-first ordering
- no Proof Reel yet

### Slice 2: Question Cards

- structured agent question event
- generated answer choices
- in-app question card
- Lock Screen quick actions for safe structured choices
- stale/duplicate action handling

### Slice 3: Proof Object

- proof artifact model
- test/command proof cards
- changed-file proof summary
- final result card tied to contract done criteria

### Slice 4: Proof Reel

- attach visual proof to a mission
- show thumbnail/verdict first
- open short video or captured preview artifact
- keep Clips/agent-native metadata as a follow-on, not initial scope

### Slice 5: Return-To-Desk Packet

- desktop handoff summary
- continuation pointers
- unresolved risk list
- next action recommendation

## Open Questions

1. Should the first V1 proof source be test/command output only, or should visual
   preview capture be included in the first paid beta?
2. Should second-agent review be included in the paid V1 pitch, or held as a
   post-beta differentiator?
3. Should the first paid SKU be a one-time client purchase plus metered cloud,
   or a subscription tied specifically to Away Mode history/proof retention?
4. Should Mission Contracts be visible as a formal card, or mostly hidden behind
   natural-language confirmation copy?

## Recommendation

Build the first paid beta around:

1. Mission Contracts
2. Away Digest
3. Lock Screen Question Cards
4. proof objects for tests/commands/changed files
5. Return-To-Desk Packet

Hold full Proof Reel video capture until the proof object and digest loop work.
The product can still market "proof" early if it shows concrete test, command,
diff, and preview evidence. Video should sharpen the experience, not become the
foundation the workflow depends on.

The reason is sequencing: paying users need trust and repeatability before they
need polish. If the non-video proof loop is valuable, Proof Reel makes it feel
magical. If the proof loop is weak, video becomes decoration.
