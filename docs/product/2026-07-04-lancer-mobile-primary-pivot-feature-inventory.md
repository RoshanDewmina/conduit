# Lancer Mobile-Primary Pivot and Feature Inventory

Prepared: 2026-07-04  
Status: product direction draft, not an implementation plan

> **Superseded 2026-07-05** by `docs/product/2026-07-05-lancer-feature-master-plan.md` — kept for
> historical record only. Its accepted pieces were folded into that doc; its non-goal-conflicting
> pieces (Micro Editor, Developer App Drawer) are formally rejected there.

## Pivot

The current V1 product is scoped as a phone-native steering and approval surface:
agents run on the user's own machines, while the phone reviews risky actions,
shows work status, and records decisions.

The broader product pivot is more ambitious:

> Lancer becomes the mobile-primary coding cockpit for remote-server development.
> The developer can use the phone as the main interface while the remote host and
> agents do the heavy editing, testing, previewing, and shipping.

This does not mean copying a desktop IDE onto a phone. The phone should not
optimize for long manual edits, dense split panes, or raw terminal time. It should
optimize for intent, review, targeted edits, preview, validation, Git decisions,
agent steering, and handoff.

## Positioning

Short form:

> Code from your phone without turning your phone into a tiny laptop.

More specific:

> Lancer lets developers run real coding work on remote servers from their phone:
> define the mission, steer agents, inspect diffs, test previews, validate proof,
> approve risky actions, and ship or hand off when ready.

Why this is different:

- Terminal apps give remote shell access.
- Mobile Git apps give commits and file editing.
- Browser IDEs give a desktop IDE squeezed into a touch screen.
- Agent mobile apps give chat, approvals, or status updates.
- Lancer should combine the useful parts into a phone-native development loop.

## Product Principles

1. **Agent-first, human-in-control.** Agents do the heavy editing; the human sets
   intent, boundaries, taste, and approval.
2. **Mobile-native, not desktop-shrunken.** Prefer cards, sheets, search, command
   actions, previews, and annotations over panes and dense trees.
3. **Proof before trust.** A run is not done because an agent says so. It needs
   tests, preview, screenshots, video, logs, verifier review, or explicit human
   acceptance.
4. **Remote host is the execution truth.** The server owns repo state, commands,
   sessions, policy, and vendor continuation. The phone is the cockpit.
5. **Safety is a baseline, not the headline.** Approvals, audit, emergency stop,
   and policy remain core, but the product promise is productive mobile coding.
6. **Every feature should shorten a real mobile loop.** If a feature only makes
   Lancer feel more like a desktop IDE, it is suspect.

## Final Feature Pillars

### 1. Remote Workspace Home

The home screen for a remote server or repo.

Features:

- active missions
- running agents
- current branch and dirty state
- recent diffs
- test status
- preview status
- pending approvals
- pending questions
- deploy/CI status
- machine health and connectivity
- "what needs me" ordering

Mobile job:

> Tell me what is happening and what I need to decide.

### 2. Mission Contract Builder

A mobile-first way to start coding work without a long prompt.

Features:

- goal
- repo/host
- allowed scope
- do-not-touch zones
- done criteria
- validation requirements
- stop conditions
- budget/time limit
- proof requirement
- one clarifying question at a time when needed

Example:

> Fix the checkout bug from this screenshot. You may edit checkout UI and tests.
> Do not touch Stripe config, migrations, or billing schema. Done means passing
> checkout test plus a proof video.

Mobile job:

> Start useful agent work from messy phone input.

### 3. Mobile Input and Ingest

Ways to create coding missions from the phone.

Features:

- photo-in mission start
- screenshot annotation
- screen recording or bug clip
- voice note
- pasted error/log
- GitHub/Linear/Jira/Sentry share sheet intake
- URL intake
- "summarize what I attached before starting"
- extracted repo/task/context suggestions

Mobile job:

