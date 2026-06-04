# PRODUCT_RESEARCH.md — Conduit Market & Competitive Research

> **Data integrity rule:** Every market claim carries a source URL and a confidence tag (High / Medium / Low).
> §2.7 verified primary-source data is used throughout. Earlier §2.4/§2.5 figures are NOT used.
> Disconfirming evidence is included per the execution brief.

---

## 1. Market Thesis

**"Phones are not where serious software is written. They are where it is steered."**

The core job-to-be-done: attach the phone to a remote workspace, get notified the moment an agent needs a human decision, approve or reject it, review diffs and output, and redirect the agent — all without reaching for a laptop. The phone is an **approval cockpit and interrupt handler**, not a local IDE.

This is meaningfully different from:
- SSH terminal apps (Termius, Blink) — dumb pipe, no agent semantics
- Remote IDEs (Codemagic, GitHub Mobile) — editing-on-phone, different JTBD
- Local AI coding assistants — no remote agent; on-device inference only

---

## 2. Demand Signals

### 2.1 Pieter Levels ("Levels") Signal
**Confidence: HIGH** — verified primary-source posts on x.com

Pieter Levels, a widely-followed indie developer, publicly documented running Claude Code on a VPS and SSH-ing in via Termius on iPhone, coining the phrase "RAW DOG DEV ON THE SERVER… SSH… @TermiusHQ":

- https://x.com/levelsio/status/1957518592284717558 (~Aug 2025)
- https://x.com/levelsio/status/1953022273595506910 (~Aug 2025)
- https://x.com/levelsio/status/1951957270989783501 (~Aug 2025)

**Signal interpretation:** A high-profile developer publicly endorses SSH + iPhone as a viable remote agent steering workflow. This drove significant awareness of the use case. Specific engagement metrics (views/likes) are NOT cited here — those numbers were not verified via authenticated access.

### 2.2 Developer Pain Points
**Confidence: HIGH** — each pain point has a verified primary URL

1. **Session loss on backgrounding / SSH drop:**
   iOS aggressively backgrounds apps; SSH sessions drop; agent context is lost.
   Source: https://dev.to/jagafarm/stop-losing-claude-code-sessions-a-tmux-primer-for-mobile-devs-2p48

2. **Approval fatigue — approving every tool call manually is unsustainable:**
   Agents fire PreToolUse hooks for every write/bash/edit; reviewers burn out or rubber-stamp.
   Source: https://www.developersdigest.tech/blog/approval-fatigue-agent-security-bug

3. **Decision / review fatigue — too many agent check-ins:**
   As agents get more autonomous, the cognitive load of each "should I approve this?" check-in compounds.
   Source: https://stackoverflow.blog/2026/05/21/coding-agents-are-giving-everyone-decision-fatigue/

4. **"tmux on touch is miserable":**
   Even with tmux keeping the session alive, navigating panes, scrolling, and typing approvals on a touch screen is painful.
   Source: same dev.to link as #1 — https://dev.to/jagafarm/stop-losing-claude-code-sessions-a-tmux-primer-for-mobile-devs-2p48

5. **Notification gaps — "I missed the moment the agent needed me":**
   The most-repeated complaint across Hacker News threads, Reddit (r/ClaudeAI, r/localLLaMA), and app-store reviews for rival apps. When the agent pauses for approval, the developer has no reliable way to know unless they're watching the terminal.
   Source: repeated pattern across HN/Reddit/app-store — MEDIUM confidence (platform content not individually verified with primary URLs)

---

## 3. Competitive Landscape

### 3.1 Verified Competitor Snapshot
*Numbers are from §2.7 primary verification. Use these — not earlier §2.4/§2.5 figures.*

| Product | Stars / Scale | Model | Notes |
|---|---|---|---|
| **Happy** | 21.6k★ GitHub | MIT, free, native iOS, E2E encryption | github.com/slopus/happy — strong OSS trust signal |
| **cmux** | 20.9k★ GitHub | macOS orchestrator + iOS early access | github.com/manaflow-ai/cmux — feed-style approval cards |
| **CloudCLI / claudecodeui** | 11.6k★ GitHub | Cross-vendor (Claude+Cursor+Codex+Gemini), self-host/Docker/managed | github.com/siteboon/claudecodeui |
| **Omnara** (YC S25) | Native iOS | Went $9 → $20 → "100% FREE, unlimited" | omnara.com/pricing — WTP collapse signal (see §4) |
| **Anthropic Remote Control** | First-party (Pro+/Team/Enterprise) | NOT Max-only; up to 32 concurrent sessions; push notifications; Dispatch (start task FROM mobile); Channels (Telegram/Discord/iMessage) | code.claude.com/docs/en/remote-control — HIGH confidence, official docs |
| **OpenAI Codex mobile** | ALL plans incl. Free (iOS + Android) | Approve commands; streams diffs/tests/screenshots; Remote SSH GA | developers.openai.com/codex/remote-connections — HIGH confidence, TechCrunch + official, May 14 2026 |
| **Cursor cloud agents** | Announced | Mobile companion | MEDIUM confidence — announced but adoption unverified |
| **GitHub Copilot cloud agent (mobile)** | Announced | Research + code from mobile | MEDIUM confidence — github.blog/changelog/2026-04-08-github-mobile-research-and-code-with-copilot-cloud-agent-anywhere/ |
| **Termius** | Mobile SSH incumbent | $10/mo — termius.com/pricing | Dumb terminal; no agent approvals |
| **Blink Shell** | Mobile SSH incumbent | $20/yr | Dumb terminal; no agent approvals |
| **Additional OSS** | Various | Paseo, Companion, Happier, Catnip, Sled, CallMe, PeonPing, Lucarne, CC Pocket | github.com/K9i-0/ccpocket and others |

