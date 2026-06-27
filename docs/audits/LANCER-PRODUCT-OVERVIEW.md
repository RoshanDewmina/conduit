# Lancer — Product Overview

*What it is, who it's for, and what it does.* Last updated 2026-06-23.

---

## In one line
**Lancer is mission control for your AI coding agents — supervise, approve, and steer them from your phone while they run on your own machines.**

## The problem
AI coding agents (Claude Code, Codex, OpenCode, Kimi) are powerful but unsupervised. Left alone they run risky commands; watched closely they tie you to a desk. The two bad options today are *let it rip* (and hope it doesn't `rm -rf` the wrong thing) or *babysit the terminal* (and never step away).

## The idea
Lancer puts a governor between the agent and the machine. The agent runs on **your** hardware (laptop, VPS, GPU box); a small resident daemon (`lancerd`) watches every action it wants to take. Anything risky is **paused and routed to your phone** as a one-tap approval — with the exact command, a risk rating, and the blast radius. You approve or deny from anywhere, even with the app closed and the phone locked. The phone steers and approves; **it is not a phone IDE.**

## Who it's for
Developers and teams who run autonomous or long-running coding agents and want to **supervise them remotely** — kick off work, stay in the loop on the dangerous moments, and keep moving without sitting at the terminal.

## Core value
> Your coding agents, supervised from your pocket.
- **Approve actions from afar** — gate risky steps with a tap.
- **Watch the work live** — stream the agent's terminal/output as it runs.
- **Policy guardrails per host** — rules decide what's auto-allowed, what asks, what's denied.

---

## How it works — the core loop
1. **Pair a machine.** Run `lancerd pair` on your computer, scan the code in the app. The phone and the daemon connect through an **end-to-end-encrypted relay** (the relay forwards ciphertext it can't read).
2. **Dispatch an agent.** From **New Chat**, pick the agent, the repo/host, and describe the work. Lancer routes it through your policy before anything runs.
3. **It runs; you get pinged on the risky parts.** Safe actions auto-proceed; anything your policy marks "ask" pauses and shows up in your **Inbox** (and as a lock-screen push). You see the command, a risk rating, and what it would change.
4. **Approve / deny / edit.** One tap. The decision rides back to the daemon and the agent continues or stops — fail-closed if you don't answer in time.
5. **Continue.** Follow up in the same thread to keep the agent going (a fresh run each turn, re-checked against policy).

---

## What it does (capability map)
**Steering & conversation**
- Multi-vendor **dispatch** (Claude Code, Codex, OpenCode, Kimi) and **follow-up/continue** in durable chat threads.
- Live transcript with tool-call, diff, and terminal "blocks."

**Governed approvals (the heart of it)**
- Per-action **approve / deny / edit-&-run**, with risk rating, command, typed tool input, and blast radius.
- Delivery in-app, on the **lock screen while the app is closed**, and on **Apple Watch**.
- **Policy engine** with autonomy presets (Balanced / Permissive / Restrictive) and an allow/ask/deny rule set per host; an **Emergency Stop** halts every running agent at once.

**Fleet & hosts**
- A **Machines** view of your paired relay hosts and SSH hosts — online/health status, agents-on-host, usage, and **setup-drift** detection.
- Power-user **live terminal** (block-rendered PTY) for direct hands-on work.

**Safety, money & trust**
- **Hash-chained audit log** of every action and decision (verify/export).
- **Quota guard** — per-provider spend with daily/monthly caps.
- **Secrets broker** — agents request secrets; you authorize/revoke; keys stay on device.
- **Provider keys** go straight from your device to the provider — Lancer never sees them.
- Security is **fail-closed**: trust-on-first-use host keys, Keychain + biometric gate, redacted notifications.

**Reach**
- iPhone (primary), iPad (split view), **Apple Watch** (approvals), and a **macOS menu-bar companion** that manages the daemon.

---

## What you actually see (the screens)
- **Home** — "N agents need you," a warm attention card for what's blocked, and your machines.
- **New Chat** — describe the work; pick agent + host; it routes through policy.
- **Inbox** — the approval queue: risk-rated cards with Deny / Approve.
- **Machines** — your hosts, their health, usage, drift, and a way into the terminal.
- **Settings** — Policy & Governance (autonomy, enforcement log, emergency stop) and General (provider keys, notifications, appearance, billing, trust & devices).

*(Real screenshots in `app-screenshots/`; full screen-by-screen in the design brief.)*

---

## Product state today
- **Proven:** the end-to-end governed loop — dispatch → policy → approve (incl. **lock-screen push with the app closed, verified on a real device**) → agent continues. First TestFlight build is out.
- **Working, polishing:** fleet/health/drift, quota, secrets, audit, multi-vendor continue, Watch, Mac companion.
- **Deferred (future):** **hosted-cloud execution** (run agents in the cloud on prepaid credits) and scheduled/looping agents — designed, not in the V1 product.

## What makes it different
1. **Governed approvals as the product**, not notifications bolted on — risk, context, and a real decision that blocks the agent.
2. **App-closed, lock-screen approval** — supervise without opening the app.
3. **Runs on your machines** — your hardware, your keys, end-to-end encrypted; nothing proprietary in the middle.
4. **Setup-drift detection** — catches when a host's agent environment has quietly broken.