> Capture the problem where I am, without typing a desktop-quality prompt.

### 4. Touch-Native Repo Browser

A code browser that avoids desktop file-tree density.

Features:

- repo search first
- recent files
- changed files
- symbol search
- feature-area grouping
- agent-highlighted relevant files
- file preview optimized for reading
- jump to function/class
- "why is this file relevant?"
- dependency/import map summaries

Mobile job:

> Understand the codebase enough to guide work, without browsing like Finder.

### 5. Micro Editor

A real editor for small, high-leverage edits.

Features:

- edit selected snippet
- edit copy/string
- patch one function
- add or adjust a test case
- accept/reject generated patch
- ask agent to rewrite selection
- AI autocomplete for a selected line/block
- keyboard accessory row for coding symbols
- external keyboard support
- save/apply through host-side patch

Non-goal:

- long-form manual editing as the main workflow

Mobile job:

> Make the small correction myself when explaining it would take longer.

### 6. Agent Patch Composer

The main coding interaction between user and agent.

Features:

- "change this"
- "make it like this screenshot"
- "add tests"
- "fix this failing output"
- "apply this patch"
- side-by-side proposed patch
- hunk-level accept/reject
- "try again smaller"
- "explain risk before applying"

Mobile job:

> Direct code changes without manually editing the whole file.

### 7. Work Thread / Run Timeline

The durable object for one coding mission.

Features:

- phase summary
- timeline of meaningful events
- current step
- approvals and questions inline
- changed files
- commands run
- test results
- artifacts
- collapsed raw logs
- reply/steer composer
- stop/pause controls

Mobile job:

> Follow agent work as a structured activity log, not terminal spam.

### 8. Decision and Question Cards

Agent questions converted into mobile decisions.

Features:

- 2-4 generated answer choices
- "open detail"
- "pause"
- "answer with voice"
- "ask another agent"
- lock-screen quick actions for safe structured choices
- deeper in-app reply for real text
- answer becomes part of the mission contract

Mobile job:

> Resolve agent uncertainty quickly while away.

### 9. Approval and Policy Cards

The existing governance spine, adapted for mobile-primary coding.

Features:

- command/action summary
- risk reason in plain English
- files touched
- repo zone
- rollback path
- allow once / allow for mission / deny / stop
- critical action friction
- audit timeline
- origin machine routing

Mobile job:

> Let safe work continue and make risky work explicit.

### 10. Mobile Diff Review

Diffs redesigned for a phone.

Features:

- summary before patch
- files grouped by purpose
- generated/lock files collapsed
- risk badges
- hunk-level accept/reject
- comment on hunk
- "ask agent to simplify this"
- before/after screenshot next to UI diffs
- test coverage indicator for changed area

Mobile job:

> Review meaningful code changes without reading a full desktop diff.

### 11. Command Cards

Common remote actions as safe, inspectable buttons.

Features:

- run tests
- run build
- run formatter/linter
- restart dev server
- open preview
- capture screenshot
- record proof
- git status
- commit
- push
- create PR
- deploy preview
- rollback

Terminal remains available as an escape hatch, but command cards should be the
default for repeated actions.

Mobile job:

> Run the commands I need without typing shell commands on glass.

### 12. Terminal Escape Hatch

Retained for power users and emergencies.

Features:

- SSH/PTY terminal
- tmux/session resume
- command snippets
- extra key rail
- external keyboard mode
- paste safety
- protected-command approval
- terminal output can be turned into a mission or proof artifact

Mobile job:

> I can still reach the real machine when cards and agents are not enough.

### 13. Preview Cockpit

Phone-native preview for web apps and app surfaces running on the remote host.

Features:

- dev-server preview
- mobile/desktop viewport switch
- dark mode / light mode
- large text mode
- screenshot capture
- console log panel
- network error panel
- "send this screen to agent"
- tap-to-annotate
- record interaction
- compare before/after

