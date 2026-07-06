# Mobile-Native AI Coding Workflow Research

Prepared: 2026-07-05  
Status: research synthesis and product opportunity memo, not an implementation plan  
Scope: how serious AI-coding users actually work, what is signal versus noise, and how Lancer can turn those workflows into a deeply iPhone-native experience.

## Executive Takeaway

The strongest signal is not that developers want to read less code blindly. It is that they are changing *what* they review first.

Experienced AI-coding users increasingly ask agents to produce:

- architecture maps before code review;
- plans before implementation;
- verification evidence before trust;
- focused question/decision cards instead of long transcripts;
- reusable review and test checklists;
- artifacts that explain what changed and why.

That maps cleanly to Lancer. The iPhone should not become a small IDE. It should become the place where an agent's work is converted into **architecture, proof, decisions, and next actions**.

Recommended product sentence:

> Lancer turns agent work into a mobile-native review loop: architecture first, proof next, code only when necessary.

This strengthens the existing July 4 direction. Proof alone is close to competitor parity. Governance alone is too abstract. The sharper wedge is:

> Governed own-machine agents, presented through iPhone-native architecture, verification, proof, and decision surfaces.

## Evidence Quality Notes

This memo uses a mix of source types:

- **High confidence:** Apple official documentation and WWDC26 session pages; repo-local Lancer docs; public GitHub profiles/repos.
- **Medium confidence:** long-form podcasts/newsletter summaries, Hacker News threads, Reddit threads with concrete workflow detail.
- **Lower confidence but useful signal:** X posts and X mirrors. X search can surface exact posts, but direct pages are often hard to scrape. I treat viral X posts as prompts to verify patterns elsewhere, not as standalone proof.

## What Practitioners Are Actually Doing

### 1. Architecture Before Code

The Delba post you cited is consistent with a broader workflow shift: ask the agent to explain architectural change first, then inspect code only if needed.

The exact pattern:

- before/after architecture;
- modules and dependencies;
- seams;
- function signatures;
- visual diagrams;
- HTML or visual report artifacts.

Related signal:

