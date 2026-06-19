# Conduit Competitor & Market Research — Compiled

**Compiled:** 2026-06-17
**Sources:** Claude Code sessions (June 14–15, 2026), OpenCode sessions, Kimi sessions
**Status:** Comprehensive; covers all known research artifacts as of June 17, 2026

---

## Source Manifest

| Source | Type | Date | Key Content |
|---|---|---|---|
| `a777373e` session (9,745 msgs) | Claude Code session | Jun 14–15 | "Competitor analysis" subagent report, strategy reframing, launch positioning |
| `6c747743` session (2,212 msgs) | Claude Code session | Jun 14–15 | Competitor analysis dispatch, feature backlog generation |
| `7b98ecb1` session (113 msgs) | Claude Code session | Jun 16 | Headroom install/config — NO competitor research |
| `5948a303` session (62 msgs) | Claude Code session | Jun 16 | OpenCode permissions config — NO competitor research |
| `docs/PRODUCT_RESEARCH.md` | In-repo doc | Jun 15 | Competitive landscape, market thesis, disconfirming evidence, re-aimed strategy |
| `docs/audit/LAUNCH_STRATEGY_RESEARCH.md` | In-repo doc | Jun 15 | Competitor launch teardowns, pricing analysis, 90-day launch plan |
| `~/Downloads/conduit-competitor-research-feature-backlog-2026-06-14.md` | Session output | Jun 14 | Full competitor snapshot, community feedback themes, prioritized feature backlog |
| `~/Downloads/conduit-competitor-research-implementation-report.md` | Session output | Jun 14 | 15 features built from research; source index |
| `~/Downloads/CONDUIT_MIGRATION_HANDOFF.md` | Session output | Jun 14 | Competitor positioning references in migration context |
| `~/Downloads/conduit-session-report-2026-06-14.md` | Session output | Jun 14 | Trust & Privacy comparison table (Omnara vs Anthropic vs Conduit) |
| `~/Downloads/Conduit GitHub repo/Conduit Board.dc.html` | Design board | Jun 14–15 | Brief mention: "synthesis of owner decisions + subagent research (competitive landscape)" |

---

## 1. Market Thesis

**"Phones are not where serious software is written. They are where it is steered."**

The core job-to-be-done: attach the phone to a remote workspace, get notified the moment an agent needs a human decision, approve or reject it, review diffs and output, and redirect the agent — all without reaching for a laptop. The phone is an **approval cockpit and interrupt handler**, not a local IDE.

This is meaningfully different from:
- SSH terminal apps (Termius, Blink) — dumb pipe, no agent semantics
- Remote IDEs (Codemagic, GitHub Mobile) — editing-on-phone, different JTBD
- Local AI coding assistants — no remote agent; on-device inference only

*Source: `docs/PRODUCT_RESEARCH.md` §1*

---

## 2. Competitor-by-Competitor Breakdown

### 2.1 First-Party Competitors (Existential Threats)