Mobile job:

> Try the thing the agent built from my phone.

### 14. Proof Bundle and Proof Reel

The result artifact for agent work.

Features:

- short video proof
- screenshot set
- test output
- build output
- console errors
- network errors
- changed files
- commands run
- validation summary
- known issues
- rollback path
- manifest

Phone presentation:

- one-line verdict first
- thumbnail
- chapters
- watch with voice narration
- annotate frame/timestamp
- send back as follow-up

Mobile job:

> Decide if the work actually works in under a minute.

### 15. Phone QA Mode

The phone becomes a lightweight tester.

Features:

- open preview
- tap through user flow
- record bug clip
- annotate screenshot
- dictate feedback
- attach current screen to mission
- create follow-up from timestamp
- compare against mission contract

Mobile job:

> Test the product in the same place I am reviewing it.

### 16. Validation Harness

Automated and agent-assisted verification.

Features:

- run test plan from mission contract
- browser automation proof
- device/viewport matrix
- accessibility spot checks
- console/network checks
- second-agent review
- "done means verified" gate
- ready-to-merge score
- proof becomes regression test candidate

Mobile job:

> Trust the result because validation is visible and repeatable.

### 17. Git and PR Workflow

Enough Git to ship from the phone.

Features:

- branch create/switch
- pull/rebase status
- dirty-state summary
- commit composer
- push
- PR create/update
- PR comments
- CI status
- revert file/hunk
- stash/shelve
- compare agent attempts
- merge gate if policy allows

Mobile job:

> Move work from branch to review without opening a laptop.

### 18. Away Digest

The mobile recap after time away.

Features:

- needs-you-first ordering
- missions completed
- missions blocked
- failed validations
- pending approvals
- proof reels ready
- cost/time used
- next recommended action
- interruption budget summary

Mobile job:

> Catch up immediately and act on the right thing first.

### 19. Interruption Budget

Control notification intensity.

Features:

- only interrupt for critical risk
- interrupt for questions
- batch low-risk updates
- quiet hours
- per-repo urgency
- "driving/walking mode" voice summary
- Watch/Live Activity summary

Mobile job:

> Keep agents moving without making the phone unbearable.

### 20. Return-To-Desk / Continue Anywhere

Even a mobile-primary product needs continuity.

Features:

- open exact branch/session on Mac
- open proof beside code
- unresolved decisions
- failed validators
- next command
- desktop deep link to Cursor/VS Code/terminal
- preserve phone annotations as comments/tasks

Mobile job:

> Continue seamlessly when I return to a computer.

### 21. Developer App Drawer

A plugin-store-inspired drawer of focused developer tools.

Candidate apps:

- Inbox
- Missions
- Git
- Preview
- Tests
- Terminal
- PRs
- Issues
- Logs
- Proof
- Automations
- Notes
- Deploys
- Machines

Each app is small and task-specific. This avoids a single bloated IDE surface.

Mobile job:

> Give me the right tool for the current coding job.

### 22. Automations for Code

Zapier/Tasks-style coding automations.

Features:

- when CI fails, diagnose
- when PR comment arrives, summarize and propose patch
- when Sentry issue spikes, create investigation mission
- nightly test/dependency audit
- morning digest
- pause mission after repeated failure
- wake user only if a threshold is crossed

Mobile job:

> Let Lancer watch the codebase and create work when needed.

### 23. Project Memory / Notebook

Repo knowledge made mobile-accessible.

Features:

- architecture notes
- dangerous zones
- common commands
- test matrix
- deploy notes
- coding standards
- agent playbooks
- recent decisions
- "what changed since last week?"

Mobile job:

> Give agents and humans the same compact project context.

### 24. Team and Client Proof Layer

The paid/team extension.

Features:

- client-safe proof export
- audit export
- weekly AI work report
- who approved what
- approval delegation
- policy packs per repo/client
- shared proof links
- team emergency stop