- Delba's X post was found directly by search: [x.com/delba_oliveira/status/2073467304491233543](https://x.com/delba_oliveira/status/2073467304491233543).
- A YouMind mirror of Delba's June 2026 guidance emphasizes encoding manual verification into reusable skills and secondary reviews: [Feedback loops: Help Claude Code complete ambitious tasks with less babysitting](https://youmind.com/landing/x-viral-articles/claude-code-feedback-loops-autonomy).
- John Lindquist's Lenny's Newsletter episode highlights Mermaid diagrams for context loading, hooks for code quality, AI-generated docs for humans and machines, and codebase orientation: [Advanced Claude Code techniques](https://www.lennysnewsletter.com/p/advanced-claude-code-techniques-context).
- A Reddit thread on maintaining AI-written codebases repeatedly recommends a human-owned architecture map, diagrams, and architecture-first reviews: [How do you guys maintain a large AI-written codebase?](https://www.reddit.com/r/ClaudeAI/comments/1plse94/how_do_you_guys_maintain_a_large_aiwritten/).
- Another Reddit comment describes Mermaid diagrams plus quick references as a way to keep the agent organized and reduce prompting overhead: [What am I missing here? Claude Code seems a joke when I use it](https://www.reddit.com/r/ClaudeAI/comments/1l4omv6/what_am_i_missing_here/).

Product implication:

Lancer should have an **Architecture Change Card** in the Work Thread. It should show:

- before/after dependency diagram;
- changed modules;
- new/removed seams;
- touched public function signatures;
- "why this shape" summary;
- risks and regression points;
- a button to open code only when the user wants depth.

This is a better mobile primitive than a raw diff as the first review surface.

### 2. Plan Review Beats Diff Review For Many Tasks

Practitioner posts repeatedly say the useful human intervention happens before code is written.

Evidence:

- A Reddit workflow post says the author improved results by asking for plans, running 2-3 review rounds with another model, then using implementation checkpoints: [Don't review code changes, review plans](https://www.reddit.com/r/ClaudeCode/comments/1rrbfkj/dont_review_code_changes_review_plans/).
- A Rasmic podcast episode summary frames Claude Code results around clear inputs, feature/test thinking, ask-user-question clarity, and not hiding behind automation before doing manual reps: [Claude Code Clearly Explained](https://podcasts.apple.com/se/podcast/claude-code-clearly-explained-and-how-to-use-it/id1593424985?i=1000745796041).
- A Reddit "agentic coding after six months" post says the improvement came from better plans, not a better model: architecture, product briefs, implementation plans, to-do lists, memory files, and task-based development with testing: [Finally Cracked Agentic Coding after 6 Months](https://www.reddit.com/r/ChatGPTCoding/comments/1iykysy/finally_cracked_agentic_coding_after_6_months/).
- Apple's Xcode 27 material mirrors this: Xcode agents have a `/plan` command that gathers context before making code changes, supports inline feedback on the plan, and can run sub-agents during exploration: [What's new in Xcode 27](https://developer.apple.com/videos/play/wwdc2026/258/).

Product implication:

Lancer should not make "Mission Draft" look like another agent plan. The already-approved thin Launch Contract is right, but it should gain one new review artifact:

**Plan Delta Card**

- "What changed from the contract?"
- "What did the agent decide?"
- "What needs human taste?"
- "What is still unknown?"
- approve plan / request smaller plan / ask another agent to review / start implementation.

On iPhone, this should be a compact decision card, not a document editor.

### 3. Verification Is The Autonomy Unlock

The strongest serious-agent pattern is not "trust the model." It is "give the model ways to check itself."

Evidence:

- Delba's mirrored guide says autonomy improves when manual checks are encoded into reusable skills, and lists deterministic signals like type errors, lint errors, tests, runtime errors, browser automation, DevTools, endpoint testing, simulators, screenshots, and performance traces: [YouMind mirror](https://youmind.com/landing/x-viral-articles/claude-code-feedback-loops-autonomy).
- A LinkedIn summary of Delba's talk states the same core idea: stop babysitting after every change by formalizing verification steps into reusable skills: [LinkedIn summary](https://www.linkedin.com/posts/rohitaggarwal_boris-cherny-bcherny-on-x-activity-7470567807701659649-jBWQ).
- Hacker News users describe dedicated TDD agents, review agents, and multiple terminals running specialized Claude agents before commits enter CI/CD: [Getting good results from Claude Code](https://news.ycombinator.com/item?id=44836879).
- A ClaudeCode TDD thread says a plan should include tests or verification steps, and that custom skills can encode testing philosophy: [TDD workflows with Claude Code](https://www.reddit.com/r/ClaudeCode/comments/1qd64xx/tdd_workflows_with_claude_code_whats_actually/).

Product implication:

Lancer's "Repo Playbook" should become a visible verification contract:

- tests to run;
- preview URL;
- screenshot/proof requirements;
- accessibility settings;
- device matrix;
- known risky flows;
- "agent may not mark done until these pass."

On iPhone, this should appear as a **Verification Checklist Card** attached to the mission, then as a **Proof Card** when completed.

### 4. The Best Users Run Multiple Agents, But Need Triage

The high-end pattern is parallel agents and cross-checking, but the UX risk is cognitive overload.

Evidence:

- Business Insider reported that Boris Cherny described using the Claude app on his phone with several code sessions and many agents doing deeper work overnight: [Claude Code creator says he runs thousands of AI agents overnight](https://www.businessinsider.com/anthropic-engineer-claude-boris-cherny-ai-agent-use-overnight-2026-5).
- HN users describe multiple agents implementing, reviewing, or maintaining reusable review checklists: [How I'm Productive with Claude Code](https://news.ycombinator.com/item?id=47494890).
- Reddit users report switching among Claude, Codex, and Gemini depending on task, quota, or reliability: [what coding agent have you actually settled on?](https://www.reddit.com/r/ChatGPTCoding/comments/1p698cb/what_coding_agent_have_you_actually_settled_on/).
- The caution is real: an HN commenter called complex multi-thread orchestration mentally heavy. That is the product problem Lancer can solve: triage, not raw multiplicity.

Product implication:

Lancer should not show "10 agents running" as a dashboard brag. It should show:

- which run needs a human;
- which run has proof ready;
- which run failed verification;
- which run made architectural changes;
- which run is safe to ignore.

Home should remain a Cursor-simple daily ledger.

### 5. Serious Users Still Warn Against Eyes-Off Coding

The noisy version of AI coding says "don't read code." The more credible version says "review better artifacts first, but keep escape hatches."

Evidence:

- A ClaudeCode Reddit reply says experienced engineers should still review code and that Claude often needs course correction: [Any experienced software engineers who no longer look at the code?](https://www.reddit.com/r/ClaudeCode/comments/1p1kh50/any_experienced_software_engineers_who_no_longer/).
- Karpathy's original "vibe coding" post was intentionally loose and playful: [x.com/karpathy/status/1886192184808149383](https://x.com/karpathy/status/1886192184808149383). Later commentary around "agentic engineering" is more serious: directing and overseeing agents, not blindly accepting output.
- Business Insider summarized Karpathy's caution that AI-written code can be awkward, repetitive, poorly abstracted, and still need human structural taste: [AI code can still be awkward and gross](https://www.businessinsider.com/andrej-karpathy-vibe-coding-ai-code-awkward-gross-needs-humans-2026-4).

Product implication:

Lancer should not promise "never read code." It should promise:

> Start with architecture and proof. Open code only when the artifact raises a question.

That is credible, safer, and more aligned with expert workflows.

### 6. Visual PR Recaps Are The Missing Review Surface

The Steve8708 video you shared is a strong concrete example of the same pattern. I could not treat the X video page itself as durable source material, so this section uses your transcript as the primary description of the video and verifies the surrounding product pattern through Steve Sewell / Builder.io's public docs and posts.

What the video demonstrates:

- a PR recap that starts with what changed, not a raw diff;
- schema, API endpoint, request/response, and error-code views;
- security-sensitive code called out with annotations;
- UX and copy implications rendered as visible UI locations;
- click-to-comment on any artifact;
- comments that can route to a human reviewer, the agent, or both;
- inline follow-up with the agent;
- a GitHub Action that posts recaps to PRs automatically;
- MDX/reusable components instead of one-off generated HTML.

Verified adjacent evidence:

- Builder's `/visual-recap` skill says it reads changed files and diffs, then publishes an interactive recap with file maps, diagrams, schema maps, API diffs, annotated diffs, UI state summaries, and focused key changes: [BuilderIO visual-recap README](https://github.com/BuilderIO/skills/blob/main/skills/visual-recap/README.md).
- Builder's `/visual-plan` skill does the same before work starts: it grounds plans in repo files, schemas, actions, and symbols, then publishes an interactive review document with diagrams, UI flows, API specs, schema maps, diffs, code annotations, and reviewer questions: [BuilderIO visual-plan README](https://github.com/BuilderIO/skills/blob/main/skills/visual-plan/README.md).
- The Builder skills README puts `/visual-plan` and `/visual-recap` first in the installer and says `/visual-recap` turns a branch, commit, or PR diff into an interactive recap with annotated diffs, diagrams, API/schema summaries, file maps, UI state summaries, and focused review notes: [BuilderIO skills README](https://github.com/BuilderIO/skills/blob/main/README.md).
- Agent-Native's framework README describes the deeper pattern: apps where agents and UI share the same actions, state, and context; the Plans app installs `/visual-plan` and `/visual-recap` for high-level code reviews with diagrams, wireframes, annotations, and review links: [BuilderIO agent-native](https://github.com/BuilderIO/agent-native).
- Builder's blog frames the problem clearly: large agent PRs shift the human from builder to exhausted reviewer; plan and recap artifacts create a verifiable contract, and drift between plan and recap is itself a failure signal: [Introducing /visual-plan: Scannable Claude Code plans](https://www.builder.io/blog/claude-code-plan).
- Steve's Agent-Native article argues that agent apps need streaming state, feedback, actions, instructions, skills, memory, and guardrails, not just `llm(prompt)` output: [How to build agent-native applications](https://www.builder.io/blog/agent-native-apps).
- Steve's LinkedIn repost of the code-review demo links directly to the BuilderIO skills repo and Agent-Native MDX viewer/editor source: [Steve Sewell LinkedIn post](https://www.linkedin.com/posts/steve8708_how-ive-changed-the-way-i-do-code-reviews-activity-7478492314152312832-rwbM).

Adjacent market pattern:

- GitHub Copilot can generate PR summaries and run code reviews, but GitHub's docs still tell users to review the generated summary carefully: [Create a PR summary with Copilot](https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/copilot-on-github/copilot-for-github-tasks/create-a-pr-summary), [Using Copilot code review](https://docs.github.com/copilot/using-github-copilot/code-review/using-copilot-code-review).
- CodeRabbit is moving beyond simple GitHub comments into a review interface: its docs describe a "Review Change Stack" entry point from PR comments into CodeRabbit Review, with walkthrough and pre-merge checks: [CodeRabbit Review docs](https://docs.coderabbit.ai/pr-reviews/coderabbit-review).
- Greptile's pitch is whole-repo understanding: it builds a repository graph, reviews every PR, posts comments, and includes "Fix with your Agent" handoff buttons to Claude Code, Codex, Conductor, Cursor, or Devin: [Greptile overview](https://www.greptile.com/docs/introduction).
- PR-Agent/Qodo Merge is the open-source baseline: describe, review, improve, ask, GitHub Actions, CLI, multiple git providers, multiple models, and PR compression: [PR-Agent GitHub repo](https://github.com/The-PR-Agent/pr-agent).
- Builder's Quality Review Agent shows another nearby direction: the agent uses the product in a real browser on every PR, checks critical flows, edge cases, and regressions, and pairs functional testing with code review: [Announcing Quality Review Agent](https://www.builder.io/blog/announcing-quality-review-agent).

Community counter-signal:

- Reddit users evaluating AI code review tools repeatedly cite noise, false positives, and missing whole-repo context, even when they still find the tools useful: [AI Code Review Tools Benchmark](https://www.reddit.com/r/devops/comments/1qntnva/ai_code_review_tools_benchmark/).
- Hacker News users give the same nuanced view: AI review catches bugs and low-level issues, but struggles with "is this solving the business problem," dependency choices, broader design fit, non-determinism, and sometimes impossible-in-practice warnings: [There is an AI code review bubble](https://news.ycombinator.com/item?id=46766961).
- Another Hacker News thread warns that English summaries and code do not automatically align; for security/audit-grade review, the artifact must point back to ground truth: [Hallucinations in code are the least dangerous form of LLM mistakes](https://news.ycombinator.com/item?id=43233903).

Product implication:

Lancer needs a **Visual Recap Card**, but it should be phone-native and proof-bound rather than a mini web document.

What it should show on iPhone:

- mission outcome;
- plan versus recap drift;
- changed architecture modules;
- changed APIs/schemas/contracts;
- UI/copy impact snapshots;
- security/privacy/auth/payment risk callouts;
- proof status and stale-proof warnings;
- top 3 "review me" questions;
- open code / open preview / open full recap actions.

Interaction model:

- tap any recap row, screenshot, schema field, API endpoint, or risk note;
- choose comment target: agent, human reviewer, PR comment, or mission note;
- send structured edits like "make this int, not string" to the agent;
- send questions like "why can this be null?" to the agent inline;
- escalate unresolved questions into the Work Thread;
- save accepted proof or review notes as future repo playbook checks.

This creates a Lancer-specific version of the Agent Native idea: the iPhone becomes the review cockpit for own-machine agent work. The user does not need a browser-sized MDX canvas first. They need a compact, source-backed stack of artifacts with fast comment routing and risk-aware approvals.

### 7. Fanout Addendum: What The Broader Market Is Teaching Us

This fanout searched across practitioner blogs, X/LinkedIn mirrors, Reddit, Hacker News, official docs, and current tool/vendor surfaces. The big update is blunt:

> "Approve an agent from your phone" is no longer enough.

Evidence:

- OpenAI says Codex is now in the ChatGPT mobile app, with live state, approvals, plugins, project context, screenshots, terminal output, diffs, and test results flowing from the user's machine or remote environment to the phone: [Work with Codex from anywhere](https://openai.com/index/work-with-codex-from-anywhere/).
- Anthropic's Remote Control lets users continue a local Claude Code session from phone, tablet, or browser: [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control).
- GitHub Mobile lets users start and track Copilot coding-agent tasks, with Copilot creating a draft PR and tagging the user for review: [Start and track Copilot coding agent tasks in GitHub Mobile](https://github.blog/changelog/2025-09-24-start-and-track-copilot-coding-agent-tasks-in-github-mobile/), [GitHub Mobile docs](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-on-mobile).
- Omnara positions itself directly as mobile control for Claude Code and Codex, with progress, diffs, and approvals from the phone: [Omnara App Store listing](https://apps.apple.com/us/app/omnara-claude-codex-mobile/id6748426727), [Omnara site](https://www.omnara.com/), [Show HN: Omnara](https://news.ycombinator.com/item?id=44878650).

Product implication:

Lancer should not lead with "remote control." It should lead with:

> A phone-native proof-to-ship loop for all your own-machine agents.

That means cross-vendor attention, typed approvals, proof bundles, risk tiers, recap drift, and local auditability. Remote terminal/chat is the substrate, not the wedge.

#### Durable Practitioner Patterns

The higher-quality practitioner sources converge on a lifecycle:

1. Start with intent, context, and constraints.
2. Produce a plan or spec.
3. Review the plan, often with a second model.
4. Run the agent in a bounded workspace.
5. Require proof: tests, browser runs, screenshots, logs, CI, preview.
6. Review a recap/diff/PR.
7. Commit or send back focused comments.

Examples:

- Steve Sewell describes Claude Code becoming the primary work interface, with the IDE increasingly used for review; Builder's visual-plan/visual-recap work makes plans and recaps into rich artifacts: [How I use Claude Code](https://www.builder.io/blog/claude-code), [Scannable Claude Code plans](https://www.builder.io/blog/claude-code-plan).
- Andrej Karpathy's "Software Is Changing Again" framing reinforces the move up the stack: humans increasingly operate at intent, evaluation, and correction layers rather than line-by-line code production: [transcript](https://singjupost.com/andrej-karpathy-software-is-changing-again/).
- Boris Cherny's phone/parallel-agent workflow validates away-from-desk orchestration, but it also raises the bar for status compression and proof: [Every interview page](https://every.to/podcast/how-to-use-claude-code-like-the-people-who-built-it), [Business Insider summary](https://www.businessinsider.com/anthropic-engineer-claude-boris-cherny-ai-agent-use-overnight-2026-5).
- John Lindquist's workflow uses Mermaid diagrams, hooks, and reusable AI workflows to load context and enforce checks: [Advanced Claude Code techniques](https://www.lennysnewsletter.com/p/advanced-claude-code-techniques-context).
- Simon Willison documents the parallel-agent pattern, especially worktrees and asynchronous agents that return later with artifacts/PRs: [parallel coding agents](https://simonwillison.net/2025/Oct/5/parallel-coding-agents/), [async code research](https://simonwillison.net/2025/Nov/6/async-code-research/).
- Harper Reed's workflow is explicitly spec-first: brainstorm, `spec.md`, detailed plan, then smaller TDD prompts: [My LLM codegen workflow atm](https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/).
- Armin Ronacher recommends giving agents large jobs and using the IDE for final edits, while warning that some hook/subagent patterns do not always improve the workflow: [agentic coding recommendations](https://lucumr.pocoo.org/2025/6/12/agentic-coding/), [things that did not work](https://lucumr.pocoo.org/2025/7/30/things-that-didnt-work/).
- Peter Steinberger describes plan mode, external model review for larger plans, and limited parallelism by work type rather than indiscriminately running many agents: [optimal AI development workflow](https://steipete.me/posts/2025/optimal-ai-development-workflow).
- Jesse Vincent's Superpowers package turns spec discovery, TDD, subagent work, review, and merge/stop choices into repeatable skills: [Superpowers](https://blog.fsck.com/2025/10/09/superpowers/), [repo](https://github.com/obra/superpowers).
- Bas Nijholt shows coding from an iPhone with Blink, voice dictation, local agents, and diff/review/commit loops; this validates mobile steering, but not mobile IDE replacement: [Agentic mobile workflow](https://www.nijho.lt/post/agentic-mobile-workflow/).
- OpenAI's Codex docs emphasize explicit context, definition of done, verification, `AGENTS.md`, and focused P0/P1 review: [Codex workflows](https://developers.openai.com/codex/workflows), [Codex GitHub review](https://developers.openai.com/codex/integrations/github), [AGENTS.md guide](https://developers.openai.com/codex/guides/agents-md).

Product implication:

Lancer should treat this lifecycle as the first-class object. A "mission" is not chat. It is a contract, a bounded run, proof, recap, comments, and a merge/continue/stop decision.

#### Community Patterns And Pain

Broad Reddit/Hacker News search was noisy, but the repeated high-signal patterns were consistent:

- **Plan-first works, but only if plans are reviewable.** Users say it is easier to review a plan than a full component, and some have another model review the plan before implementation: [HN: Ask HN on Claude Code](https://news.ycombinator.com/item?id=44362244), [Reddit: opinion on plan mode](https://www.reddit.com/r/ClaudeCode/comments/1qr2mzw/your_opinion_on_plan_mode/), [Reddit: improve plan mode quality](https://www.reddit.com/r/ClaudeCode/comments/1rdgmdj/the_easiest_way_ive_found_to_improve_plan_mode/).
- **Tests are an unlock, but agents can game or mutate tests.** Simon Willison notes good tests let Claude Code check distant behavior, while commenters warn agents may "fix" tests instead of root causes: [HN: Claude Code experience](https://news.ycombinator.com/item?id=44596472), [HN: Getting good results from Claude Code](https://news.ycombinator.com/item?id=44836879).
- **Browser/devtools proof is becoming mandatory for frontend.** Users want agents to inspect DOM, console, network, screenshots, and rendered UI, but screenshots can also bloat context: [HN: Claude Code 2.0](https://news.ycombinator.com/item?id=45416228), [Reddit: Playwright screenshots filling context](https://www.reddit.com/r/ClaudeCode/comments/1ojwtop/playwright_screenshots_quickly_filling_up_context/).
- **Context rot and handoff state are real.** Users maintain state files, TODO files, or compact handoff docs because long sessions lose details: [HN: Claude Code after two weeks](https://news.ycombinator.com/item?id=44596472), [Reddit: context switching with Claude Code](https://www.reddit.com/r/ClaudeCode/comments/1ravaw5/how_do_you_manage_context_switching_when_using/).
- **Parallel agents need ownership and receipts.** Worktrees help avoid file conflicts, but users still need to know which agent touched what, why, and with what proof: [Simon Willison](https://simonwillison.net/2025/Oct/5/parallel-coding-agents/), [Reddit: managing multiple coding agents](https://www.reddit.com/r/ClaudeCode/comments/1st213z/how_are_you_managing_multiple_coding_agents_in/).
- **AI review is useful but noisy.** Users value AI review as a first pass, but complain about false positives, repetition, missing repo context, and inability to judge business fit: [Reddit: AI code review benchmark](https://www.reddit.com/r/devops/comments/1qntnva/ai_code_review_tools_benchmark/), [HN: AI code review bubble](https://news.ycombinator.com/item?id=46766961).
- **Generated-code maintenance is the long-term fear.** Skeptics worry about duplicated patterns, overengineering, hidden debt, and code authors who cannot explain decisions: [Reddit: AI generated code and technical debt](https://www.reddit.com/r/programming/comments/1it1usc/how_ai_generated_code_accelerates_technical_debt/), [Reddit: ExperiencedDevs AI code review tools](https://www.reddit.com/r/ExperiencedDevs/comments/1o1a601/whats_your_honest_take_on_ai_code_review_tools/).
- **Cost and quota shape behavior.** Users switch models/tools over limits and want to know what work is burning tokens/time: [HN: Codex vs Claude Code](https://news.ycombinator.com/item?id=45610266), [Reddit: settled coding agent thread](https://www.reddit.com/r/ChatGPTCoding/comments/1p698cb/what_coding_agent_have_you_actually_settled_on/).

Product implication:

Lancer should show less transcript and more receipts:

- "what the agent was asked to do";
- "what changed";
- "what proof exists";
- "what drifted from plan";
- "what still needs human judgment";
- "what this cost";
- "what the agent is allowed to do next."

#### What Lancer Can Capitalize On

Ranked opportunities:

1. **Needs-Me Queue:** one queue across agents, repos, worktrees, and machines for the decisions that actually require the user.
2. **Mission Contract:** compact phone-native intake with goal, constraints, forbidden areas, done criteria, proof requirements, budget, and interruption rules.
3. **Plan/Recap Drift:** approve the plan first, then approve the delta between plan and what the agent actually did.
4. **Proof-to-Ship Bundle:** tests, screenshots, browser logs, diff slices, PR/CI state, and preview links compressed into a phone-sized proof card.
5. **Typed Approval Semantics:** not just "approve command"; distinguish file write, network, secret access, package install, DB migration, push, deploy, merge, test skip, destructive shell.
6. **Per-Agent Receipts:** each agent gets a card with prompt, scope, files touched, commands run, tests, proof, open questions, branch/commit/PR.
7. **Context Ledger:** durable mission memory that survives compaction and lets a fresh agent reconstruct the state from facts, not chat scrollback.
8. **Evidence-Scoped Review Comments:** comments point to a rule, source file, proof artifact, confidence, and suggested next action.
9. **Simplify/Delete Lane:** before PR, ask an independent reviewer to remove bloat, reduce dependencies, conform to local patterns, and prove deletions.
10. **Budget And Burn Meter:** show time, token/model cost, context growth, and "no new evidence" loops.
11. **Own-Machine Trust Badge:** show the host, repo, branch, relay state, local credentials boundary, and whether files/secrets stayed on the user's machine.
12. **Away Reliability State:** host asleep, network stale, CLI waiting, hook blocked, CI failed, merge conflict, agent loop, quota limit, or session timed out should be first-class phone states.

The strongest near-term product loop:

> Mission Contract -> Away Mode Live Activity -> Needs-Me Queue -> Risk Card -> Proof Bundle -> Visual Recap -> Return-to-Desk Packet.

That loop is sharper than "mobile coding" and harder for single-vendor tools to own because it is cross-agent, proof-centered, phone-native, and grounded in the user's own machine.

## Apple iOS 27 / WWDC26 Capabilities To Exploit

### Live Activities And Dynamic Island

Apple's WWDC26 Live Activities session says Live Activities should be tailored across surfaces and can receive real-time updates via ActivityKit and push notifications. It also notes a landscape Dynamic Island presentation with more information when iPhone is used in landscape: [Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/).

Useful Lancer mapping:

- one active mission state;
- phase, risk, time/budget, blocked question, proof ready;
- structured actions: pause, stop, answer A/B, open proof;
- no free-form chat inside the Live Activity.

Lancer already has Live Activity/APNs plumbing in the repo. The opportunity is better information design, not basic support.

### Widgets, StandBy, And Full-Screen Glance Surfaces

Apple's WidgetKit foundations session frames widgets as glanceable, relevant, personalizable surfaces that extend the app across system contexts: [WidgetKit foundations](https://developer.apple.com/videos/play/wwdc2026/277/).

Useful Lancer mapping:

- **Proof Ready Widget:** one mission, one verdict, one action.
- **Decide Now Widget:** highest-priority blocked card.
- **Quick Mission Widget:** start a common mission from a docked phone.
- **Weekly Away Digest Widget:** "what did agents finish this week?"

Constraint:

Widgets should not become mini dashboards. Use one job per widget.

### Siri, App Intents, View Annotations, And AppIntentsTesting

Apple's iOS guide says Siri connects to app content/actions through App Intents; entity schemas contribute content to Spotlight semantic index; View Annotations map views to entities so users can reference on-screen content conversationally; AppIntentsTesting validates integrations through system pathways: [WWDC26 iOS guide](https://developer.apple.com/wwdc26/guides/ios/).

Apple's advanced App Intents session highlights voice, visual responses, semantic index, structured/in-app search, and onscreen awareness: [Explore advanced App Intents features for Siri and Apple Intelligence](https://developer.apple.com/videos/play/wwdc2026/343/).

Useful Lancer mapping:

- "Hey Siri, what needs me in Lancer?"
- "Tell Lancer to pause the checkout fix."
- "Ask the agent to use the existing pattern."
- "Open the proof for the Settings crash."
- On-screen question cards become Siri-referenceable entities.

Safety rule:

Siri can query, deny, pause, or request proof. Approving high-risk actions still needs the same risk-tiered authentication path.

### Foundation Models And Private Cloud Compute

Apple's Foundation Models material says the framework supports on-device and Private Cloud Compute models, multimodal prompts, model abstraction, context management, semantic search, and agentic primitives: [Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/), [Apple Intelligence overview](https://developer.apple.com/apple-intelligence/), [Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/).

Useful Lancer mapping:

- compress long agent questions into 2-4 choices;
- summarize proof cards locally when possible;
- generate architecture captions from a diff;
- create semantic search over Flight Recorder history;
- classify "needs user" versus routine progress;
- generate mobile-friendly explanations without sending more repo content to a third party when the local/system model is enough.

Constraint:

Do not make Apple Intelligence availability a launch dependency. Use it as a privacy-preserving enhancement with fallbacks to the active coding agent or server-side summary.

### Xcode 27 Agentic Workflows And Device Hub

Apple's Xcode 27 session shows agent conversations in the editor, plan mode before code changes, artifacts/screenshots appearing alongside changes, a sidebar of parallel tasks, and Device Hub for testing across simulators and devices: [What's new in Xcode 27](https://developer.apple.com/videos/play/wwdc2026/258/). The "Xcode, agents, and you" session frames agents around explore, build, refine, and orchestrate: [Xcode, agents, and you](https://developer.apple.com/videos/play/wwdc2026/259/).

Useful Lancer mapping:

- Lancer's Work Thread should mirror the useful part of Xcode: plan, artifacts, changed files, screenshots, proof.
- Lancer's Device Matrix Proof should borrow Device Hub's mindset: evaluate the app across device, appearance, text size, accessibility, and mirrored/resized contexts.
- Lancer can be the iPhone-side approval/proof companion to Xcode's desktop agent workflow, not a clone of Xcode.

## Clean iPhone Product Concepts

### 1. Architecture Change Card

Where it lives: Work Thread, before Review/Diff.

What it shows:

- "Before" module map;
- "After" module map;
- dependency changes;
- new seams and removed seams;
- public function signature changes;
- risk notes;
- "open code" and "ask for simpler architecture" actions.

iOS-native layer:

- Generated diagram is rendered as a card in the transcript.
- Siri can answer "what changed architecturally?"
- Foundation Models can create short captions from the generated artifact.

Why it matters:

This directly answers the Delba-style workflow. The user reads structure first, not files first.

### 2. Plan Delta Card

Where it lives: after Launch Contract and before implementation starts.

What it shows:

- mission contract;
- agent-proposed plan;
- differences from user constraints;
- unknowns;
- test/proof plan;
- "approve plan", "make smaller", "ask question", "send to second reviewer."

iOS-native layer:

- Lock Screen can expose only structured actions.
- App opens to a focused approval sheet for anything nuanced.

Why it matters:

Practitioners repeatedly say plan quality drives output quality. This card makes the phone a useful planning surface without becoming a doc editor.

### 3. Verification Contract

Where it lives: Launch Setup, Repo Playbook, Work Thread.

What it shows:

- required tests;
- proof commands;
- preview URL;
- screenshots needed;
- device matrix;
- accessibility checks;
- manual checks encoded as skills;
- current pass/fail state.

iOS-native layer:

- Full-screen "Proof Ready" widget.
- Live Activity stale state when proof is outdated.
- Foundation Models summarize failure causes.

Why it matters:

This is the practical form of "less babysitting." Lancer lets users encode the checks they already perform manually.

### 4. Question Ladder

Where it lives: Work Thread, Live Activity, notification, app sheet.

Levels:

1. Glance: "Needs decision."
2. Lock Screen chips: 2-4 safe structured answers.
3. Evidence reveal: show screenshot/diff/proof excerpt.
4. Typed instruction: open app or notification text input.
5. Contract update: if answer changes scope, update the Mission Contract.

iOS-native layer:

- LiveActivityIntent for quick buttons.
- Siri/App Intents for status and safe actions.
- App sheet for high-risk or free-form responses.

Why it matters:

It uses the system correctly. The Lock Screen is for quick structured decisions, not full chat.

### 5. Flight Recorder With Searchable Architecture And Proof

Where it lives: Work Thread history and Search/Recent.

What it shows:

- mission timeline;
- architectural change artifacts;
- proof artifacts;
- decisions;
- run comparisons;
- regression candidates.

iOS-native layer:

- semantic search through Foundation Models/Core Spotlight/App Entities where appropriate;
- Siri query: "show me the last proof for checkout";
- Handoff to exact Mac hunk/proof.

Why it matters:

This turns Lancer into memory for agent work, not just a remote control panel.

### 6. Proof Becomes Regression

Where it lives: Proof card action and Repo Playbook.

What it does:

- successful proof can be saved as a future check;
- if the same flow is touched again, Lancer suggests rerunning it;
- results attach to the next Work Thread.

iOS-native layer:

- widget or Live Activity can say "watched flow touched, proof rerun needed";
- Siri can query watched flows.

Why it matters:

It makes Lancer compound in value over time. Competitors can show proof; Lancer can remember and reuse proof.

### 7. Visual Recap Card

Where it lives: Work Thread, Review, PR handoff, and Proof Ready state.

What it shows:

- plan versus recap drift;
- changed architecture modules;
- changed APIs, schemas, and contracts;
- UI/copy impact snapshots;
- security/privacy/auth/payment risk callouts;
- proof status and stale-proof warnings;
- top questions for human judgment;
- code, preview, PR, and full recap links.

iOS-native layer:

- swipe between Architecture, API, UI, Risk, and Proof slices;
- tap any artifact to comment;
- choose whether the comment goes to the agent, a human, the PR, or the mission log;
- Live Activity only exposes "proof ready," "needs decision," or "review blocked";
- Siri can answer "what changed in the PR?" from the recap entity, but risky approvals stay in-app.

Why it matters:

This is the Steve8708 / Agent-Native pattern translated to Lancer. It makes iPhone review useful without turning the phone into GitHub or a browser-sized MDX viewer.

## What Not To Build

- Do not make "Claude/Codex on your phone" the main pitch. OpenAI, Anthropic, GitHub, and Omnara already validate that table-stakes surface.
- Do not build a new root called Architecture. Architecture is a Work Thread artifact.
- Do not build a diagram editor. Agents generate diagrams; users review and ask for changes.
- Do not promise "never read code." Promise "read architecture and proof first."
- Do not make the visual recap a detached report that cannot receive comments or route work back to an agent.
- Do not make Live Activities into chat. Use them for state and structured actions.
- Do not make Siri able to approve risky actions without the same security model.
- Do not depend on iOS 27-only APIs for the first paid loop. Use them as progressive enhancements.
- Do not add a broad automation builder. Encode verification into Repo Playbook and command cards first.

## Recommended Product Direction

The July 4 product direction should be updated from:

> Away Mode with proof and risk control.

to:

> Away Mode with architecture-first visual review, proof-to-ship, and risk control.

That adds the missing expert workflow from the Delba/Rasmic/community research, the Steve8708 visual recap pattern, and the broader fanout finding that mobile remote control is now table stakes.

The final app should feel like:

- Cursor-simple in visual structure;
- Apple-native in system surfaces;
- Claude/Codex-aware in workflow;
- Lancer-specific in cross-agent attention, typed approvals, proof bundles, and own-machine execution.

## Suggested Next Design Changes

1. Add an **Architecture Change Card** section to the canonical board, near Work Thread artifacts.
2. Add **Plan Delta Card** to Launch Setup / Work Thread.
3. Extend **Repo Playbook** into **Verification Contract**.
4. Add **Visual Recap Card** to Review/Work Thread, with tap-to-comment routing to agent, human, PR comment, or mission log.
5. Add **Needs-Me Queue** as the home logic: one queue of decisions, blockers, proof-ready work, and risky actions across agents/repositories.
6. Add **Typed Approval Semantics** to approval cards: file write, network, secret access, package install, DB migration, push, deploy, merge, test skip, destructive shell.
7. Add **Per-Agent Receipts** to Work Thread / Flight Recorder: prompt, scope, files touched, commands, proof, open questions, branch/commit/PR.
8. Add **Proof Becomes Regression** earlier than "distant fast-follow"; it is one of the most compounding ideas.
9. Add a **Siri/Widget Interaction Matrix**:
   - status query: allowed;
   - deny/pause/stop: allowed with proper safeguards;
   - low-risk structured answer: allowed;
   - high-risk approve: require biometric/app path;
   - free-form reply: app or text notification path.
10. Add **Architecture/Proof/Recap Search** to Flight Recorder.

## Source Index

Practitioner and community sources:

- Delba X post: <https://x.com/delba_oliveira/status/2073467304491233543>
- Delba workflow mirror: <https://youmind.com/landing/x-viral-articles/claude-code-feedback-loops-autonomy>
- Delba GitHub profile: <https://github.com/delbaoliveira>
- Rasmic / Startup Ideas Podcast episode: <https://podcasts.apple.com/se/podcast/claude-code-clearly-explained-and-how-to-use-it/id1593424985?i=1000745796041>
- John Lindquist on Claude Code, Mermaid, hooks: <https://www.lennysnewsletter.com/p/advanced-claude-code-techniques-context>
- Boris Cherny phone/parallel-agent workflow summary: <https://www.businessinsider.com/anthropic-engineer-claude-boris-cherny-ai-agent-use-overnight-2026-5>
- Karpathy original vibe-coding post: <https://x.com/karpathy/status/1886192184808149383>
- Karpathy 2026 follow-up post: <https://x.com/karpathy/status/2019137879310836075>
- Karpathy caution article: <https://www.businessinsider.com/andrej-karpathy-vibe-coding-ai-code-awkward-gross-needs-humans-2026-4>
- Reddit: plan-first workflow: <https://www.reddit.com/r/ClaudeCode/comments/1rrbfkj/dont_review_code_changes_review_plans/>
- Reddit: agentic coding planning workflow: <https://www.reddit.com/r/ChatGPTCoding/comments/1iykysy/finally_cracked_agentic_coding_after_6_months/>
- Reddit: maintaining AI-written codebases: <https://www.reddit.com/r/ClaudeAI/comments/1plse94/how_do_you_guys_maintain_a_large_aiwritten/>
- Reddit: Mermaid workflow comment: <https://www.reddit.com/r/ClaudeAI/comments/1l4omv6/what_am_i_missing_here/>
- Reddit: still review code caution: <https://www.reddit.com/r/ClaudeCode/comments/1p1kh50/any_experienced_software_engineers_who_no_longer/>
- Reddit: TDD workflows: <https://www.reddit.com/r/ClaudeCode/comments/1qd64xx/tdd_workflows_with_claude_code_whats_actually/>
- Hacker News: TDD/multi-agent workflows: <https://news.ycombinator.com/item?id=44836879>
- Hacker News: reusable review checklist discussion: <https://news.ycombinator.com/item?id=47494890>
- OpenAI Codex mobile/remote: <https://openai.com/index/work-with-codex-from-anywhere/>
- Claude Code Remote Control: <https://code.claude.com/docs/en/remote-control>
- GitHub Mobile Copilot coding agent tasks: <https://github.blog/changelog/2025-09-24-start-and-track-copilot-coding-agent-tasks-in-github-mobile/>
- GitHub Copilot mobile docs: <https://docs.github.com/en/copilot/how-tos/use-copilot-agents/cloud-agent/use-cloud-agent-on-mobile>
- Omnara App Store listing: <https://apps.apple.com/us/app/omnara-claude-codex-mobile/id6748426727>
- Omnara site: <https://www.omnara.com/>
- Show HN: Omnara: <https://news.ycombinator.com/item?id=44878650>
- Steve8708 / X profile: <https://x.com/Steve8708>
- Steve8708 video source supplied by user transcript: <https://x.com/Steve8708/status/2072726780742713432/video/1>
- Steve Sewell LinkedIn visual-recap post: <https://www.linkedin.com/posts/steve8708_how-ive-changed-the-way-i-do-code-reviews-activity-7478492314152312832-rwbM>
- Steve Sewell / Builder Claude Code workflow: <https://www.builder.io/blog/claude-code>
- BuilderIO visual-recap skill: <https://github.com/BuilderIO/skills/blob/main/skills/visual-recap/README.md>
- BuilderIO visual-plan skill: <https://github.com/BuilderIO/skills/blob/main/skills/visual-plan/README.md>
- BuilderIO skills repo: <https://github.com/BuilderIO/skills>
- Agent-Native framework: <https://github.com/BuilderIO/agent-native>
- Builder.io visual-plan/visual-recap blog: <https://www.builder.io/blog/claude-code-plan>
- Builder.io agent-native apps article: <https://www.builder.io/blog/agent-native-apps>
- Builder.io Quality Review Agent: <https://www.builder.io/blog/announcing-quality-review-agent>
- CodeRabbit Review docs: <https://docs.coderabbit.ai/pr-reviews/coderabbit-review>
- Greptile overview: <https://www.greptile.com/docs/introduction>
- PR-Agent open-source PR reviewer: <https://github.com/The-PR-Agent/pr-agent>
- GitHub Copilot PR summaries: <https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/copilot-on-github/copilot-for-github-tasks/create-a-pr-summary>
- GitHub Copilot code review: <https://docs.github.com/copilot/using-github-copilot/code-review/using-copilot-code-review>
- Reddit: AI code review benchmark/noise: <https://www.reddit.com/r/devops/comments/1qntnva/ai_code_review_tools_benchmark/>
- Hacker News: AI code review bubble: <https://news.ycombinator.com/item?id=46766961>
- Hacker News: LLM summaries/code alignment caution: <https://news.ycombinator.com/item?id=43233903>
- Simon Willison on parallel coding agents: <https://simonwillison.net/2025/Oct/5/parallel-coding-agents/>
- Simon Willison on async code research: <https://simonwillison.net/2025/Nov/6/async-code-research/>
- Harper Reed LLM codegen workflow: <https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/>
- Armin Ronacher agentic coding recommendations: <https://lucumr.pocoo.org/2025/6/12/agentic-coding/>
- Armin Ronacher on what did not work: <https://lucumr.pocoo.org/2025/7/30/things-that-didnt-work/>
- Peter Steinberger AI development workflow: <https://steipete.me/posts/2025/optimal-ai-development-workflow>
- Jesse Vincent Superpowers: <https://blog.fsck.com/2025/10/09/superpowers/>
- Superpowers repo: <https://github.com/obra/superpowers>
- Bas Nijholt agentic mobile workflow: <https://www.nijho.lt/post/agentic-mobile-workflow/>
- Codex workflows: <https://developers.openai.com/codex/workflows>
- Codex GitHub review: <https://developers.openai.com/codex/integrations/github>
- Codex AGENTS.md guide: <https://developers.openai.com/codex/guides/agents-md>
- HN: Ask HN on Claude Code workflows: <https://news.ycombinator.com/item?id=44362244>
- Reddit: Claude Code plan mode: <https://www.reddit.com/r/ClaudeCode/comments/1qr2mzw/your_opinion_on_plan_mode/>
- Reddit: improving plan mode quality: <https://www.reddit.com/r/ClaudeCode/comments/1rdgmdj/the_easiest_way_ive_found_to_improve_plan_mode/>
- HN: Claude Code two-week experience: <https://news.ycombinator.com/item?id=44596472>
- HN: Claude Code 2.0 browser/tooling discussion: <https://news.ycombinator.com/item?id=45416228>
- Reddit: Playwright screenshots filling context: <https://www.reddit.com/r/ClaudeCode/comments/1ojwtop/playwright_screenshots_quickly_filling_up_context/>
- Reddit: managing multiple coding agents: <https://www.reddit.com/r/ClaudeCode/comments/1st213z/how_are_you_managing_multiple_coding_agents_in/>
- Reddit: ChatGPTCoding settled coding agent thread: <https://www.reddit.com/r/ChatGPTCoding/comments/1p698cb/what_coding_agent_have_you_actually_settled_on/>
- Reddit: AI-generated code and technical debt: <https://www.reddit.com/r/programming/comments/1it1usc/how_ai_generated_code_accelerates_technical_debt/>
- Reddit: ExperiencedDevs AI code review tools: <https://www.reddit.com/r/ExperiencedDevs/comments/1o1a601/whats_your_honest_take_on_ai_code_review_tools/>

Apple sources:

- WWDC26 iOS guide: <https://developer.apple.com/wwdc26/guides/ios/>
- Apple Intelligence developer overview: <https://developer.apple.com/apple-intelligence/>
- Live Activities essentials: <https://developer.apple.com/videos/play/wwdc2026/223/>
- WidgetKit foundations: <https://developer.apple.com/videos/play/wwdc2026/277/>
- Foundation Models framework: <https://developer.apple.com/videos/play/wwdc2026/241/>
- Bring an LLM provider to Foundation Models: <https://developer.apple.com/videos/play/wwdc2026/339/>
- Explore advanced App Intents features for Siri and Apple Intelligence: <https://developer.apple.com/videos/play/wwdc2026/343/>
- What's new in Xcode 27: <https://developer.apple.com/videos/play/wwdc2026/258/>
- Xcode, agents, and you: <https://developer.apple.com/videos/play/wwdc2026/259/>
- iOS and iPadOS 27 beta release notes: <https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes>

Repo-local sources:

- `docs/product/2026-07-04-lancer-strategy-feature-source-of-truth.md`
- `docs/design-audit/2026-07-05-final-cursor-wireframe-handoff.md`
- `docs/design-audit/lancer-core-wireframes-2026-07-05/index.html`
- `docs/_archive/away-mode-2026-07/2026-07-04-v1-paid-away-workflow-spec.md`
- `ARCHITECTURE.md`
- `docs/competitive-intelligence/reports/current-product-baseline.md`
