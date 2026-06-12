# Conduit — Website & Design Brief

> **Purpose:** everything Claude Design (and whoever builds the site) needs to design and ship conduit.dev — codebase findings, verified research, strategy, copy for all 6 pages, App Store copy, an ads plan, and a paste-ready Claude Design prompt.
> **Compiled:** 2026-06-11 · **Status:** ready for design. Research-and-write only; no production code touched.
> **Honesty rule applied throughout:** no fake stats, customers, or certifications. Planned/unbuilt features are marked **[PLANNED]**.

---

## 0. TL;DR for the designer

- **Product:** a phone-first **approval & governance layer** for AI coding agents (Claude Code, Codex, opencode) that run on *your own* machines. You get a push when an agent wants to do something risky; you approve/deny/edit in a tap; a policy auto-handles the safe stuff; everything is logged. **Your code never leaves your host.**
- **Audience:** developers and small teams running **multiple** agents across their **own** machines — not casual single-vendor users (first-party tools already serve those, free).
- **Aesthetic:** **calm-editorial, but serious devtool.** Warm paper background, Instrument Serif headlines + Inter body + a real monospace for commands. This is a *deliberate counter-position* — every competitor site is dark and code-dense; warm-and-calm is our visual differentiator and matches the product's emotional promise (control without anxiety).
- **Hero:** a modern iPhone showing the real app — the **approval inbox card** — with a live micro-animation (a command types in, a tap resolves it to ✓ Approved). Replaces the old Nokia-on-a-beach mockup.
- **Reminder for owner:** **you are supplying the real iPhone screenshots yourself.** The design uses clearly-marked placeholders until you drop them in. (See §8.)

---

## 1. Codebase findings

### 1.1 What the app actually does (from the repo, not marketing)
Conduit is an iOS app + two Go daemons:
- **iOS app** (`Packages/ConduitKit/`, SwiftUI, Swift 6.2): the approval **Inbox**, **Activity** (audit) feed, **Fleet** glance, **Settings** (policy editor + bridge pairing), and a power-user **block terminal** demoted to depth. Recent commits (`feat/governed-approvals`) explicitly moved the IA to **Inbox / Fleet / Activity / Settings, terminal at session depth** — governance-first.
- **`conduitd`** (`daemon/conduitd/`): a resident daemon on the developer's host. Enforces a **policy** (deny > ask > allow, default *ask* / fail-closed), keeps an **audit log** (`~/.conduit/audit.log`, JSONL, secret-redacted), computes **blast radius** (files touched, touches-git, touches-network), persists **allow-always** rules, and queues approvals offline. Ingests **PreToolUse hooks** from Claude Code, Codex, and opencode.
- **`push-backend`** (`daemon/push-backend/`): control plane — relays approval decisions, sends APNs pushes; also (currently) Stripe billing + a hosted cloud-execution path. *(Strategically, the hosted-cloud-execution piece is being de-scoped — see §3; the website should not market "we run your agents in our cloud.")*

**The verified differentiator:** a Claude Code `PreToolUse` hook returning `deny` **blocks the action even under `--dangerously-skip-permissions`**. Conduit's enforcement is robust and un-circumventable, not a fragile wrapper. (Source: Claude Code hooks docs — §2.)

### 1.2 Existing marketing site (the thing we're replacing/redesigning)
- **Location:** `marketing/` — **Next.js 16.2.6 (App Router) + React 19.2.4 + Tailwind v4**. Fonts: Geist + Geist Mono. Theme: dark (`zinc-950` bg, `zinc-100` text, `emerald-400` accent).
- **Pages:** `/` (landing), `/download`, `/privacy`, `/subscribe`, `/mainframe`.
- **No animation library installed** (`motion/react` would be added).
- **Its copy is STALE and off-strategy:** the current H1 is *"Run AI agents over SSH. Your infrastructure. Your keys."* with eyebrow *"SSH Agent Terminal for iOS."* This is the **old terminal-first positioning we've abandoned.** All copy must move to the governed-approvals story. **This is a reposition, not a re-skin.**
- **Implementation constraint (`marketing/AGENTS.md`):** *"This is NOT the Next.js you know… Read the relevant guide in `node_modules/next/dist/docs/` before writing any code."* Next 16 has breaking changes — honor this if/when the site is implemented.
- **OG/icon:** `layout.tsx` references `/og.png` (1200×630) and `/icon.png` (512×512) that **don't exist yet** — design needs to produce them.

### 1.3 Assets
- **Real app screenshots exist** at `docs/screenshots/governed-approvals/` (`01-inbox-review`, `02-inbox-tabs-live`, `03-fleet`, `04-activity`, `05-settings`). **Owner has chosen to supply final hero screenshots themselves**, so treat these as reference only and use **placeholders** in the design (§8).
- **No logo/wordmark asset** found — design should produce a wordmark (recommendation: lowercase **`conduit`** set in Instrument Serif; a small monospace variant for technical contexts).
- Domain: **conduit.dev** (already referenced in `layout.tsx` metadata).

### 1.4 Design constraints summary
- Deliverable is **design-only**; framework is decided later. If/when built: Next.js 16 App Router + React 19 + Tailwind v4 + `motion/react`, honoring `marketing/AGENTS.md`.
- The pasted "dot." template is a **Vite single-`App.tsx`** structure — that's a *reference for aesthetic + motion patterns*, not the target framework. The design should be portable to either.

---

## 2. Research notes (verified, with sources)

### 2.1 Claude Design (the stated build target)
- **What it is:** Anthropic Labs prompt-to-prototype tool at **claude.ai/design**. Generates "designs, prototypes, slides, one-pagers, marketing collateral," realistic prototypes, wireframes/mockups. **The model is selectable — run it on Claude Fable 5** (owner-confirmed; the public announcement cites Opus 4.7 as the default). See §2.2 for why Fable 5 fits this job.
- **Inputs it accepts:** text prompts, **image uploads**, document uploads (DOCX/PPTX/XLSX), **codebase references**, and **website capture** (URL). → We can feed it this brief + a reference screenshot + the codebase.
- **Refinement:** inline comments on elements, direct text editing, **"adjustment knobs" for spacing/color/layout**, then "apply across the full design."
- **Export:** internal org URL, folder, **Canva, PDF, PPTX, standalone HTML**.
- **Design-system feature:** it can **read your codebase + design files** and apply colors/typography/components automatically — useful for keeping site and app visually coherent.
- **Handoff:** designs hand off **to Claude Code with a single instruction** for development.
- **Access:** Claude Pro / Max / Team / Enterprise (research preview; Enterprise admins must enable it).