#### Anthropic Remote Control
- **What:** First-party mobile/web control of local Claude Code sessions
- **Availability:** Pro+/Team/Enterprise (NOT Max-only)
- **Capabilities:** Up to 32 concurrent sessions (server mode), push notifications, Dispatch (start task FROM mobile), Channels (Telegram/Discord/iMessage)
- **Pricing:** FREE for existing Pro+/Team/Enterprise subscribers
- **Strengths:** First-party integration; zero setup for Claude users; push + Dispatch + Channels
- **Weaknesses:** "No per-event configuration" for push (Anthropic's own docs); "Claude decides when to notify" — no user control over notification granularity; no blocking-on-permission guarantee; routes traffic through Anthropic infrastructure (compliance problem)
- **Conduit vs. them:** First-party gap is the opening — Conduit's Blocked-State + enforceable per-event notifications attack the one thing first-party does worst. Plus: code never leaves user's host.
- **Source:** `code.claude.com/docs/en/remote-control` (HIGH confidence), `a777373e` L2080, `PRODUCT_RESEARCH.md` §3.2

#### OpenAI Codex Mobile
- **What:** Codex remote control in the ChatGPT app
- **Availability:** ALL plans including Free (iOS + Android)
- **Capabilities:** Approve commands, stream diffs/tests/screenshots, Remote SSH GA, secure relay
- **Pricing:** Free (included in all ChatGPT plans)
- **Strengths:** Massive user base; free tier; Remote SSH GA
- **Weaknesses:** OpenAI account required; code routes through OpenAI infrastructure
- **Conduit vs. them:** Same privacy/compliance gap as Anthropic Remote Control. Codex has same mobile approve story but no governance layer.
- **Source:** `developers.openai.com/codex/remote-connections`, TechCrunch May 14 2026 (HIGH confidence), `PRODUCT_RESEARCH.md` §3.1

#### Cursor Cloud Agents
- **What:** Announced mobile companion for Cursor IDE
- **Pricing:** Part of Cursor ecosystem ($20/mo Pro, $40/user Teams)
- **Strengths:** Cursor's $1B ARR user base; IDE integration
- **Weaknesses:** Announced only — adoption unverified; Cursor is an IDE, not a control plane
- **Source:** MEDIUM confidence — announced but unverified, `PRODUCT_RESEARCH.md` §3.1

#### GitHub Copilot Cloud Agent (Mobile)
- **What:** "Research + code from mobile" — Copilot agent on mobile
- **Availability:** Announced (April 8, 2026)
- **Source:** `github.blog/changelog/2026-04-08-github-mobile-research-and-code-with-copilot-cloud-agent-anywhere/` (MEDIUM confidence)


### 2.2 Direct Third-Party Competitors

#### Omnara (YC S25)
- **What:** Web + mobile interface for Claude Code and Codex. Agents run on user's machine; daemon relays via WebSocket to Omnara server → mobile/web clients.
- **Pricing Arc:** Started free → $9/mo → raised to $20/mo → now "100% FREE, unlimited"
- **Stars/Scale:** YC S25; App Store (88.9 MB, 4+); Google Play
- **Strengths:** YC brand + HN awareness (147 pts, 161 comments); voice dictation; Apple Watch; cloud handoff; open-source backend; worktrees; live previews; orchestration
- **Weaknesses:** Privacy concern (plaintext goes through Omnara servers); pricing confusion signals lack of conviction; cloud sync infra costs; no self-host option
- **Conduit lesson:** Validates the market but leaves privacy completely unaddressed. Conduit's blind relay is the structural moat.
- **Pricing correction note:** Earlier `PRODUCT_RESEARCH.md` §4.3 claimed Omnara "collapsed to free." Session `a777373e` L2088 corrects this: Omnara is now $20/mo unlimited, NOT collapsed to free. This is an important correction — the WTP collapse narrative in §4.3 needs updating.
- **Sources:** `omnara.com/pricing`, App Store, Google Play, `github.com/omnara-ai/omnara`, HN 44878650 + 46991591, `LAUNCH_STRATEGY_RESEARCH.md` §2.1

#### Happy (slopus/happy)
- **What:** Open-source (MIT), E2E encrypted, no telemetry/tracking mobile/web client for Claude and Codex
- **Stars:** 21.6k★ GitHub
- **Pricing:** Free (MIT license)
- **Strengths:** Strong OSS trust signal; E2E encryption; push alerts; voice; no telemetry/tracking claim
- **Weaknesses:** Open issues show notification reliability is hard and valuable (GitHub issue #1383: automatic push doesn't work consistently)
- **Sources:** `github.com/slopus/happy`, `happy.engineering/docs/faq/`, `PRODUCT_RESEARCH.md` §3.1

#### cmux (manaflow-ai/cmux)
- **What:** macOS orchestrator + iOS early access; feed-style approval cards
- **Stars:** 20.9k★ GitHub
- **Pricing:** Free (MIT)
- **Sources:** `github.com/manaflow-ai/cmux`, `PRODUCT_RESEARCH.md` §3.1

#### CloudCLI / claudecodeui (siteboon/claudecodeui)
- **What:** Cross-vendor (Claude+Cursor+Codex+Gemini), self-host/Docker/managed
- **Stars:** 11.6k★ GitHub
- **Pricing:** Free (MIT)
- **Strengths:** Cross-vendor breadth; self-host option; Docker deployment
- **Sources:** `github.com/siteboon/claudecodeui`, `PRODUCT_RESEARCH.md` §3.1


### 2.3 OSS Projects (Long Tail)

| Project | Notes | Source |
|---|---|---|
| **CC Pocket** | Self-hosted bridge for Codex/Claude, mobile/desktop clients, file/diff/git flows, model switching, minimal data collection; Tailscale for remote access | `github.com/K9i-0/ccpocket` |
| **Paseo** | Open-source, multi-vendor | Various |
| **Companion** | Multi-vendor mobile client | Various |
| **Happier** | Alternative to Happy | Various |
| **Catnip** | Agent mobile client | Various |
| **Sled** | Agent mobile client | Various |
| **CallMe** | Agent mobile client | Various |
| **PeonPing** | Agent mobile client | Various |
| **Lucarne** | Agent mobile client | Various |
| **OpenCode Mobile** | OpenCode-specific mobile client | `github.com/dzianisv/opencode-mobile` |
| **Cline Kanban** | Mobile Kanban for Cline agents | `cline.bot/blog/cline-mobile-how-to-vibe-code-from-your-phone` |
| **littleclaw** | AI coding agents iOS app | App Store |
| **AgentsRoom** | AI remote dev agent iOS app | App Store |
| **Moshi** | SSH + Mosh terminal iOS app | App Store |
| **Fewshell** | SSH terminal iOS app | App Store |

**Combined OSS GitHub stars (Happy + cmux + CloudCLI): ~54k** — a formidable "free and trusted" signal.

*Sources: `PRODUCT_RESEARCH.md` §3.1, `conduit-competitor-research-feature-backlog-2026-06-14.md` §Competitor Landscape*


### 2.4 Terminal / SSH Incumbents (Indirect)

| Product | What | Pricing | Conduit vs. Them |
|---|---|---|---|
| **Termius** | Mobile SSH client (incumbent) | $10/mo | Dumb terminal; no agent approvals; no governance |
| **Blink Shell** | Professional iOS terminal, Mosh + SSH + VS Code | $19.99/yr (14-day trial) | #1 dev tool on App Store 5+ years; 6.8K GitHub stars; Mosh = "always-on" differentiator; no agent governance |

*Sources: `termius.com/pricing`, `blink.sh`, App Store, `LAUNCH_STRATEGY_RESEARCH.md` §2.8*


### 2.5 Adjacent Competitors (Different Product, Overlapping Audience)

#### Warp
- **What:** Rust-based terminal → "Agentic Development Environment" (ADE). Terminal + Oz orchestration for cloud agents.
- **Pricing:** Free (terminal, up to 10 seats) → Build ($20/mo, 1,500 credits) → Max ($200/mo) → Business ($50/user/mo) → Enterprise
- **PH launches:** 6 launches total (494, 424, 208, 217 upvotes)
- **Strengths:** "15× revenue growth after PH launch"; 2M agents/day; open-sourced terminal (AGPL May 2026); terminal-first → agent expansion natural progression
- **Weaknesses:** Desktop-first (no mobile); credit-based pricing anxiety
- **Conduit lesson:** Multiple PH launches compound attention. Plan launches for: iOS app → SSH relay → self-host → team features.
- **Source:** `LAUNCH_STRATEGY_RESEARCH.md` §2.3

#### Portkey
- **What:** Centralized credentials, budgets, observability, provider failover, guardrails, MCP logs, audit for coding agents
- **Conduit lesson:** Portkey = gateway layer. Conduit should own host-side tool-call governance and phone-authorized approvals, not compete as an API gateway.
- **Source:** `conduit-competitor-research-feature-backlog-2026-06-14.md`

#### Tailscale
- **What:** Zero-trust mesh VPN on WireGuard. Closest GTM analogy.
- **Pricing:** Personal (free, unlimited devices, 6 users) → Standard ($8/user/mo) → Premium ($14/user/mo) → Enterprise
- **Scale:** $100M Series B, $1B+ valuation, ~5.2M monthly visitors
- **Conduit lesson:** Open-core + free-forever personal tier = grassroots adoption. Privacy/security wedge = IT trust. The Tailscale playbook translates directly to Conduit.
- **Source:** `LAUNCH_STRATEGY_RESEARCH.md` §2.5

#### Conan
- **What:** Native macOS HUD for Claude Code. Streaming timeline of prompts, tool calls, tokens.
- **Pricing:** Free download, Premium $29 one-time
- **Launch:** #7 Product of the Day Jun 14 2026 (83 upvotes); privacy stance: "no telemetry"
- **Source:** `LAUNCH_STRATEGY_RESEARCH.md` §2.7

#### Blume ("Blume Sidecar") — `blume.codes`
- **What:** Web-based **desktop** oversight/governance app for AI coding agents. Tagline "Watch every coding agent, effortlessly / Tired of steering your coding agents?" Monitors agent status (working / awaiting approval); **tracks the hidden files, skills, hooks & rules that shape agent behavior** and flags config↔instruction **drift**; approve-before-apply. Runs **locally**; supports Cursor, Claude Code, Codex, omp, Pi.
- **Overlap with Conduit:** governance/oversight + approve-before-apply + own-host + multi-vendor.
- **Where it leads Conduit:** **agent-config drift detection** (intended config vs. actual agent behavior) — Conduit has no equivalent.
- **Gap vs Conduit:** **desktop-first, not phone-native** (no mobile control / push surfaced); no audit chain / blast-radius / risk scoring; technical internals undisclosed.
- **NOT** to be confused with `blume.page` (an unrelated AI website builder).
- **Source:** blume.codes (verified 2026-06-19)

#### Orca
- **What:** Open-source mobile app to run + monitor + direct existing Claude Code agentic sessions from a phone (monitoring/direction focus).
- **Source:** explainx.ai 2026 mobile-control roundup (verified 2026-06-19)

---

## 3. Demand Signals & Pain Points

All HIGH confidence unless noted.

1. **"RAW DOG DEV ON THE SERVER"** — Pieter Levels publicly documented running Claude Code on a VPS + SSH via Termius on iPhone (Aug 2025). Three verified x.com posts. Signal: high-profile endorsement of SSH+iPhone as remote agent workflow.
   - Source: `x.com/levelsio/status/1957518592284717558` (+ 2 others)

2. **Session loss on backgrounding / SSH drop** — iOS aggressively backgrounds apps; SSH sessions drop; agent context is lost.
   - Source: `dev.to/jagafarm/stop-losing-claude-code-sessions-a-tmux-primer-for-mobile-devs-2p48`

3. **Approval fatigue** — PreToolUse hooks fire for every write/bash/edit; reviewers burn out or rubber-stamp.
   - Source: `developersdigest.tech/blog/approval-fatigue-agent-security-bug`

4. **Decision / review fatigue** — Cognitive load of each "should I approve this?" check-in compounds.
   - Source: `stackoverflow.blog/2026/05/21/coding-agents-are-giving-everyone-decision-fatigue/`

5. **"tmux on touch is miserable"** — Navigating panes, scrolling, typing approvals on touch screen is painful.
   - Source: same dev.to link as #2

6. **Notification gaps** — Most-repeated complaint: agent pauses for approval → developer has no reliable way to know unless watching the terminal.
   - Source: Repeated pattern across HN/Reddit/app-store reviews (MEDIUM confidence)

7. **Community feedback on notification reliability** (from competitor research):
   - OpenAI Community: "approval requests should trigger mobile push notifications" (`community.openai.com/t/codex-approval-requests-should-trigger-mobile-push-notifications/1381134`)
   - Claude Code GitHub issue #29438: push notifications for permission approval
   - Happy GitHub issue #1383 (Jun 2026): manual push works, automatic notification on agent finish/block does not
   - Codex GitHub issue #10760: stuck awaiting approval prompt

8. **Developer skepticism of mobile "coding"** — Reddit blunt: phone is awkward for real dev. Counter-case: checking status, approving work, nudging tasks, not "write code on phone."
   - Source: `reddit.com/r/ClaudeCode/comments/1o32vzg/` (MEDIUM confidence)

9. **Session continuity** — Approving from mobile is not enough if switching devices means losing reasoning state or relying on unreliable agent summaries.
   - Source: Reddit AI agents thread (MEDIUM confidence)

10. **Multi-project / multi-branch supervision** — Running tasks on several branches/projects, using worktrees, needing a clean dashboard.
    - Source: Competitor and community posts (MEDIUM confidence)

11. **Privacy anxiety** — OpenCode community: concerns about telemetry, "local" claims, prompts/session data leaving the machine.
    - Source: `reddit.com/r/LocalLLaMA/comments/1rv690j/` (MEDIUM confidence)

*Sources: `PRODUCT_RESEARCH.md` §2, `conduit-competitor-research-feature-backlog-2026-06-14.md` §Community Feedback*

---

## 4. Market Positioning Analysis

### 4.1 The Shift: 2025 Workaround → 2026 First-Party Feature War

The space went from "SSH + tmux + Termius" (2025) to **both Anthropic and OpenAI shipping "drive your agent from phone" natively, on all plans, for free** (2026). The generic "approve agents from your phone" wedge is now table stakes, not a differentiator.

*Source: `a777373e` L2080 "Competitor analysis" subagent report, `PRODUCT_RESEARCH.md` §4.4*

### 4.2 Conduit's Defensible Lane

**"The governed, self-hosted, cross-vendor control plane for AI coding agents."**

Positioning reframe (from session `a777373e` L8762, L8791):
> NOT just a mobile Claude client — that market is crowded by Anthropic Remote Control, Omnara, Happy, CodeVibe.
> Conduit = "mobile approval firewall + audit cockpit for AI coding agents"

Three structural wedges:
1. **Privacy/Security** — Code never leaves user's host. Blind E2E relay (X25519 + ChaCha20-Poly1305). No vendor sees your code. Anthropic Remote Control and Omnara both route traffic through their infrastructure.
2. **Apple-exclusive surfaces** — Live Activities, Dynamic Island, Apple Watch approval. Web/Electron rivals structurally can't match native iOS quality.
3. **Cross-vendor** — Claude + Codex + OpenCode (later Cursor/Gemini). Anti-lock-in: "You control the bridge. Your code stays on your host."

### 4.3 Positioning Progression (from earlier to current)

| Stage | Old Positioning | New Positioning |
|---|---|---|
| Pre-research | "Approve AI coding agents from your phone" | — |
| Post-research v1 | "Govern the AI coding agents running on your own machines" | Self-hosted control plane |
| Launch reframe | "Mobile approval firewall + audit cockpit for AI coding agents" | Privacy-first, governed |

### 4.4 Trust & Privacy Comparison Table
(from `conduit-session-report-2026-06-14.md` Task 3, wired into Settings > Trust & Privacy)

| | Code Leaves Host? | Model Goes to Cloud? | Relay Reads Messages? |
|---|---|---|---|
| **Omnara** | Yes | Yes | Yes |
| **Anthropic Remote Control** | Yes | Yes | Yes |
| **Conduit** | **No** (green) | **No** (green) | **No** (green) |

### 4.5 "Better Free Mobile Client" = Lost Lane
First-party Anthropic Remote Control (free for Pro+/Team/Enterprise) + 54k combined OSS GitHub stars + ~15 OSS projects = "better free Claude Code phone client" is not a viable strategy. Cross-vendor breadth alone is also not a moat (CloudCLI, Paseo, Companion, Happier already multi-vendor).

*Source: `PRODUCT_RESEARCH.md` §4.4, §4.5*

---

## 5. Pricing Research & Analysis

### 5.1 Competitor Pricing Snapshot

| Product | Consumer Price | Enterprise/Team | Model |
|---|---|---|---|
| Anthropic Remote Control | FREE (Pro+ $20/mo, Team $25/user/mo, Enterprise custom) | Included in plan | Bundled |
| OpenAI Codex Mobile | FREE (all plans incl. free) | N/A | Bundled |
| Omnara | FREE (was $9→$20→free) | N/A | Freemium collapse |
| Happy | FREE (MIT OSS) | N/A | Open source |
| cmux | FREE (MIT OSS) | N/A | Open source |
| CloudCLI | FREE (MIT OSS) | N/A | Open source |
| Termius | $10/mo | — | Subscription |
| Blink Shell | $19.99/yr | — | Subscription |
| Cursor | $20/mo Pro, $40/user Teams, $60-200/mo higher tiers | Enterprise custom | PLG freemium |
| Warp | Free; Build $20/mo; Max $200/mo; Biz $50/user/mo | Enterprise custom | Freemium + credits |
| Conan | Free download; Premium $29 one-time | N/A | One-time |
| Tailscale | Free (6 users); $8/user/mo Standard; $14/user/mo Premium | Enterprise custom | Open-core freemium |

### 5.2 WTP Signals

- **Consumer WTP is near zero** — Omnara's pricing arc ($9 → $20 → free) signals that consumer willingness-to-pay for agent mobile clients is very low OR the market is not mature enough for recurring consumer pricing. However, session `a777373e` L2088 corrects: Omnara is now $20/mo unlimited, NOT "collapsed to free." The pricing confusion itself is the signal — this market hasn't settled on a pricing anchor.
- **Enterprise WTP exists:** Termius $10/mo and Blink $19.99/yr prove developers pay for transport-grade reliability on iOS.
- **$20/mo is the anchor price for AI dev tools** (Cursor Pro, Warp Build are both $20/mo). Conduit as a companion (not IDE) should be lower.

### 5.3 Recommended Conduit Pricing
(from `LAUNCH_STRATEGY_RESEARCH.md` §3.2)

| Tier | Price | Key Features |
|---|---|---|
| Personal (Self-Host) | Free forever | Run own relay, full encryption, all integrations, AGPL |
| Personal (Cloud Relay) | Free forever | Conduit-hosted relay, 5 sessions/mo, push, community support |
| Pro (Cloud Relay) | $9/mo or $89/yr | Unlimited sessions, priority relay, team sharing (up to 5), email support |
| Teams (Cloud Relay) | $25/user/mo | Unlimited members, SSO/SAML, audit logs, self-host relay option, SLA |
| Enterprise | Custom | Dedicated relay, on-prem, SOC2/HIPAA, admin API, white-glove |

**Rationale:** $9/mo matches Omnara's price point, undercuts Warp/Cursor ($20). Flat pricing (no credits) at launch — Replit and Warp credit systems are widely criticized as opaque. Self-host free removes "what if you go under?" objection.

**Conversion funnel prediction:** Free → Pro at 5–8%. Teams upsell at 8–12% of Pro users. Self-host users convert at lower rates but serve as marketing/credibility engine.

### 5.4 Pricing Anti-Patterns (from competitor analysis)
1. **Don't do credit-based usage pricing at launch** — Replit's system is "opaque and anxiety-inducing"; Warp's creates "I don't know what I'll pay" fear.
2. **Don't skip the free tier** — Blink's forced trial attracts bad reviews; Cursor's free Hobby tier powered $100M ARR.
3. **Don't price too low** — Conan's $29 one-time is hobby pricing; $9/mo is the floor for a paid tier with relay infra.

*Sources: `LAUNCH_STRATEGY_RESEARCH.md` §3, §6.2*

---

## 6. Disconfirming Evidence & Thesis Risks

### CRITICAL: First-Party Anthropic Remote Control
Anthropic ships multi-session + push + Dispatch + start-from-mobile, FREE for Pro+/Team/Enterprise. Any developer already paying for Claude Pro gets this for free. This is direct competition in Conduit's exact use case.

### CRITICAL: OSS Field Is Crowded
~54k combined stars (Happy + cmux + CloudCLI), all MIT-licensed, all free. Actively maintained with community trust.

### HIGH: Consumer WTP Uncertain
Omnara's pricing arc ($9 → $20 → now $20/mo unlimited with confusion in between) shows the market hasn't stabilized. Consumer willingness-to-pay is not proven.

### HIGH: Distribution Is the Biggest Risk
"Conduit will be the best-built and least-known app in a crowded field." Mitigation: open-source conduitd bridge (Happy/CloudCLI model of earning trust via OSS); beachhead underserved niche first; positioning that Anthropic Remote Control structurally cannot undercut ("your code never leaves your host").

### MEDIUM: Cross-Vendor Alone Is Not a Moat
CloudCLI (11.6k★), Paseo, Companion, Happier already support multiple vendors. Cross-vendor is table-stakes once peers catch up.

### MEDIUM: X/Twitter Engagement Numbers Unverified
Levels posts identified by URL, but specific engagement metrics (views, likes) not verified via authenticated access.

*Sources: `PRODUCT_RESEARCH.md` §4, `a777373e` L2088*

---

## 7. Strategy Evolution (from Sessions)

### 7.1 Original Strategy (user's launch plan, reviewed in a777373e L8762)
- Positioning: "Privacy-first iOS control plane for AI coding agents"
- Wedge: agents keep running on user's machine, Conduit monitors/approves/denies/edits from phone
- Pricing: free self-host tier, free limited cloud relay, $9-$12/mo Pro, later Teams/Enterprise
- Distribution: Show HN + Product Hunt + Reddit + X/Twitter + Discord + TestFlight + App Store SEO
- Message: privacy/security as core

### 7.2 Claude's Corrections (from verified market data)
- **Positioning:** "Private mobile Claude client" is crowded → reframe as "mobile approval firewall + audit cockpit" — governance, not access
- **Pricing:** Flat Pro pricing confirmed as correct (no credits). Self-host free tier confirmed as essential.
- **Demo:** Must show the *approval firewall loop*, not "chat with Claude from phone" — that's the commodity competitor demo
- **3-day reality:** Full HN/PH blitz in 3 days = wrong move. Phase-1 validation beta (TestFlight + landing page + demo) is the right 3-day target

### 7.3 Final Re-Aimed Strategy (PRODUCT_RESEARCH.md §5)

**Stage 1 — Reliability + native-iOS notifications:**
- Rock-solid reconnect engine (NWPathMonitor + backoff + AutoReconnectEngine — already built)
- Live Activities / Dynamic Island / Apple Watch approval
- Structured approval cards
- Rivals can't copy: Apple-exclusive APIs

**Stage 2 — Security / self-host / enterprise:**
- E2E, on-premises bridge (conduitd), Secure Enclave / TOFU (already built)
- Audit log (already built), team approval routing
- Pricing: team seats / enterprise tier ($25/user/mo)
- Open-source conduitd bridge

**Stage 3 — Cross-vendor breadth:**
- Claude + Codex first; later Cursor / Gemini
- Anti-lock-in wedge: "You control the bridge. Your code stays on your host."

**Beachhead:** Security-conscious / enterprise / regulated developers (NOT broad consumer launch)

---

## 8. Research-Informed Implementation

The `conduit-competitor-research-feature-backlog-2026-06-14.md` research spawned **15 features** built across Go (daemon) and Swift (iOS) in the `conduit-competitor-research-implementation-report.md`:

### P0 (Built — Core Reliability & Trust)
1. **Blocked State OS** — State machine + APNs proof + stale-decision handling + notification preferences
2. **conduit doctor** — Setup health check (6 checks: daemon version, hooks, auth, policy, permissions, local models)
3. **Privacy Badge** — Local/Cloud/E2E Relay variants with visual indicators
4. **opencode status-reader path fix** — Config path corrected from `~/.local/share/opencode/` to `~/.config/opencode/`
5. **Scoped Allow-Always Manager** — Scopes by repo, path, command pattern, tool, vendor, time window; one-tap revoke
6. **Loop Object** — Goal, plan, current blocker, host/repo/worktree, files, tests, approvals, spend, proof
7. **Proof Card** — Completion summary: tests, diffs, commands, approvals, policy exceptions, spend, PR link
8. **Policy Simulator** — "Last 7 days: this policy would auto-approve X, ask Y, deny Z"

### P1 (Built — Strong Differentiators)
9. **Tamper-Evident Audit** — Hash-chained local JSONL; export; verify command
10. **Quota/Spend Guardrails** — Per-provider budgets, burn-rate, alerts, pause-on-threshold
11. **Host Availability Guard** — Sleep/lid/battery/network/APNs checks; health badge
12. **Secrets Broker** — Agent requests credential → daemon holds → phone authorizes scoped use
13. **Worktree/Branch Board** — Active/Review Ready/Idle worktree columns
14. **CI/PR Event Integration** — GitHub webhook receiver; PR/check events in LoopDetailView
15. **Adapter SPI + conduit-mcp Gateway** — Documented SPI + MCP gateway for Goose/Cline/Roo/Kilo

### T0 Foundation Built Simultaneously
16. **E2E Bidirectional Relay** — WebSocket relay server + daemon E2E client + iOS E2E relay client. Blind ciphertext relay, no Tailscale required.

### Not Yet Built (from research plan)
- Voice nudge mode (P2 — competitors already have it)
- Watch + lock-screen deep actions (P2 — needs APNs reliability proven first)
- Team policy packs (P2 — premature before single-user reliability)
- Self-hosted relay package (P2 — OSS trust tier)
- Local small-model assistant (P2)
- Adapter marketplace (P2)

### Features Explicitly Avoided
1. Full mobile IDE/editor
2. Generic SSH terminal positioning
3. Generic hosted cloud sandbox
4. Voice-first coding
5. Broad LLM API gateway (Portkey territory)
6. opencode-only mobile client

---

## 9. Key URLs & References

### Competitor Sites
- Omnara: `omnara.com`, `github.com/omnara-ai/omnara`, App Store + Google Play
- Happy: `github.com/slopus/happy`, `happy.engineering/docs/faq/`
- cmux: `github.com/manaflow-ai/cmux`
- CloudCLI: `github.com/siteboon/claudecodeui`
- CC Pocket: `github.com/K9i-0/ccpocket`
- OpenCode Mobile: `github.com/dzianisv/opencode-mobile`
- Cline Kanban: `cline.bot/blog/cline-mobile-how-to-vibe-code-from-your-phone`
- Portkey: `portkey.ai/docs/product/coding-agent`
- Warp: `warp.dev/pricing`
- Tailscale: `tailscale.com/pricing`
- Conan: `conan.sh`, Product Hunt
- Blink Shell: `blink.sh`, App Store

### Official Agent Docs
- Claude Code Remote Control: `code.claude.com/docs/en/remote-control`
- Claude Code Hooks (PreToolUse + Notification): `code.claude.com/docs/en/hooks`
- Claude Code Agent SDK `canUseTool`: `code.claude.com/docs/en/agent-sdk/permissions`
- OpenAI Codex Remote: `developers.openai.com/codex/remote-connections`
- OpenAI Codex Hooks: `developers.openai.com/codex/hooks`

### Community Pain Points
- Session loss: `dev.to/jagafarm/stop-losing-claude-code-sessions-a-tmux-primer-for-mobile-devs-2p48`
- Approval fatigue: `developersdigest.tech/blog/approval-fatigue-agent-security-bug`
- Decision fatigue: `stackoverflow.blog/2026/05/21/coding-agents-are-giving-everyone-decision-fatigue/`
- Codex push notifications: `community.openai.com/t/codex-approval-requests-should-trigger-mobile-push-notifications/1381134`
- Claude Code push issue: `github.com/anthropics/claude-code/issues/29438`
- Happy push issue: `github.com/slopus/happy/issues/1383`
- Codex stuck approval: `github.com/openai/codex/issues/10760`
- Mobile dev skepticism: `reddit.com/r/ClaudeCode/comments/1o32vzg/`
- OpenCode privacy concerns: `reddit.com/r/LocalLLaMA/comments/1rv690j/`

### Launch Strategy References (full list in LAUNCH_STRATEGY_RESEARCH.md §8)
- HN Launch: `ilin.pt/marketing/strategy/community/2025/07/08/show-hn-guide.html`
- PLG Benchmarks: `productled.com/blog/product-led-growth-benchmarks`
- App Store Rejection: `appbot.co/blog/app-store-app-review-approval-vibe-coded-delays-2026`
- Reddit SaaS Launch: `redship.io/blog/how-to-launch-saas-on-reddit`

---

## 10. Session-Level Activity Summary

### a777373e (Jun 14-15, 9,745 msgs) — THE MAIN DESIGN SESSION
- Competitor analysis subagent dispatched → comprehensive competitive landscape report
- Strategy reframing: "mobile approval firewall + audit cockpit" vs "mobile Claude client"
- Launch plan review with market-verified corrections
- Omnara pricing correction: $20/mo unlimited, NOT "collapsed to free"
- E2E relay proven end-to-end
- Multiple architecture discussions comparing relay vs SSH vs Omnara approach
- All 15+ features from competitor research backlog planned and mostly built

### 6c747743 (Jun 14-15, 2,212 msgs)
- Competitor analysis dispatch
- Feature backlog generated from research
- Implementation planning based on competitive gaps

### 7b98ecb1 (Jun 16, 113 msgs)
- Headroom context compression tool install/configuration
- NO competitor/market research content

### 5948a303 (Jun 16, 62 msgs)
- OpenCode permissions configuration (`.config/opencode/opencode.json`)
- NO competitor/market research content

### Design Board (Jun 14-15)
- `Conduit Board.dc.html`: mentions "synthesis of owner decisions + subagent research (competitive landscape)" and notes Happy Coder + Omnara ship real-time voice
- All other `.dc.html` files: UI/feature design, no research content

---

*End of compiled research. All sources verified against primary session data and in-repo documentation.*