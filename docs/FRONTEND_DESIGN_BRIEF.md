# Conduit — Frontend Design Brief

> **Purpose of this document.** It describes **what Conduit is, who uses it, what it does, the data it works with, the flows, the states, and the platform/technical constraints** — so a designer has rich, accurate context to design a great frontend. It is intentionally **descriptive, not prescriptive**: it does **not** specify visual style, color, typography, layout, components, or navigation structure. Those decisions are the designer's. Where it mentions screens that exist today, that's **raw material / current reality**, not a requirement to keep them.

---

## 1. What Conduit is (in one breath)
Conduit is an **iOS app for steering AI coding agents** (Claude Code, OpenAI Codex, opencode) that run on a developer's **own computer or server**. The phone is not where code is written — it's where the developer **gets notified when an agent needs a decision, approves or denies it, watches what their agents are doing, and starts/schedules new work** — from anywhere.

The thing that makes it different from a normal "phone terminal": a small **helper program (the "bridge") runs on the developer's machine** alongside their agents. The bridge can **enforce the developer's approval policy automatically** — auto-approving safe actions, auto-blocking dangerous ones, and only **interrupting the human for the genuinely ambiguous decisions**. So the app is less "remote control" and more "**mission control for agents that mostly run themselves**."

**One-line positioning:** *the cockpit where your coding agents run unattended, safely — under rules you control, on hardware you own, across every agent vendor.*

---

## 2. Who uses it (personas & context of use)

**Primary users — professional / "AI-first" software developers:**
- **The indie hacker / founder** running agents on a cheap cloud server, shipping from their phone between meetings, on a walk, in bed.
- **The professional engineer** with agents working on a powerful work machine or remote dev box, who steps away and wants to keep things moving without being chained to the desk.
- **The security-conscious / enterprise developer** who *cannot* send their code to a third-party cloud, so "runs on my own machine, my keys, nothing leaves my box" is the reason they'll use it at all. This persona is the one most willing to pay.

**Context of use (critical for design):**
- **Interrupt-driven, not session-driven.** Users open the app *because they got a notification* ("an agent needs you"), deal with it in seconds, and leave. They are rarely sitting and browsing.
- **Often one-handed, on the move, glancing.** Phone, walking, poor light, spotty signal. Decisions must be makeable fast and with confidence.
- **Sometimes deep-focus.** When something interesting is happening they *will* sit and watch an agent work, read a diff, or review what happened while they were away.
- **Across devices.** Same agents are also visible on their laptop; the phone is one window onto a system that keeps running without it.
- **Technical audience.** They read commands, diffs, file paths, and exit codes natively. Density and precision are assets, not liabilities — but the *decision* still has to be instant.

---