### 2.2 Claude Fable 5 (run the design on this)
- `claude-fable-5`, **GA June 9 2026** — Anthropic's **most capable widely-released model**: demanding reasoning + **long-horizon agentic work**, "more capable engineering in fewer turns." **1M-token context**, **128k output**, **vision**. (Note: uses the Opus-4.7-era tokenizer — ~30% more tokens per the same text.)
- **Why it's the right pick for this design job** (from the release + prompting docs):
  - **Vision:** "interprets dense technical images, web applications, and detailed screenshots with substantially higher accuracy, often while using fewer output tokens." → feeding it the "dot." reference screenshot (and later the real app shots) is a strength, not a stretch.
  - **First-shot correctness on well-specified problems:** early testers report single-pass implementations of things that used to take days — our prompt + locked copy is exactly that kind of fully-specified brief.
  - **Strong instruction-following:** "steer most behaviors with a brief instruction rather than enumerating each one." Keep the prompt direct; don't over-spell.
  - **Caveat — it can over-build at higher effort:** it may add features/refactors/abstractions beyond the ask. That's why the §7 prompt includes a "do the simplest thing; don't invent extra pages/features" guard.
- **How to run it:** select **Fable 5** in Claude Design; use **`high` effort** as the default and **`xhigh`** for the hero / most capability-sensitive screens. Then hand the approved design to **Claude Code (also Fable 5)** to implement the React site in one instruction.
- **Owner-confirmed:** Fable 5 is selectable inside Claude Design. (The public Claude Design announcement cites Opus 4.7 as the default; model selection lets you run it on Fable 5.)
- **API-only caveats (irrelevant to the design UI):** safety classifiers can refuse cyber/bio/reasoning-extraction requests (returns `stop_reason: "refusal"`) → plan a fallback to Opus 4.8; **adaptive thinking always on**; raw chain-of-thought never returned; don't instruct it to echo its reasoning (can trigger a refusal); $10/$50 per Mtok.

### 2.3 Anthropic's frontend-design framework (shapes our prompt)
Establish **Purpose → Audience → Aesthetic Direction** before generating. **Reject "generic AI aesthetics": no generic system fonts, no predictable purple gradients, no cookie-cutter components.** Favor **unexpected font pairings, orchestrated + scroll-triggered motion, asymmetry/grid-breaking, and layered depth (gradients/textures).** Good prompts name the interface type + industry/context + key features. → All of this is encoded in the §7 prompt.

### 2.4 App Store product page guidance (Apple + ASO, 2026)
- **Screenshot sizes:** 6.9" iPhone **1320×2868**, 13" iPad **2064×2752**; Apple scales down.
- **First 1–3 screenshots show in search results** and decide installs — make them carry the value. Users spend **~7 seconds** on a product page.
- **Text overlays:** plain, honest, descriptive. **Avoid hype/"Download now"/"Best app ever."** Screenshot text is **OCR-indexed** → clarity doubles as ASO.
- **Product Page Optimization** lets you A/B icon, screenshots, preview video.

### 2.5 Landing-page patterns (devtools/AI/infra)
- **Linear / Vercel / Stripe** = the canon: **dark, type-led, real product visuals (not stock illustrations), motion that doesn't slow the page, pricing that pre-answers questions.** Linear wins on **unapologetic specificity** ("speaks directly to engineers, doesn't try to appeal to everyone"); Vercel on a **live interactive hero** (real-time deploy globe).
- **Our move:** keep the *principles* (ruthless above-the-fold positioning, real product visuals, tasteful motion, honest pricing) but **invert the aesthetic** to warm-light-editorial. In a category where every serious tool is dark, warm-and-calm is memorable *and* on-message.

### 2.6 Competitive landscape (verified prior research, re-confirmed)
- **Anthropic Remote Control** — first-party, code stays local, but **single-vendor (Claude Code only)**, **Pro/Max only and explicitly NOT Team/Enterprise**, one remote session per instance. *(The Team/Enterprise gap is our open door.)*
- **OpenAI Codex mobile** (in ChatGPT app, May 2026) — free, code stays on host, but **single-vendor (Codex only)**, **macOS-host-only** at launch.
- **Happy / cmux / CloudCLI** (OSS, ~11–22k★ combined) — mostly **manual tap-every-action**, thin clients; little/no policy-based auto-approval.
- **Omnara** (YC) — pricing collapsed $9→$20→free = **consumer WTP ≈ 0** signal.
- **Termius / Blink** — dumb terminals, no agent semantics, but prove transport-tooling WTP ($10/mo, $20/yr).
- **AI-agent governance market** is real and growing (~$0.3B→$4.8B by 2034; **EU AI Act high-risk duties land Aug 2 2026**; SOC2/ISO 42001 want "audit evidence generated automatically") — Conduit's audit log *is* that artifact. The named GRC players (AuditBoard/Optro, Holistic AI) are enterprise platforms, **not** developer-host, per-action, cross-vendor — that's our white space.

**Takeaway:** the website must say, in five seconds, the one thing no first-party tool can: **one local-first approval + policy + audit layer across *all* your agents, with your code staying on your machine.**

---

## 3. Strategy

### 3.1 Target audience
- **Bullseye (design for these):** multi-agent power users + tiny AI-native teams running Claude Code *and* Codex *and* opencode across a laptop + Mac mini/server, who background long autonomous runs and won't hand each vendor unrestricted access.
- **Expansion [later / where WTP is]:** security-conscious & regulated engineering orgs needing a human-approval audit trail as compliance evidence — the segment first-party structurally can't serve.
- **Explicitly not for:** single-vendor casual users (served free by Anthropic/OpenAI), people who want to *write code* on a phone, hobbyists with no unattended-run pain.