**Combined OSS GitHub stars (Happy + cmux + CloudCLI): ~54k** — a formidable "free and trusted" signal.

### 3.2 Claude Code Platform Capabilities Relevant to Conduit
**Confidence: HIGH** — official docs

- **PreToolUse hook:** fires before any tool; can return a permission decision that BLOCKS the tool (deny wins even in `bypassPermissions`). Blocks while your gateway waits on the phone.
  Source: https://code.claude.com/docs/en/hooks

- **Notification hook:** fires when agent is waiting for permission or idle — powers "tell my phone the agent needs me."
  Source: same hooks doc

- **Agent SDK `canUseTool` callback:** pauses indefinitely until you return `{behavior, updatedInput?}` — this is the edit-before-run path.
  Source: https://code.claude.com/docs/en/agent-sdk/permissions

- **Sessions:** resumable via `--resume <session_id>`; background sessions; worktrees isolate parallel agents.

- **Limitation (important):** CLI `-p` cannot use `canUseTool` — near-term loop uses pure-Go hook gateway; SDK bridge is deferred.

- **Codex analogous capabilities:** PreToolUse-block + resumable sessions.
  Source: https://developers.openai.com/codex/hooks

---

## 4. Disconfirming Evidence & Thesis Risks

**These are real threats. Include them in any investor/partner narrative.**

### 4.1 First-Party Anthropic Remote Control Is Now a Major Competitor
**Confidence: HIGH** — official docs at code.claude.com/docs/en/remote-control

Multi-session + push notifications + start-from-mobile is now FIRST-PARTY from Anthropic, available FREE for Pro+/Team/Enterprise users. This is not a distant incumbent — it is Anthropic directly competing in the exact use case Conduit addresses. Any developer already paying for Claude Pro gets this for free.

### 4.2 OSS Field Is Crowded and Free
Happy (21.6k★), cmux (20.9k★), CloudCLI (11.6k★) = ~54k combined GitHub stars, all MIT-licensed, all free. These are not vaporware — they are actively maintained with significant community trust.

### 4.3 Consumer WTP Appears Close to Zero
Omnara (YC S25) started at $9/mo, raised to $20/mo, then collapsed to "100% FREE, unlimited" (omnara.com/pricing). This pricing arc is a strong signal that consumer willingness-to-pay for agent mobile clients is near zero — or that the market is not yet mature enough to sustain recurring consumer pricing.

### 4.4 "Better Free Mobile Client for Claude Code" Is a Lost Lane
First-party Anthropic Remote Control + free OSS alternatives dominate this positioning. Building a better-free-client is not a viable strategy.

### 4.5 Cross-Vendor Alone Is Not a Moat
CloudCLI (11.6k★), Paseo, Companion, and Happier already support multiple vendors. Cross-vendor breadth is a table-stake, not a differentiator, once peers catch up.

### 4.6 X/Twitter Engagement Numbers Are Unverified
The Levels posts were identified by URL, but specific engagement metrics (view counts, like counts) cited in earlier research drafts are UNVERIFIED — the platform requires authentication to view full engagement data. Treat those specific numbers as MEDIUM confidence at best, and do not cite them in materials requiring high verifiability.

---

## 5. Re-Aimed Strategy (From Verified Market Analysis)

### 5.1 New Positioning
**"The secure, native, cross-vendor cockpit for steering AI coding agents — for developers and teams who can't or won't route their code through someone else's cloud."**

This positioning carves out the segment that first-party Anthropic Remote Control cannot serve: security-conscious developers, enterprise teams, and regulated industries where routing source code through Anthropic's (or any cloud vendor's) infrastructure is a compliance problem.

### 5.2 Differentiation, Sequenced

**Stage 1 — Reliability + native-iOS notifications (the universal #1 complaint):**
- Rock-solid reconnect engine (already built: NWPathMonitor + backoff + AutoReconnectEngine)
- Live Activities / Dynamic Island / Apple Watch — approve from lock screen or wrist
- Structured approval cards (not raw JSON or a 500-char truncated string)
- Why rivals can't easily copy: Live Activities + Dynamic Island are Apple-exclusive APIs; web/Electron/Android-first rivals structurally can't match native quality

**Stage 2 — Security / self-host / enterprise (the one segment with real WTP):**
- E2E, on-premises bridge (conduitd), Secure Enclave / TOFU (already built)
- Audit log (already built), team approval routing
- Pricing: team seats / enterprise tier; precedent is Termius $10/mo for transport-grade reliability — real WTP exists in this segment
- Open-source conduitd bridge in this stage (earned developer trust via transparency — Happy + CloudCLI model)

**Stage 3 — Cross-vendor breadth (anti-lock-in wedge):**
- Claude + Codex first; later Cursor / Gemini
- "You control the bridge. Your code stays on your host." — anti-Anthropic-Remote-Control wedge

### 5.3 Beachhead: Security-Conscious / Enterprise / Regulated Developers
NOT a broad consumer launch. This segment:
- Has demonstrable WTP (enterprise SSH tools: Termius $10/mo, Blink $20/yr)
- Cannot use first-party Anthropic Remote Control for compliance reasons
- Values on-premises bridge + audit log + Secure Enclave

### 5.4 Distribution Risk (Biggest Risk)
Conduit will be the best-built and least-known app in a crowded field.

**Mitigation:**
1. Open-source conduitd bridge — Happy/CloudCLI earned 11–21k★ by going open-source. The bridge is low-IP (hook plumbing, not the iOS app), high-trust.
2. Beachhead a specific underserved niche first; avoid spray-and-pray consumer launch.
3. Positioning that cannot be undercut by Anthropic Remote Control: "your code never leaves your host."