## 3. The mental model the UI must convey
Users need to understand four concepts. Designs should make these legible without a manual:
1. **Agents** — AI coding tools (Claude Code / Codex / opencode) running on a host. Each has a vendor, a model, a working directory, and a status (idle / working / waiting-for-you / done / error).
2. **The bridge** — the helper running on the host that watches the agents, enforces policy, records everything, and talks to the phone. It can be **connected** (you're attached live) or **running-without-you** (still enforcing policy, queuing things for you).
3. **Approvals (decisions)** — when an agent wants to do something the policy says a human must judge, it becomes an **approval** the user acts on: allow once / allow always / edit-then-run / deny.
4. **Policy** — the user's rules that decide which agent actions are auto-allowed, auto-denied, or escalated to them. The whole point is that **most things never reach the human** — the app should make the user feel *in control precisely because they're not being asked about everything.*

The emotional target (functional, not visual): **calm confidence.** The user should feel their agents are working safely and that they'll be tapped only when it truly matters — and when they are tapped, they can decide in seconds and trust the decision.

---

## 4. Core jobs-to-be-done (the flows that matter most, ranked)

1. **"An agent needs me — decide fast."** Notification → open → see the one decision (what the agent wants, where, what it would touch) → allow / allow-always / edit / deny → done. *This is the #1 flow; it happens many times a day and must be effortless and trustworthy.*
2. **"What happened while I was away?"** Review the stream of decisions the bridge made autonomously (what it allowed/denied for me), catch anything I disagree with, and reverse or tighten policy.
3. **"How are my agents / what are they costing me?"** Glance a dashboard: which agents are running/idle/waiting, on which host, what model, how much they've spent today (across all vendors).
4. **"Start a new task."** Tell an agent to do something from the phone (pick agent, working directory, prompt, optional budget) — and/or **schedule** it to run on a recurring basis.
5. **"Set the rules."** View and adjust the approval policy (what auto-allows, what asks, what's forbidden), per-project and globally.
6. **"Get set up."** First run: install the bridge on my machine, pair my phone, choose how cautious the default policy should be — and connect to my host.
7. **"Go deep / power-user."** Drop into a live terminal on the host, watch an agent's raw output, review a code diff, browse files, preview a running web app. (Full-fidelity, for when the cards aren't enough.)

---

## 5. The surfaces / content (what each must show & let the user do)

Below is **what information and actions each area involves** — its purpose, the data it shows, the actions it offers, and its important states. **How these are arranged into screens/navigation is the designer's call.**

### 5.1 The decision surface (an "approval")
**Purpose:** let the user judge and act on one agent action in seconds.
**Data it has available:** which agent (vendor + name), the host, the working directory, the **action kind** (run a shell command / apply a code patch / write a file / delete a file / make a network request / touch credentials / open a browser), the **actual content** (e.g. the exact command, or the file path + a diff), a **risk level** (low / medium / high / critical), a **"blast radius"** computed by the bridge (which files it would touch, whether it touches git, whether it touches the network), and **which policy rule** caused it to be escalated.
**Actions:** **Allow once**, **Allow always** (creates a standing rule so this never asks again), **Edit & run** (modify the command/input before allowing — e.g. tweak a path), **Deny**. Dangerous actions may require an extra confirmation (e.g. Face ID).
**States:** waiting-for-decision; just-decided (allowed/denied); expired/timed-out (the bridge auto-decided after a timeout); offline (can't reach the bridge right now).
**Why it's hard:** the user must grasp *what will happen and how risky it is* at a glance, then commit — possibly one-handed, possibly for something destructive like `rm -rf`. Getting this wrong is scary; the design carries the trust.

### 5.2 The queue of decisions (the "inbox")
**Purpose:** the list of approvals currently needing the human, across all agents/hosts.
**Data:** each item = agent + action summary + risk + how long it's been waiting. Possibly grouped (by agent, host, risk, or time).
**Actions:** open one to decide; quick-act without opening (e.g. swipe to allow/deny); jump to whichever agent is blocked.
**States:** empty ("nothing needs you" — a *good* state, should feel reassuring, not barren); a few; a flood (an agent fired many approvals).

### 5.3 The activity / "while you were away" feed
**Purpose:** transparency into what the bridge did **autonomously** — the trust surface (and the enterprise selling point).
**Data:** a time-ordered log of decisions: auto-allowed, auto-denied, escalated-to-you, your-own past decisions, dispatched/scheduled runs. Each entry = timestamp, agent, action, the outcome (allow/deny/ask), and **which rule decided it**.
**Actions:** review; "I disagree with this" → tighten or loosen the relevant policy rule; filter (by agent, outcome, risk, time).
**States:** empty (new user); busy (lots of autonomous activity overnight). This feed is also where a user *audits* the system after the fact — every action is recorded.

### 5.4 The agents / fleet view
**Purpose:** see and manage all agents across all hosts.
**Data per agent:** vendor (Claude/Codex/opencode), display name, host it runs on, model in use, **status** (idle / working / waiting-for-you / done / error / offline), whether it's logged in, current session/run count, and **spend today**. A summary strip aggregates: total agents, runs today, concurrent runs, total spend today vs. a budget, credits remaining.
**Actions:** open an agent for detail; start a new task on it (see 5.5); create/configure an agent; jump to one that needs attention.
**States:** no agents yet (onboarding nudge); several agents healthy; one waiting/errored (needs to stand out).
**Note:** "usage & cost across every vendor in one place" is the single most-requested feature in this market — this surface carries it.

### 5.5 Start a task / dispatch & schedule
**Purpose:** kick off new agent work from the phone, or schedule recurring work.
**Data the user provides:** which agent, the working directory on the host, the task/prompt (free text), and an optional daily budget cap. For scheduling: an interval (e.g. every N minutes/hours) or recurrence.
**What comes back:** the bridge applies the same policy + budget gate, so a dispatch can return **running**, **needs-approval** (it became an approval in the inbox), **denied** (policy forbade it), or **budget-exceeded** (over the cap). Scheduled jobs show their next/last run.
**Actions:** dispatch now; save a schedule; view/cancel running dispatches; edit/delete schedules.
**States:** composing; submitting; result (with the outcome above); a list of active/scheduled runs.

### 5.6 An agent's detail / run history
**Purpose:** drill into one agent — what it's doing now and what it has done.
**Data:** the agent's config (vendor, model, host, working directory, budget), its **runs** (each with status running/succeeded/failed/cancelled, start time, duration, exit code, streamed log lines, and any **artifacts** like screenshots/files it produced), its **schedules**, and quick links to that agent's files/workspace and git state.
**Actions:** start/cancel a run; open a run's logs; review artifacts; manage schedules; edit the agent.

### 5.7 Policy editor
**Purpose:** let the user see and shape the rules that drive the autonomy.
**Data:** an ordered set of rules, each with: which agents/tools/action-kinds it matches, an optional path/glob and risk-band condition, and an **effect** (allow / ask / deny). There's a **global** policy and an optional **per-project** policy (a file in the repo). There are sensible **presets** (e.g. "cautious": auto-allow read-only, ask on writes, deny secrets & network). The default for anything unmatched is **ask** (fail-safe).
**Actions:** view active rules and *which file they came from*; toggle presets; add/edit/remove a rule; understand *why* a given action would be allowed/asked/denied.
**Why it matters:** this is where "I'm in control" becomes concrete. It must be understandable by a developer without being intimidating; the consequences of a rule should be clear.

### 5.8 Hosts & connection
**Purpose:** manage the machines agents run on and how the phone connects.
**Data:** SSH hosts (address, user, auth method — password or key), host-key trust state (first-connect "do you trust this host?" confirmation), the **bridge status** on each host (installed? running? attached?).
**Actions:** add/edit a host; trust a host key on first connect; install/repair the bridge; connect/disconnect.

### 5.9 Onboarding / first run
**Purpose:** get from "downloaded the app" to "my agents are visible and safe."
**Steps the flow must cover:** install the bridge on the host (a one-line command the user runs on their machine; may be conveyed via copy/QR), pair the phone to that bridge securely, connect to the host, and choose how cautious the default policy should be. The reward moment: the app **auto-detects the agents already running** and shows them — including, ideally, *"you're logged into Claude Code and Codex; here's what you've spent today,"* which is the "aha."

### 5.10 The terminal / power-user surface
**Purpose:** full-fidelity control when the cards aren't enough.
**Data & behavior:** a live terminal on the host rendered as **"blocks"** — each command and its output is a unit (with an exit-status indicator), not an endless scroll. Interactive full-screen programs (vim, htop, tmux) and inline agent TUIs render live inside their block. There's also: a **code diff reviewer** (approve changes hunk-by-hunk), an **SFTP file browser**, and a **live web preview** (view a web app running on the host). A keyboard accessory rail provides terminal keys (Ctrl-C/D/Z, arrows, etc.) that phones lack.
**Note:** this is intentionally the *deep* surface — most users live in cards/inbox and only come here when they want raw control.

### 5.11 Settings
Account/subscription, the policy editor entry, notification preferences (which risk levels/agents notify, quiet hours), security (biometric gate, output redaction, audit log access), bridge management, snippets/workflows library, appearance.

---

## 6. The data model & vocabulary (so designs use real objects)

- **Agent:** `vendor` (claudeCode | codex | opencode), `name`, `host`, `model` (e.g. `claude-sonnet-4.6`), `workingDirectory`, `status`, `loggedIn`, `runningCount`, `spendToday`, `dailyBudget?`.
- **Approval / decision:** `agent`, `host`, `actionKind` (command | patch | fileWrite | fileDelete | network | credential | browser), `content` (the command, or file path + diff), `risk` (low | medium | high | critical), `blastRadius` (`files[]`, `touchesGit`, `touchesNetwork`), `matchedRule`, plus the decision the user makes (`allow | allowAlways | editAndRun | deny`).
- **Policy rule:** `effect` (allow | ask | deny), and optional matchers: `agent`, `tool`, `kind`, `path/glob`, `minRisk`/`maxRisk`. Lives in a **global** policy and optional **per-repo** policy; unmatched ⇒ **ask**.
- **Audit entry:** `timestamp`, `action` (auto-allow | auto-deny | escalate | human-allow | human-deny | dispatch-launched | dispatch-denied | budget-exceeded | …), `agent`, `kind`, `command`, `effect`, `rule`.
- **Usage / quota:** per vendor — `loggedIn`, `model`, `sessionCount`, `runningCount`, `usageTodayUSD`, `usagePeriod`. Aggregate — `agentsUsed/limit`, `runsToday`, `concurrentRuns/limit`, `usageTodayUSD/dailyLimit`, `creditsRemaining`.
- **Dispatch / run:** `agent`, `cwd`, `prompt`, `budgetUSD?` → result `status` (running | needs-approval | denied | budget-exceeded | error), `runId`, `rule`. A **run** has `status` (running | succeeded | failed | cancelled), `logLines[]`, `exitCode`, `duration`, `artifacts[]`.
- **Schedule:** `agent`, `cwd`, `prompt`, `interval`, `budget?`, `lastRun`, `nextRun`.
- **Host:** `address`, `user`, `authMethod` (password | key), `hostKeyTrusted`, `bridgeStatus` (notInstalled | installed | running | attached).
- **Block (terminal):** `command`, `output`, `exitStatus`, `running?`, `isInteractive?`.

---

## 7. Real sample content (use these to make designs feel true, not lorem-ipsum)

**Approvals:**
- Claude Code wants to run `rm -rf build/ dist/` in `~/repos/conduit` — kind: command, risk: high, blast radius: 2 dirs, touches git: no.
- Codex wants to apply a patch to `src/auth/session.swift` (+18 / −4) — kind: patch, risk: medium, touches git: yes.
- Claude Code wants to run `curl https://api.stripe.com/... | sh` — kind: network, risk: critical → policy would **deny**.
- opencode wants to write `.env.production` — kind: fileWrite, risk: high, touches credentials.

**Audit / activity lines:**
- `09:12  auto-allow   claude · ls -la            (rule: allow-read-only)`
- `09:14  auto-deny    codex  · curl … | sh       (rule: deny-network)`
- `09:15  escalate     claude · patch session.swift (rule: ask-on-write)`
- `02:03  dispatch-launched  claude · "run the nightly test suite"`

**Agent status rows:**
- `Claude Code · claude-sonnet-4.6 · 2 sessions · $3.18 today · ● working`
- `Codex · gpt-5.1-codex · 1 session · $0.74 today · ● waiting for you`
- `opencode · — · not logged in · ○ offline`

**Usage strip:** `agents 2/5 · runs today 7 · concurrent 1/3 · usage $4 / $25 · credits $12.50`

**Terminal block:** `$ swift test` → output → `✓ 327 tests passed · exit 0 · 23.9s`

---

## 8. Platform surfaces beyond the main app (all part of the experience)
These reinforce the #1 job ("an agent needs me"). They each must convey **who needs what, how urgent, and let the user act fast**:
- **Notifications:** must carry *context* ("Claude needs to delete 2 files in conduit" — not "Claude is waiting"). Distinguish **needs-a-decision** from **finished**. Allow acting from the notification (allow/deny) where possible.
- **Live Activity / Dynamic Island:** a glanceable live status of an agent or a pending decision on the lock screen / island.
- **Apple Watch:** approve/deny from the wrist; see the inbox, agent activity, a current session, and quick snippets.
- **Home-screen widgets:** at-a-glance agent status / pending count / spend.

---

## 9. Constraints & requirements the design must respect
- **Platform:** iOS (iPhone primary; iPad and a Mac/desktop companion are on the roadmap — designing with larger screens in mind is welcome but iPhone is the priority). watchOS app and widgets exist.
- **Accessibility:** full **Dynamic Type** (text scales for low vision), **VoiceOver** labels on every actionable element, sufficient contrast, large enough touch targets for one-handed/on-the-move use. Terminal/fixed-geometry areas may cap scaling but must remain usable.
- **Light & dark** appearance both first-class. The terminal/agent context skews dark by nature; the rest should work in both.
- **Glanceability & speed:** the primary decision must be makeable in seconds, often one-handed, in bad conditions. Information density is acceptable (technical users) but the *action* must be unmistakable.
- **Trust & safety in the UI:** destructive/high-risk actions must be visually distinct and harder to do by accident; biometric confirmation is available for dangerous ones. **Never display secrets** (API keys, passwords) — output is redacted.
- **Truthful states:** empty/loading/error/offline must all be designed. "Nothing needs you" is a *frequent and positive* state. "Can't reach your bridge right now" is common (phones lose signal) and must be graceful, not alarming.
- **Internationalization-friendly:** text length varies; avoid designs that assume fixed-width labels.
- **Existing raw material (factual, not a mandate):** today the app is built in SwiftUI with a custom design-system (tokens + components like cards, chips, buttons, status bars, a pixel-art "agent state" motif, diff chips). Current top-level navigation is four areas (hosts, inbox, library, settings) with the terminal as home — but **the product has outgrown a terminal-first structure**, and reconsidering the information architecture for the command-center reality is explicitly in scope. The designer is free to restructure.

---

## 10. Competitive context (the bar to clear, and where to differ)
Several apps do "control a coding agent from your phone": **Happy** (free, open-source, polished but a *thin client* — you approve every action manually, shown as raw JSON), **Omnara** (free, native, but routes your sessions through their cloud), **Anthropic's own Remote Control** and **OpenAI's Codex mobile** (polished but single-vendor and cloud-tied), and **CloudCLI** (cross-vendor but a web UI). Common user complaints across all of them: notifications that lack context or don't fire reliably; approval UIs that are raw and hard to judge ("just shows the JSON with a yes/no"); sessions that get lost; and no usage/cost visibility.

**Where Conduit is different (and the design should make felt):** the agents **run themselves under the user's policy** (not babysat tap-by-tap), everything runs on the **user's own machine** (privacy/trust), it's **cross-vendor** (Claude + Codex + opencode in one place), and it shows **usage/cost** nobody else does. The design's job is to make a technical, interrupt-driven, trust-critical product feel **calm, fast, and in-control** — the opposite of "another raw terminal" or "another yes/no JSON prompt."

---

## 11. What to design for first (priority order)
1. The **decision/approval** experience (§5.1) and its **queue** (§5.2) — the daily heartbeat.
2. The **agents/fleet + usage** view (§5.4) — the "is everything okay / what's it costing" glance.
3. The **activity/while-you-were-away** feed (§5.3) — the trust surface.
4. **Onboarding** (§5.9) — first impression + the "aha."
5. **Start a task / dispatch & schedule** (§5.5) and **policy editor** (§5.7).
6. The overall **information architecture** that ties these together (and demotes the terminal to the power-user depth, §5.10).
7. The **glanceable surfaces** (notifications, Live Activity, Watch, widgets, §8).

Everything here is *what the app does and needs to convey* — the visual language, layout, motion, and structure are yours to create.