### 3.2 Positioning (one line)
**"The local-first approval, policy, and audit layer for AI coding agents — so they can run unattended without your code leaving your machine."**

### 3.3 Main pain
You can't babysit an agent every second — but you can't let it run blind either. Approve-everything is fatigue; approve-nothing is a `rm -rf` waiting to happen. And every vendor wants its own unrestricted access to your repo.

### 3.4 Main promise
Let your agents run while you're away. Conduit pauses them at the risky moments, asks you on your phone, auto-handles the safe stuff by your policy, and logs everything — across every vendor, with your code on your host.

### 3.5 Differentiator (the one a buyer can't get first-party)
**Cross-vendor + local-first + policy/audit, in one layer.** Anthropic RC is Claude-only & not for teams; Codex mobile is Codex-only & macOS-only. Conduit is the *governance* layer over all of them, and your source never transits a vendor's cloud.

### 3.6 Tone & visual direction
- **Tone:** calm, precise, confident, engineer-to-engineer. Short declaratives. No hype, no "revolutionary," no emoji-soup. Show the actual command and the actual decision.
- **Visual:** **calm-editorial-serious.**
  - **Background:** warm paper `#F4F2EC` (primary), pure-white cards, generous negative space.
  - **Ink:** warm near-black `#16170F`.
  - **Type:** **Instrument Serif** (display/headlines, the editorial signal) + **Inter** (body/UI) + a **monospace** (Geist Mono / Berkeley-Mono-style) for *all literal commands, paths, code, risk pills*. The serif+mono pairing is the "unexpected pairing" that reads premium-yet-technical.
  - **Accent:** a single confident **deep evergreen `#1E4D3D`** as primary (calm, serious, not the AI-purple cliché), with **semantic state colors borrowed from the app's risk bands**: approve = green `#2E9E5B`, ask = amber `#C8841A`, deny = red `#C0392B`. Use these *functionally* (the approve button is green, the deny is red) so the site teaches the product.
  - **Texture/depth:** subtle paper grain, soft layered card shadows, a faint blueprint/grid motif for "infrastructure." No glassmorphism, no neon.
- **Replace** the template's blue `#0871E7` with the evergreen accent; **drop** the Nokia retro font (we show a modern iPhone, and use the real monospace for on-screen command text).
- **Motion stack & ambition:** design to **Awwwards "Site of the Day" standard** — distinctive, premium craft — but **restrained, fast, and accessible** (a serious devtool, not an agency showreel). Use **GSAP** (ScrollTrigger for orchestrated scroll reveals/pinning, SplitText for the headline) + **Lenis** smooth-scroll for the signature motion; keep `motion/react` for component-level micro-interactions (the approval-card sequence, hovers). **Don't make Three.js/WebGL the centerpiece** — heavy 3D reads flashy and off-brand here; allow at most one subtle, optional shader/grain accent. Always honor `prefers-reduced-motion`, and keep Core Web Vitals in the Linear/Vercel range.

### 3.7 First 5-second message (above the fold must land this)
> **"Approve your agents. Keep your code."** — your AI coding agents pause and ask your phone before doing anything risky; you decide in a tap; your code never leaves your machine.

### 3.8 Objections & how the site answers them
| Objection | Where / how the site answers |
|---|---|
| "Claude/OpenAI already let me do this from my phone." | A comparison strip: *single-vendor & not for teams* vs **all your agents, your policy, your host.** State it plainly above the fold. |
| "Is my source code safe? You're a relay." | **Trust page**, prominent: source + credentials never leave the host; the relay carries only the action metadata you send; **E2EE of that relay [PLANNED]**; conduitd is **open-sourcing [PLANNED]**. Be precise, not absolute. |
| "Setup sounds painful." | **Getting-started**: real one-liner install + pair + point your agent's hook. Show the actual commands. "Working in ~5 minutes." |
| "Will it nag me constantly?" | **Policy** section: presets (Cautious/Balanced/Bypass) + per-repo rules → "most actions never reach you." |
| "Another dashboard to babysit." | Reframe: *you don't open it — it opens you.* It buzzes a few times a day, you tap, done. |
| "Does it actually work / is it real?" | Real screenshots, real commands, honest beta status (TestFlight now, App Store [PLANNED]). No fake logos/stats. |

### 3.9 Above the fold (priority order)
1. Wordmark + minimal nav (Product · Trust · Pricing · Docs · **Get the app**).
2. H1 "Approve your agents. Keep your code." + one-sentence subhead.
3. Primary CTA **Join the TestFlight beta**, secondary **See how it works** (anchor) / **Docs**.
4. The **live iPhone approval-card** moment (the product in one glance).
5. A one-line vendor row: *Works with Claude Code · Codex · opencode.*

