# Lancer — landing page copy

> Attach this with the design prompt. It maps Lancer's copy onto the **same section order as the reference site** (stoopper.framer.website). Use this text verbatim. Keep the reference's visual style, colors, type, and motion — only the words and the phone screens change.
>
> **Honesty rules (do not break):** No invented user counts, ratings, "#1 in App Store", awards, logos, or testimonials. Anything marked **[PLANNED]** is not shipped — keep it future-tense. The product is in **TestFlight beta**; there is no public App Store listing yet, so use TestFlight / "join the beta", never "Download on the App Store".

---

## 0. Announcement bar (top strip)
`Now in TestFlight beta — governed approvals for Claude Code, Codex & opencode.`

## 1. Nav
- **Wordmark:** Lancer
- **Links:** Features · How it works · Pricing · Trust
- **Nav CTA (pill):** Join the beta

## 2. Hero
- **Badge / eyebrow pill:** `Works with Claude Code · Codex · opencode`
- **Headline:** Approve your agents. Keep your code.
- **Subhead:** Lancer puts everything risky your AI coding agents try — across Claude Code, Codex, and opencode — into one inbox on your phone. Approve, deny, or edit in a tap. Set a policy and most actions never reach you. Your code never leaves your machine.
- **Primary CTA:** Join the TestFlight beta
- **Secondary CTA (text/anchor):** See how it works
- **Trust line (replaces "Trusted by 17,000+ users"):** No account required. Your code stays on your machine.

### Floating cards around the phone (replace stoopper's $517k / +20% / 350% stat cards)
Use these as small UI chips/cards orbiting the phone — they show the product, not fake metrics:
- An **"ask"** card (amber): `npm install` · touches `package-lock.json`
- A green chip: `✓ Approved`
- A red chip: `Denied · rm -rf /`
- A neutral chip: `Policy matched: auto-allow reads`
- A vendor chip: `Claude Code`

## 3. Features (3 — replaces "verified jobs / salaries / certifications")
1. **One inbox for every agent** — Risky actions from Claude Code, Codex, and opencode all land in one place, each with the exact command, the files it touches, and a risk read.
2. **Decide in a tap — even when you're away** — Approve, deny, edit-then-run, or allow-always. Your decision relays back and the agent resumes in a second, even if the app was closed.
3. **Your code never leaves your machine** — A small bridge (`lancerd`) runs on your host and enforces the policy you set. Lancer never gets your source or your credentials.

## 4. Benefits (3 — replaces "Learning Modules / Market Insights / Recommendations")
1. **Policy handles the boring majority** — Start from a preset — Cautious, Balanced, or Bypass — then tighten per repo. Reads, tests, and in-tree edits auto-allow, so most actions never reach your phone.
2. **An audit trail by default** — Every autonomous decision and every tap is written to an append-only, secret-redacted log on your host. Export it as evidence if you ever need it.
3. **A glance across your fleet** — Idle, waiting on you, or blocked — see every machine you run agents on, and what it's costing, in one place.

## 5. How it works (4 steps — replaces "Create Profile / Explore / Apply / Updates")
1. **Install the bridge** — On your host: `cd daemon/lancerd && go build -o lancerd . && ./lancerd install`. It runs in the background and survives reboots.
2. **Point your agent's hook** — One line for each agent — Claude Code, Codex, or opencode — so Lancer sees what they're about to do.
3. **Pair your phone** — Install the app, scan the pairing code, and pick a caution preset. No account.
4. **Go do something else** — Next time an agent hits something risky, your phone buzzes. You tap. It resumes. Everything's logged.
- **Section CTA:** Read the getting-started guide

## 6. Why Lancer (3 value props — replaces "Why Choose Us")
1. **Cross-vendor, not single-vendor** — Claude's and OpenAI's mobile control each govern only their own agent. Lancer is the one policy, approval, and audit layer across all of them.
2. **Local-first, not cloud-run** — Your agents run on your own machine. Only the approval metadata you choose to send ever leaves your host. **[PLANNED]** end-to-end encryption of that relay.
3. **Enforcement you can trust** — Lancer's hook returns a hard deny that holds **even under `--dangerously-skip-permissions`**. Default is fail-closed: if the bridge isn't reachable, mutating actions hold rather than auto-run.

## 7. "Proof" band (replaces the 6 fake testimonials — HONEST equivalents only)
**Section headline:** What Lancer guarantees
*(Use these three as cards in place of customer testimonials — they are commitments, not quotes.)*
- **Your source stays put** — Code and credentials never leave your host. The relay carries only the action metadata you send for a decision.
- **A deny means deny** — The policy holds even when an agent is launched with `--dangerously-skip-permissions`. It can't talk its way around the rule.
- **Everything is logged** — An append-only, secret-redacted record of every autonomous decision and every human tap, on your machine.

**Vendor row (small, under the band):** Works with Claude Code · Codex · opencode

## 8. Pricing (3 tiers — replaces $19 / $29 / $49 monthly)
**Section headline:** Free to run. Pay once if you want the full app.
**Subhead:** No subscription. No account required to start.

| | **Free** | **Lancer Pro** *(recommended)* | **Team & Self-host** |
|---|---|---|---|
| Price | $0 | **$14.99 once** | **[PLANNED] — talk to us** |
| Approvals across your hosts | ✓ | ✓ | ✓ |
| Policy + audit log | ✓ | ✓ | ✓ |
| Cross-vendor (Claude Code, Codex, opencode) | ✓ | ✓ | ✓ |
| Full app unlock (fleet depth, advanced surfaces) | — | ✓ | ✓ |
| Shared team policies, signed audit export, on-prem relay | — | — | **[PLANNED]** |

- **Footnote:** Lancer Pro is a one-time purchase, not a subscription. Team/self-host pricing isn't set yet — tell us what you need.
- **Pricing CTA:** Join the TestFlight beta

## 9. FAQ
- **Does my code go through your servers?** No. Source and credentials stay on your host. The relay only carries the approval metadata you send. End-to-end encryption of that relay is **[PLANNED]**.
- **How is this different from Claude's or OpenAI's mobile app?** Those are single-vendor (Claude-only / Codex-only), and Anthropic's isn't available to Team/Enterprise. Lancer governs *all* your agents, with your code on your host.
- **Will it constantly interrupt me?** No — policy auto-handles the safe majority. You tune how cautious it is.
- **Which agents are supported?** Claude Code, Codex, and opencode today.
- **Is it available?** TestFlight beta now; public App Store release is **[PLANNED]**.
- **What does it cost?** Free to use; a one-time Lancer Pro unlock is $14.99. Team/self-host is **[PLANNED]**.

## 10. Final CTA band
- **Headline:** Let your agents run. We'll get you when it matters.
- **Subhead:** Join the TestFlight beta — no account required.
- **Button:** Get Lancer

## 11. Footer
- **Wordmark:** Lancer
- **Tagline:** Approve your agents. Keep your code.
- **Columns / links:** Features · How it works · Pricing · Trust · Privacy · Join the beta
- **Bottom line:** conduit.dev · Your code stays on your machine.

---

### Phone screen content (for the CSS placeholder mockups)
Build the iPhone(s) in CSS/code; the screen shows a simple **approval card** placeholder:
- Status bar `9:41`
- Title: `Inbox`
- A card: agent `Claude Code` wants to run
  - command (monospace): `rm -rf node_modules/`
  - meta: `touches 1,204 files · risk: ask`
  - two buttons: **Deny** (red) / **Allow** (green)
- A second, resolved card behind it: `✓ Approved · npm test`

Label these clearly as placeholders — real screenshots / a screen-recording will replace them later.