Mobile job:

> Make remote agent work accountable to a team or client.

## Prioritization

> **Correction (2026-07-04, confirmed independently by both Claude Code and Codex verification
> passes — see `docs/product/2026-07-04-lancer-whole-app-consolidation.md` §9 and the Away Mode
> cut log in `docs/_archive/away-mode-2026-07/2026-07-04-away-mode-master-consolidation.md` §8):** three items below
> were listed here as "later, not rejected," but have since been explicitly resolved elsewhere as
> **CONFLICTS_WITH_NONGOAL**, not just deferred:
> - **Micro Editor** (Next Layer #2) — directly conflicts with `ARCHITECTURE.md` §1.1's "no local
>   iOS code editor" non-goal. Even Orca's own inline-editing code (the strongest competitor
>   precedent found) scopes strictly to narrow terminal-scratch-artifact files, never general
>   worktree files — the same line Lancer's non-goal already draws.
> - **Developer App Drawer** (Expansion Layer #1) — directly contradicts the locked
>   `ARCHITECTURE.md` §4.1 navigation decision (exactly 5 sidebar destinations, explicit "do not
>   reintroduce a tab bar," a prior Fleet/Activity/Control multi-root layout already deprecated).
> - **Automations for Code, broad version** (Expansion Layer #2) — already explicitly narrowed to
>   "Light Automations" in the Away Mode sweep; the full rule-engine version described here competes
>   with agent judgment and was declined for that reason.
>
> Treat these three as closed unless an owner explicitly reopens them — don't read their presence
> in "Next Layer" / "Expansion Layer" below as still-open roadmap material.

### Near-Term Product Core

These are the features that define the pivot and should be treated as the
central product spine:

1. Remote Workspace Home
2. Mission Contract Builder
3. Mobile Input and Ingest
4. Work Thread / Run Timeline
5. Decision and Question Cards
6. Approval and Policy Cards
7. Proof Bundle and Proof Reel
8. Preview Cockpit
9. Phone QA Mode
10. Away Digest

### Next Layer

These make the app closer to a true mobile-primary coding cockpit:

1. Touch-Native Repo Browser
2. Micro Editor
3. Agent Patch Composer
4. Mobile Diff Review
5. Command Cards
6. Validation Harness
7. Git and PR Workflow
8. Return-To-Desk / Continue Anywhere

### Expansion Layer

These are powerful, but should wait until the core loop is proven:

1. Developer App Drawer
2. Automations for Code
3. Project Memory / Notebook
4. Team and Client Proof Layer
5. Terminal Escape Hatch polish
6. Interruption Budget depth

## Explicit Holds

Do not lead with these until the mobile-primary loop is validated:

- generic mobile terminal positioning
- desktop-style split-pane IDE
- local iOS language servers or local build tools
- hosted cloud execution as the primary story
- broad team dashboards before solo loop works
- gamified trust scores
- automatic destructive rollback
- raw transcript/log stream as the default UI

## Relationship to Current V1

Current V1 remains a narrower governed approval and attention loop. This pivot
is the likely V2/V3 product direction if Lancer chooses to become the primary
phone interface for real remote coding.

The tension is real:

- V1 says the phone steers and approves, not codes.
- This pivot says the phone is the primary coding cockpit.

The way to reconcile that is to avoid defining "coding" as typing source files
for hours. In Lancer, phone-primary coding means:

- setting intent
- directing agents
- reviewing patches
- making small edits
- testing previews
- validating proof
- managing Git/PRs
- deciding what ships

That is a credible phone-native interpretation of coding.

## Recommended Next Artifact

Turn this inventory into a structured roadmap with four buckets:

1. **Current V1**: already built or close to built.
2. **Mobile-primary MVP**: minimum set needed to prove coding from phone.
3. **Paid Pro / team wedge**: features that justify payment.
4. **Moonshots / later**: ambitious features that should not distract now.