### 3.10 What to avoid
- ❌ The old "SSH terminal" framing or "mobile terminal" language. Terminal is a *depth* feature, never the headline.
- ❌ Marketing the hosted cloud-execution / "we run your agents" path (off-strategy; contradicts "your host").
- ❌ Generic-AI look: purple gradients, system fonts, glassy cards, robot/sparkle iconography.
- ❌ Fake social proof, invented metrics, "SOC2 certified" (we're not), logo walls of customers we don't have.
- ❌ "Download on the App Store" buttons until it's actually live — **TestFlight/waitlist** for now.
- ❌ Dark-by-default. The whole point is to look unlike every other devtool site.

---

## 4. Website copy (all 6 pages)

> Voice: plain, specific, confident. CTAs are honest about beta status. **[PLANNED]** = not shipped; never imply otherwise on the live site.

### 4.1 Landing (`/`)
**Eyebrow:** Governed approvals for AI coding agents
**H1:** Approve your agents. Keep your code.
**Subhead:** Conduit puts everything risky your AI coding agents try — across Claude Code, Codex, and opencode — into one inbox on your phone. Approve, deny, or edit in a tap. Set a policy and most actions never reach you. Your code never leaves your machine.
**Primary CTA:** Join the TestFlight beta · **Secondary:** See how it works
**Vendor row:** Works with Claude Code · Codex · opencode

**Section — The problem**
*Headline:* You can't watch an agent every second. You can't let it run blind either.
*Body:* Approve every action and it's death by a thousand taps. Approve nothing and you're one `rm -rf` from a bad afternoon. And every vendor wants its own unrestricted access to your repo. There's no layer that sits above all of them and answers one question: *can this safely proceed while I'm away?*

**Section — The approval card (the product in one screen)**
*Headline:* The whole product is one card.
*Body:* When an agent wants to do something risky, it pauses. You get a push with the exact command, the files it touches, a risk read, and which rule matched. Approve, deny, edit-then-run, or "always allow this in this repo." It resumes in a second — even if the app was closed.
*Caption under the device:* A real approval, mid-decision. [SCREENSHOT — owner to supply]

**Section — Policy (so it doesn't nag you)**
*Headline:* Most actions should never reach your phone.
*Body:* Start from a preset — Cautious, Balanced, or Bypass — then tighten per repo. Reads, tests, and edits inside the working tree auto-allow. Lockfiles, `git push`, anything touching `.env` or `~/.ssh`, network installs — those ask. `rm -rf /` and credential reads — those never run. You're in control precisely because you're not asked about everything.

**Section — Activity (proof of what happened)**
*Headline:* See everything that ran while you were away.
*Body:* Every autonomous decision and every tap lands in an append-only, secret-redacted log: what the agent did, which rule allowed it, what you approved. The trust surface — and your compliance evidence if you ever need it.

**Section — Cross-vendor**
*Headline:* One layer over every agent you run.
*Body:* Claude Code, Codex, and opencode each have their own permission system. Conduit is the single policy, approval, and audit layer across all three — so you set the rules once, not three times.

**Section — Local-first / trust**
*Headline:* Your code stays on your machine.
*Body:* A small bridge — `conduitd` — runs on your host and enforces the policy *you* set. Conduit never gets your source or your credentials; the approval relay carries only the action metadata you choose to send. You own the bridge. *(End-to-end encryption of the relay and an open-source bridge are [PLANNED] — see Trust.)*

**Section — Fleet (keep minimal)**
*Headline:* A glance across every machine.
*Body:* Idle, waiting on you, or blocked — see your whole fleet and what it's costing, in one place.

**Final CTA**
*Headline:* Let your agents run. We'll get you when it matters.
*Body:* Join the TestFlight beta — no account required.
*Button:* Get Conduit

**FAQ**
- *Does my code go through your servers?* No. Source and credentials stay on your host. The relay only carries the approval metadata you send. E2EE of the relay is [PLANNED].
- *How is this different from Claude's or OpenAI's mobile app?* Those are single-vendor (Claude-only / Codex-only) and Anthropic's isn't available to Team/Enterprise. Conduit governs *all* your agents, with your code on your host.
- *Will it constantly interrupt me?* No — policy auto-handles the safe majority. You tune how cautious it is.
- *Which agents are supported?* Claude Code, Codex, and opencode today.
- *Is it available?* TestFlight beta now; App Store [PLANNED].
- *What does it cost?* Free to use; a one-time Conduit Pro unlock is $14.99. Team/self-host [PLANNED].

---

### 4.2 Product (`/product`)
**H1:** How Conduit works
**Subhead:** Four pieces: your agents, the bridge, the approvals, the policy. Once they're set up, you mostly forget Conduit exists — until it matters.

**Block — Agents:** Your coding agents (Claude Code, Codex, opencode) run where they always have: on your laptop, your Mac mini, your server. Conduit doesn't run them and doesn't move them.

**Block — The bridge (`conduitd`):** A small daemon on your host. It owns the policy, the audit log, and the approval queue, and it survives disconnects — so an agent can keep working (and keep being governed) whether your phone is attached or not.

**Block — Approvals:** When a tool call is risky, the bridge pauses it, computes blast radius (files, git, network), and surfaces a card to your phone. Allow · Deny · Edit-then-run · Always-allow. Decisions relay back and the agent continues — even if the app was backgrounded.

**Block — Policy:** Ranked rules — deny beats ask beats allow, default ask. Global plus per-repo. Presets to start, then tighten. This is the dial between "babysitting" and "blind trust."

**Block — Go deep when you need to:** A full Warp-style block terminal, diff review, and file browser live one tap down — for when you *do* want to drive directly. It's depth, not the headline.

**CTA:** Read the getting-started guide · Join the beta

---

### 4.3 Security / Trust (`/trust`)
**H1:** Your code stays on your host. Here's exactly what we can and can't see.
**Subhead:** We'd rather be precise than make an absolute claim we can't stand behind.

**What never leaves your machine:** Your source code. Your SSH keys and AI API credentials (in the iOS Keychain / on your host). Your agent output.

**What the relay carries:** Only the approval metadata you send for a decision — the command, the file paths it touches, a risk read. This is how the card reaches your phone when the app is closed.

**On the wire today vs. tomorrow:**
- Today: the relay transmits that approval metadata to deliver pushes and relay your decision.
- **[PLANNED] End-to-end encryption:** the bridge will encrypt each approval payload to your device's public key, so the relay only ever sees an opaque blob plus routing metadata.
- **[PLANNED] Open-source `conduitd`:** the bridge is being opened so you can read exactly what runs on your host.

**Enforcement you can trust:** Conduit's hook returns a hard *deny* that holds **even under `--dangerously-skip-permissions`** — a policy your agent can't talk its way around. Default is fail-closed: if the bridge isn't reachable, mutating actions hold rather than auto-run.

**Audit:** Every decision — auto and human — is written to an append-only, secret-redacted log on your host. Export it as evidence if you need it.

**What we don't claim:** We are not SOC2/ISO certified and we don't say we are. We don't have your code, so we can't lose it.

**CTA:** Read the docs · See the policy model

---

### 4.4 Pricing (`/pricing`)
**H1:** Free to run. Pay once if you want the full app.
**Subhead:** No subscription to use it. No account required to start.

| | **Free** | **Conduit Pro** | **Team & Self-host** |
|---|---|---|---|
| Price | $0 | **$14.99 once** | **[PLANNED] — talk to us** |
| Approvals across your hosts | ✓ | ✓ | ✓ |
| Policy + audit log | ✓ | ✓ | ✓ |
| Cross-vendor (Claude Code, Codex, opencode) | ✓ | ✓ | ✓ |
| Full app unlock (fleet depth, advanced surfaces) | — | ✓ | ✓ |
| Shared team policies, signed audit export, on-prem relay | — | — | **[PLANNED]** |

*Footnote:* Conduit Pro is a one-time StoreKit purchase, not a subscription. Team/self-host pricing isn't set yet — [PLANNED]; tell us what you need and we'll talk.
**CTA:** Join the TestFlight beta

> ⚠️ **Owner note (not site copy):** confirm exactly what the $14.99 IAP gates before publishing the feature rows — the repo gates "paid surfaces" behind `showPaidSurfaces`, but don't list a specific Pro-only feature on the live site unless it's actually gated. Keep rows honest.

---

### 4.5 Docs / Getting started (`/docs`)
**H1:** Working in about five minutes
**Subhead:** Install the bridge, pair your phone, point your agent at it. Three steps.

**1 — Install the bridge on your host**
```bash
cd daemon/conduitd && go build -o conduitd .
./conduitd install        # writes the binary + a launchd/systemd unit
```
The bridge runs in the background and survives reboots.

**2 — Point your agent's hook at it**
| Agent | Hook |
|---|---|
| Claude Code | `cp docs/conduit-hook.sh ~/.claude/hooks/conduit-hook.sh && chmod 700 ~/.claude/hooks/conduit-hook.sh` |
| Codex | `cp docs/codex-conduit-hook.sh ~/.config/codex/hooks/conduit-hook.sh` |
| opencode | `cp docs/opencode-conduit-hook.sh ~/.config/opencode/hooks/conduit-hook.sh` |

**3 — Set a policy (optional — there's a sane default)**
Drop a `~/.conduit/policy.yaml` (global) or `<repo>/.conduit/policy.yaml` (per-repo). Default is *ask* on anything mutating; reads auto-allow.

**4 — Pair your phone & go**
Install the app, scan the pairing code, choose a caution preset. Next time an agent hits something risky, your phone buzzes.

**CTA:** Join the beta · Read the policy reference

> ⚠️ **Owner note:** verify these exact paths/commands against the shipping CLI before publishing (they're from current repo docs but the install UX may change).

---

### 4.6 Download / App Store (`/download`)
**H1:** Get Conduit
**Subhead:** TestFlight beta now. No account required.
**Body:** Conduit is in active beta. Join TestFlight to run it against your own hosts and agents; the App Store release is [PLANNED]. Requires a recent iPhone and a host (macOS or Linux) you can install the bridge on.
**Primary CTA:** Join the TestFlight beta
**Secondary:** Read the getting-started guide
**Reassurance line:** No Conduit account. Your code stays on your machine.

---

## 5. App Store copy

> Aligns with `docs/app-store-metadata.md`. Honest-claims rules apply; reviewer notes pre-empt the SSH-app Guideline 2.5.2 trap.

**App name options (30 char):**
1. **Conduit — Agent Approvals** *(recommended)*
2. Conduit: AI Agent Control
3. Conduit — Agent Governance

**Subtitle options (30 char):**
1. **Approve AI agents from anywhere** *(recommended)*
2. Govern your AI coding agents
3. One inbox for every agent

**Promotional text (170 char):**
> Your AI coding agents pause and ask your phone before doing anything risky. Approve in one tap — even when you're away. Safe actions auto-handle by your policy. All logged.

**Full description:**
> Conduit is the approval and governance layer for AI coding agents that run on *your own* machine. A small bridge on your host enforces the policy *you* set — auto-allowing safe actions, blocking dangerous ones, and tapping you only for the calls that genuinely need a human.
>
> When one does, you get a notification with the exact command, the files it touches, and a risk read — and you approve, deny, or edit it in seconds, even when the app is closed. Works across Claude Code, Codex, and opencode, with a full audit trail of every decision. Your code never leaves your host.
>
> • DECIDE FAST — risky approvals surface with command, blast radius, and risk band. Allow, deny, allow-always, or edit-then-run.
> • STAY CALM — Cautious / Balanced / Bypass presets and per-repo policy mean most actions never reach you.
> • SEE EVERYTHING — a while-you-were-away activity feed logs every autonomous decision; a fleet glance shows status across vendors.
> • GO DEEP — a full block-mode terminal, diff review, and file browser live one tap down.
>
> Conduit governs agents on your own remote host. It does not download or execute code on your device.

**Keywords (100 char):**
`claude code,codex,opencode,ai agent,approvals,governance,policy,audit,ssh,devops,terminal,fleet`

**Screenshot order + captions** *(owner supplying real shots — captions ready; plain, OCR-friendly, no hype):*
1. **The approval card** — "Approve, deny, or edit in one tap."
2. **A decision being made** — "Allow once, allow-always, or edit-then-run."
3. **Policy presets** — "Cautious, Balanced, Bypass — most actions never reach you."
4. **Activity feed** — "Every autonomous decision, logged."
5. **Fleet** — "Every agent, every machine, at a glance."

**App preview video idea (15–20s):** Cold open on a phone face-down on a desk. It buzzes. Hand picks it up — an approval card: `npm install` touching `package-lock.json`, risk amber. Thumb taps **Allow once**. Cut to a laptop across the room: the agent resumes. Cut to the Activity feed ticking the decision in. End card: "Approve your agents. Keep your code. — Conduit." No voiceover; mono captions only.

**Privacy / trust positioning (nutrition label):** No tracking. Declare: APNs device token (push registration) and, if Pro billing is used, subscription data. State plainly: **source code never leaves the device.** Verify against actual data flows before submission.

**App Review notes:** Conduit governs AI coding agents on the developer's own remote host; it drives a *remote* shell and does **not** download or execute code locally (pre-empts Guideline 2.5.2). The Inbox is pre-seeded in DEBUG builds so reviewers see cards without a live host. A $14.99 StoreKit non-consumable (`dev.conduit.mobile.pro`) unlocks the full app — use a sandbox account.

---

## 6. Ads & launch strategy

> Small budget, developer audience, honest beta. Lead with the *demo*, not adjectives.

### 6.1 Best launch channels (in priority order)
1. **Show HN** ("Show HN: Conduit — a local-first approval layer for Claude Code / Codex / opencode"). The single highest-leverage launch for this audience; open-sourcing `conduitd` [PLANNED] amplifies it.
2. **Reddit:** r/ClaudeAI, r/ChatGPTCoding, r/ExperiencedDevs, r/devops, r/selfhosted, r/LocalLLaMA. Post the *demo clip*, not a pitch.
3. **X / dev-twitter:** the 15s approval-card clip; reply-guy in threads about agents going rogue / `rm -rf` horror stories.
4. **Dev newsletters / communities:** TLDR, Console.dev, relevant Discords (Claude, Codex, opencode).
5. **Targeted search** (tiny budget, high intent): "claude code mobile," "approve claude code commands," "codex remote control," "ai agent guardrails."

### 6.2 Angles
- **Search:** intent capture — people already trying to control agents from a phone.
- **Community:** the *unattended-agent horror story* → "here's the guardrail." Lead with the clip.
- **Social:** the calm-confidence reframe ("let it run, I'll get pinged") + the cross-vendor one-liner first-party can't match.

### 6.3 Landing-page A/B tests
- **Hero headline:** "Approve your agents. Keep your code." vs. "Let your agents run unattended — safely."
- **Hero visual:** static iPhone screenshot vs. the live typing→approve animation.
- **Above-fold CTA:** "Join the TestFlight beta" vs. "See how it works" as primary.
- **Aesthetic:** warm-light (our bet) vs. a dark control — confirm the differentiation actually converts.

### 6.4 CTA tests
"Join the TestFlight beta" · "Get Conduit" · "Try it on your own host" · "Put a guardrail on your agents."

### 6.5 Ten ad hooks
1. Your AI agent will run `rm -rf` eventually. Be the one who taps **Deny**.
2. Claude's mobile app only controls Claude. What about the other three agents you run?
3. Let your agent work while you're at lunch. Get pinged only when it matters.
4. Approve every action = fatigue. Approve nothing = disaster. There's a third option.
5. Your code never leaves your machine. Your approvals come to your phone.
6. One policy. One audit log. Every agent.
7. The agent paused, asked, and waited for you — across the room, from your pocket.
8. Anthropic's remote control isn't for your team. This is.
9. Set the rules once, not three times — Claude Code, Codex, opencode.
10. The guardrail for agents that run on *your* machine.

### 6.6 Ten short ads (1–2 lines)
1. **Approve your agents. Keep your code.** Conduit pings your phone the moment an agent needs a human. TestFlight now.
2. Your agents can run while you're away. Conduit pauses them at the risky bits and asks you — in one tap.
3. `rm -rf node_modules`? Allowed. `rm -rf /`? Never. Set the policy, sleep fine.
4. Claude Code, Codex, opencode — one approval inbox for all of them.
5. Death by a thousand approvals? Set a policy and most actions never reach you.
6. The agent stopped, showed you the command and the blast radius, and waited. You tapped Allow.
7. Code stays on your host. Decisions come to your phone. That's the whole deal.
8. Every autonomous action your agents take — logged, on your machine.
9. First-party mobile control is single-vendor. Conduit governs all your agents.
10. Put a guardrail on your AI agents in about five minutes.

### 6.7 Five longer ads (paragraph)
1. *"You wouldn't give a new contractor root and walk away. Why do it with an AI agent? Conduit sits between your agents — Claude Code, Codex, opencode — and your machine. Safe actions auto-run by your policy; risky ones pause and ping your phone with the exact command and what it touches. Approve, deny, or edit in a tap. Your code never leaves your host. TestFlight now."*
2. *"The pitch for agents was 'let them work while you don't.' The reality is you hover over the terminal hitting 'approve' all day. Conduit fixes that: set a caution level, let reads and tests fly, and only get pinged for the calls that actually need you — lockfiles, pushes, anything near your secrets. Run agents like you mean it."*
3. *"Anthropic and OpenAI shipped mobile control — for their own agent. If you run more than one, you've got more than one app and zero shared policy. Conduit is the layer above all of them: one inbox, one rulebook, one audit log, across every agent on every machine you own."*
4. *"Compliance teams are about to start asking who approved what your agents did. Conduit answers it by default — an append-only, redacted log of every autonomous decision and every human tap, on your own host, exportable as evidence. Governance that happens to also make your day calmer."*
5. *"Your source is the one thing you can't get back. Conduit never has it — agents run on your host, your keys stay in your Keychain, and only the approval metadata you send ever leaves, to reach your phone. End-to-end encryption of even that is on the way. You own the bridge."* *(Note: E2EE is [PLANNED] — keep the future-tense phrasing.)*

### 6.8 Metrics to track
- **Top funnel:** landing → "Join beta" click-through; hero-variant conversion; clip completion rate.
- **Activation:** TestFlight installs → bridge installed → phone paired → **first real approval** (the true activation event).
- **Retention/value:** approvals/week, % auto-handled by policy (target the 90%+ "calm" zone), D7/D30 return.
- **Channel:** CPA and install→activation by source (HN vs Reddit vs search).
- **Qualitative:** "would you be disappointed if this went away" + which vendor mix they run.

### 6.9 Small-budget testing plan
- **Week 0 (free):** Show HN + 3 Reddit posts + the clip on X. Instrument everything. This validates message before you spend a dollar.
- **Weeks 1–2 (~$300–500):** tiny search campaign on the four high-intent terms above → the winning hero variant. Kill anything over target CPA fast.
- **Decision gate:** scale only the channel where install→**first-approval** activation clears your bar. If warm-light loses to dark in the A/B, switch — let data, not taste, settle the aesthetic bet.

---

## 7. Final Claude Design prompt

*(Also saved standalone in `docs/marketing/prompt-for-claude-design.md`.)*

```
You are designing the marketing website for Conduit — conduit.dev.

PURPOSE
Design a 6-page marketing site that makes Conduit feel like a serious, trustworthy developer tool — not a generic AI app. The hero must communicate the product in five seconds and show the real app on a modern iPhone.

AMBITION / QUALITY BAR
Design this to Awwwards "Site of the Day" standard — the level of craft featured on awwwards.com: confident typography, orchestrated motion, impeccable spacing, memorable detail. But it must stay a serious, fast, accessible developer tool: restraint over spectacle. Never trade clarity, load speed, or the five-second message for decoration. "Award-grade" here means the most polished possible version of calm-editorial — not a maximalist agency showreel.

WHAT THE PRODUCT IS
Conduit is a phone-first approval, policy, and audit layer for AI coding agents (Claude Code, OpenAI Codex, opencode) that run on the developer's OWN machine. A small bridge (conduitd) on the host enforces the user's policy: safe actions auto-run, dangerous ones are blocked, and ambiguous ones pause and ping the phone with the exact command, the files it touches, and a risk read. The user approves, denies, edits-then-runs, or sets an allow-always rule — in one tap, even when the app is closed. Every decision is logged. The user's source code never leaves their host.

WHO IT IS FOR
Developers and small teams running MULTIPLE agents across their OWN machines, who won't give each vendor unrestricted repo access. NOT casual single-vendor users (first-party tools serve those for free). Speak engineer-to-engineer: precise, calm, specific. No hype.

AESTHETIC DIRECTION (follow exactly — reject generic AI aesthetics)
Calm-editorial, but serious devtool. This is a deliberate counter-position: every competitor site (Linear, Vercel, Warp) is dark and code-dense, so we go warm and light to stand out and to match the product's promise of control-without-anxiety.
- Background: warm paper #F4F2EC; pure-white cards; generous whitespace.
- Ink: warm near-black #16170F.
- Type: Instrument Serif for display/headlines; Inter for body/UI; a true monospace (Geist Mono) for ALL literal commands, file paths, code, and risk pills. The serif + mono pairing is intentional and premium — do not substitute system fonts.
- Accent: one confident deep evergreen #1E4D3D as primary. Semantic state colors, used functionally: approve/green #2E9E5B, ask/amber #C8841A, deny/red #C0392B (the Approve button is green, the Deny button is red — the site should teach the product's color language).
- Depth: subtle paper grain, soft layered card shadows, a faint blueprint/grid motif for "infrastructure." NO glassmorphism, NO neon, NO purple gradients, NO robot/sparkle icons, NO dark-by-default.

PAGES TO DESIGN (6)
1. Landing (/) — the priority. Above the fold: wordmark + nav (Product, Trust, Pricing, Docs, Get the app); H1 "Approve your agents. Keep your code."; one-sentence subhead; primary CTA "Join the TestFlight beta" + secondary "See how it works"; the live iPhone approval-card hero; a vendor row "Works with Claude Code · Codex · opencode." Then sections: the problem; the approval card; policy; activity/audit; cross-vendor; local-first/trust; minimal fleet; final CTA; FAQ.
2. Product (/product) — the four concepts: Agents, the Bridge (conduitd), Approvals, Policy; plus "go deep" (terminal/diff/files as depth).
3. Trust/Security (/trust) — precise privacy story: source + credentials never leave the host; relay carries only chosen approval metadata; E2EE of the relay and open-source bridge are PLANNED (label clearly); fail-closed default; deny holds even under --dangerously-skip-permissions; audit log. No certification claims.
4. Pricing (/pricing) — Free / Conduit Pro $14.99 one-time / Team & Self-host PLANNED. Honest, no contact-sales wall.
5. Docs / Getting started (/docs) — three steps: install the bridge, point the agent's hook, pair the phone. Show real commands in monospace. "Working in ~5 minutes."
6. Download (/download) — TestFlight beta now; App Store PLANNED; "No account. Your code stays on your machine."

COPY
Use the copy in docs/marketing/website-design-brief.md §4 (landing, product, trust, pricing, docs, download) and §5 (App Store) verbatim where possible. Headline lane is locked: "Approve your agents. Keep your code." Everything marked [PLANNED] must read as future tense — never imply it ships today.

HERO — THE LIVE MOMENT (replaces an old Nokia-phone-on-a-beach mockup)
A modern iPhone (clean device frame) showing the Conduit inbox approval card. A scripted micro-animation, looping:
1) a command types into the card in monospace (e.g. `rm -rf node_modules/`),
2) a risk pill appears (amber "ask"), blast-radius lines populate (files touched),
3) a tap lands on Allow → the card resolves to a green "✓ Approved" state → the next card slides up.
The on-screen app screenshot is a PLACEHOLDER labeled "[SCREENSHOT — owner-supplied]" (the owner is providing the real captures). The animated approval-card overlay itself should be a real, designed component so the live moment works before the screenshot is dropped in.

INTERACTIONS / ANIMATION
Orchestrated, scroll-triggered reveals (fade + slight rise) per section; the looping hero approval-card animation; a typed-command effect in monospace; subtle hover states on buttons (the evergreen primary, with a soft top glint). Tasteful and fast — motion must never slow the page, and must honor prefers-reduced-motion.
Animation stack: use GSAP for the signature page motion — ScrollTrigger for orchestrated scroll reveals and any pinned sections, SplitText for the editorial headline — with a Lenis smooth-scroll layer for the buttery feel. motion/react is fine for React component micro-interactions (the approval-card sequence, hovers). Do NOT make Three.js / WebGL the centerpiece — heavy 3D reads flashy and off-brand for a calm, serious tool; at most one subtle, optional WebGL/shader accent (e.g., animated paper grain), never required.

DESKTOP / MOBILE
Desktop: centered max-width ~1024–1152px content column, asymmetric hero (text left / device right or device-centered with text above), generous margins. Mobile: single column, device hero stacks under the headline, sticky compact nav, thumb-reachable CTAs. The site must look native on a 390×844 iPhone.

ASSETS TO USE / PRODUCE
- Produce a wordmark: lowercase "conduit" in Instrument Serif (a small monospace lockup variant for footers/technical contexts).
- Produce /og.png (1200×630) and /icon.png (512×512) — they're referenced but missing.
- Use PLACEHOLDER device screenshots throughout (owner supplies finals). Reference shots exist at docs/screenshots/governed-approvals/ for layout only — do not treat as final.

WHAT TO REPLACE / AVOID
- REPLACE the old phone mockup with the modern iPhone live approval card.
- REPLACE all "SSH terminal / run agents over SSH" copy — that positioning is retired. Terminal is a depth feature, never the headline.
- AVOID: hosted-cloud / "we run your agents" messaging; generic-AI visuals (purple gradients, system fonts, glassy cards, sparkle/robot icons); fake logos, stats, testimonials, or certifications; "Download on the App Store" buttons (use TestFlight); dark-by-default theme.

IMPLEMENTATION CONSTRAINTS (from the codebase)
- Deliverable is design-first; if implemented, target the existing site: Next.js 16 App Router + React 19 + Tailwind v4, with GSAP (ScrollTrigger, SplitText) + Lenis for signature motion and motion/react for component micro-interactions. The repo warns (marketing/AGENTS.md) that Next.js 16 has breaking changes — its docs must be read before coding.
- A "dot." Vite template (single App.tsx, Instrument Serif + Inter, motion/react, a video-background hero with a typing overlay) is the reference for motion + editorial feel ONLY — adapt its structure, not its content; replace its blue (#0871E7) with the evergreen accent and its retro Nokia font with Geist Mono.
- Keep site and app visually coherent; you may read the codebase/design tokens to align colors, type, and components.
- Run this design session on Claude Fable 5 (claude-fable-5): select it as the model. Its stronger vision (dense screenshots/web UIs) and first-shot accuracy fit a fully-specified page; use high effort, or xhigh for the hero. Then hand the design to Claude Code (also Fable 5) to implement the React site in one instruction.

SCOPE / DISCIPLINE
Design exactly the 6 pages and the sections specified — do not invent extra pages, modals, or features, and don't add abstractions beyond what's asked. Do the simplest thing that looks excellent. If a choice is ambiguous, pick the option that best serves the five-second message and move on.
```

---

## 8. Open items & reminders (owner)

- 🔔 **REMINDER (you asked me to flag this): you are supplying the real iPhone app screenshots yourself.** The design + App Store copy use placeholders marked `[SCREENSHOT — owner-supplied]`. Capture the 6.9" set at **1320×2868** for: approval card · a decision · policy presets · activity feed · fleet. Until you drop them in, the hero relies on the designed approval-card overlay component.
- ⚠️ **Replace stale site copy:** the current `marketing/` landing still sells "SSH Agent Terminal." Do not ship it as-is.
- ⚠️ **Honest-claims checklist before publish:** E2EE relay = [PLANNED]; open-source `conduitd` = [PLANNED]; Team/self-host pricing = [PLANNED]; App Store = [PLANNED] (TestFlight now); no SOC2/ISO claims; confirm what the $14.99 IAP actually gates before listing Pro-only feature rows.
- ✅ **Model:** run Claude Design on **Fable 5** (owner-confirmed selectable). Use high/xhigh effort, feed it a reference screenshot (vision is a Fable 5 strength), keep instructions concise, and lean on the prompt's "don't over-build" guard. See §2.2.
- ✅ **Decisions locked this session:** aesthetic = calm-editorial-serious; deliverable = design-only (framework later); scope = all 6 pages; claims = documented model + honest; **sequence = website design first, then port the design language into the iOS app (§9)**.

---

## 9. Plan: website first, then port to the app

Agreed sequencing (this session): **design the website first, then take its design language into the iOS app.** Rationale — the marketing site is the cheapest place to settle the brand (palette, type, motion, the approval-card visual language); the app's DesignSystem then inherits a proven look instead of guessing.

- **Phase 1 — Website (now):** run the §7 prompt in Claude Design on Fable 5. Iterate the hero approval-card animation and the warm-editorial system until it's right. Output: designed pages + a settled token set (§3.6).
- **Phase 2 — Extract the design language:** from the approved site, lock the canonical tokens — warm paper, ink, evergreen primary, the approve/ask/deny semantic set, Instrument Serif + Inter + Geist Mono, card/shadow/grid motifs, and the approval-card motion spec.
- **Phase 3 — Port into the iOS app (separate, code-touching task — flagged, not started):** map those tokens onto the app's existing DesignSystem (`Packages/ConduitKit/Sources/DesignSystem/Tokens.swift` + `Components/`). The app is currently dark with glass chrome — decide whether it adopts the warm-light language wholesale or keeps a dark variant using the *same* type/accent/semantic system.
  - **Reuse:** the approval-card component (the site's hero *is* the app's core screen), the approve/ask/deny color language, the serif+mono pairing for command text, the risk-pill treatment.
  - **Don't:** port the web layout 1:1 — re-flow natively (the app IA is already Inbox/Fleet/Activity/Settings). Respect the architecture invariants in `docs/agent-contract.md` (glass chrome via `conduitGlassChrome`, design tokens single-sourced).

---

## Sources
- Claude Design — [Anthropic Labs announcement](https://www.anthropic.com/news/claude-design-anthropic-labs) · [Frontend Design plugin](https://claude.com/plugins/frontend-design)
- Claude Fable 5 — [Anthropic docs](https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5) · [announcement](https://www.anthropic.com/news/claude-fable-5-mythos-5)
- Claude Code hooks (deny holds under skip-permissions) — [hooks reference](https://code.claude.com/docs/en/hooks)
- Competitors — [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control) · [OpenAI Codex remote connections](https://developers.openai.com/codex/remote-connections) · [opencode permissions](https://opencode.ai/docs/permissions/)
- App Store — [Product Page Optimization](https://developer.apple.com/app-store/product-page-optimization/) · [screenshot specs](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- Landing patterns — [SaaS/devtool design 2026](https://www.gridrebels.studio/post/20-best-saas-website-designs-in-2026-examples-that-actually-convert)
- AI-agent governance market — [2026 governance guide](https://www.digitalapplied.com/blog/ai-agent-governance-policy-compliance-2026)
