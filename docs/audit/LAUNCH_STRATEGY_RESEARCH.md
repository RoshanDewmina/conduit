# Launch Strategy Research: Conduit

> **Product:** Conduit — iOS mobile control plane for AI coding-agent loops.
> **File:** `docs/audit/LAUNCH_STRATEGY_RESEARCH.md`
> **Date:** 2026-06-15

---

## Table of Contents

1. Executive Summary: Top 5 Recommendations
2. Competitor Launch Teardowns
   - 2.1 Omnara (YC S25)
   - 2.2 Cursor (Anysphere)
   - 2.3 Warp
   - 2.4 Replit
   - 2.5 Tailscale
   - 2.6 Linear
   - 2.7 Conan (adjacent benchmark)
   - 2.8 Blink Shell (iOS market benchmark)
3. Pricing & Monetization Options for Conduit
   - 3.1 Analysis of Available Models
   - 3.2 Recommended Model
   - 3.3 Rough Price Points
4. Short-Term Profit Levers (Months 0–3)
5. Long-Term Moat & Retention (Months 3–18)
6. Risks & Anti-Patterns
7. 90-Day Launch Checklist
8. Sources & References

---

## 1. Executive Summary: Top 5 Recommendations

1. **Ship a free‑forever Personal tier immediately; monetize via a single Pro subscription at $9–$12/mo (or $99/yr) with a 14‑day free trial, no usage caps.** The leading direct competitor (Omnara) charges $9/mo after 10 free sessions. Warp charges $20/mo for its Build tier. Cursor charges $20/mo for Pro. Blink Shell charges $19.99/yr. $9–$12/mo is the sweet spot for a mobile‑first companion that doesn't replace a full IDE. Usage‑based pricing (relay minutes, agent runs) adds complexity too early — start simple, add credits later.

2. **Lead with the privacy narrative in every piece of copy.** Conduit's blind‑relay, X25519/ChaCha20, ciphertext‑only forwarding is the single strongest differentiator vs. Omnara (which relays plaintext through its servers). This is Tailscale's playbook. Own "private agent control plane."

3. **Launch via Show HN + Product Hunt on the same week, seeded by 2–3 weeks of Reddit credibility-building (r/iOSProgramming, r/ClaudeAI, r/coding).** Developer tools that launch on HN and PH together see 3–5× the sustained traffic of a single‑channel launch. Conan (#7 PH on June 14, 2026, $29 one‑time) proves the App Store + PH combo works for Claude Code adjacencies.

4. **Self‑host free + relay‑hosted paid is your wedge into enterprise.** Give teams the option to run their own relay (open‑core, AGPL). Sell the hosted relay with SLA, SSO, team management, audit logs, and priority support at $20–$30/user/mo. Mirror Tailscale's self‑serve personal → team expansion motion.

5. **Invest in App Store presence and TestFlight from Day 1 — not as an afterthought.** Conduit lives on the App Store. Apple has tightened review for AI/agent apps in 2026 (ref: Appbot analysis, "stricter reviews, more manual checks"). Pre‑submit early, test with TestFlight, budget for rejection cycles. The App Store is both a distribution channel and a chokepoint.

---

## 2. Competitor Launch Teardowns

### 2.1 Omnara (YC S25)

**What it is:** Web + mobile interface for Claude Code and Codex. Agents run on your machine; a daemon relays messages via WebSocket to Omnara's server, which pushes to web/mobile clients. Desktop app bundles the CLI.

**Launch timeline:**
- YC S25 batch (summer 2025)
- First Show HN: `Show HN: Omnara – Run Claude Code from anywhere` (44878650) — 147 points, 161 comments
- Launch YC: `Launch HN: Omnara (YC S25)` (46991591) — 4 months ago from June 2026
- Product Hunt: listed but not a high‑profile PH #1
- App Store: iOS app live, 88.9 MB, 4+ age rating

**Pricing model:**
- 100% free tier initially (unlimited sessions, no paywall)
- Then: Free for 10 sessions/month, $9/mo unlimited
- Current (as of early 2026): "Omnara is 100% free, with unlimited sessions" — appears to have reverted/re‑expanded free tier
- Cloud sync (laptop offline → cloud continuation) is a paid differentiator

**What worked:**
- YC brand + HN launch generated strong awareness (147 points, 161 comments on Show HN)
- Free tier drove adoption; the problem ("agent stalls while I'm away") resonates viscerally
- Voice dictation + mobile control is a clear demo hook
- Open‑source backend (github.com/omnara-ai/omnara) built developer trust

**What flopped / risks:**
- Pivoted from CLI wrapper to full daemon + GUI — significant engineering churn
- Early HN comments flagged "waiting for response" stalls (terminal output parsing is fragile)
- Pricing confusion: free → $9 → free again signals lack of conviction
- Cloud sync ("laptop goes offline") is a compelling pitch but a massive infra cost — they're essentially running a cloud IDE backend
- No self‑host option, so all traffic goes through Omnara servers (privacy concern for enterprise)

**Conduit lesson:** Omnara validates the market ("agents from phone") but leaves the privacy angle completely unaddressed. Their relay sees plaintext. Conduit's blind relay is a moat.

### 2.2 Cursor (Anysphere)

**What it is:** AI‑native IDE (VS Code fork) with multi‑model agentic coding, Composer, Cloud Agents.

**Launch & growth (documented history):**
| Milestone | Date |
|---|---|
| $1M ARR | Dec 2023 |
| $100M ARR | Mid 2024 (zero marketing spend) |
| $300M ARR | Early 2025 |
| $500M ARR | Aug 2025 |
| $1B ARR | Nov 2025 |
| $29.3B valuation | Series D Nov 2025 |

**Why it worked:**
- **PLG perfection:** 36% free‑to‑paid conversion (industry median is 5%). Developers installed it, loved it, paid.
- **Zero marketing to $100M** — pure product quality and word of mouth.
- **Team expansion:** Individual developer adoption led to team/org purchases (100× enterprise revenue growth in 2025).
- **Land‑and‑expand:** Free Hobby → $20 Pro → $40/user Teams → Enterprise custom.

**Pricing:**
- Hobby (free): limited completions
- Pro ($20/mo): full agent access
- Pro+ ($60/mo): heavier usage
- Ultra ($200/mo): max capacity
- Teams ($40/user/mo)
- Enterprise (custom)

**Conduit lesson:** Cursor proves that a dev‑first PLG motion with a generous free tier and frictionless upgrade path ($20/mo is the anchor price for AI dev tools) can produce extraordinary results. But Cursor is an IDE — a primary tool. Conduit is a companion. The PLG principles apply; the price point must be lower.

### 2.3 Warp

**What it is:** Rust‑based terminal → "Agentic Development Environment" (ADE). Includes Warp Terminal + Oz orchestration platform for cloud agents.

**Launch history (Product Hunt):**
- Warp (terminal): PH #2 of day, March 2023 — 494 upvotes
- Agent Mode: PH June 2024
- Warp 2.0 (ADE): PH June 2025 — 424 upvotes
- Oz by Warp: PH Feb 2026 — 208 upvotes
- Warp Open‑Source: PH May 2026 — 217 upvotes

**Pricing:**
- Free: terminal + limited agents, up to 10 seats
- Build ($20/mo): 1,500 credits/month for agents
- Max ($200/mo): 12× credits of Build
- Business ($50/user/mo): team management
- Enterprise (custom)

**What worked:**
- Multiple staged launches (6 PH launches total) kept compounding attention
- Terminal‑first → agent expansion was a natural progression, not a pivot
- "15× revenue growth one month after PH launch" (2M agents/day reported mid‑2025)
- #1 on Terminal‑Bench, top 5 on SWE‑bench — credibility through benchmarks
- Open‑sourcing the terminal (AGPL) in May 2026 was a community trust move

**What flopped / risks:**
- Early versions had poor vi‑mode and git autocomplete (community frustration)
- Building a terminal from scratch in Rust was years of work before agents were viable
- Credit‑based pricing creates "sticker shock" anxiety (common criticism in reviews)
- Oz (cloud agents) requires significant cloud infra investment

**Conduit lesson:** Multiple launches compound attention. Warp launched 6 separate times on PH. Conduit should plan launches for: (1) iOS app launch, (2) SSH relay launch, (3) self‑host launch, (4) team/enterprise features.

### 2.4 Replit

**What it is:** Browser‑based IDE + AI agent (Replit Agent) + hosting + database. All‑in‑one platform.

**Scale:**
- $100M ARR (announced June 2025)
- 30M+ registered users
- Google Cloud Partner of the Year 2026 (AI Tooling)

**Pricing evolution:**
- Originally flat $7/mo Hacker plan
- Shifted to credit‑based "effort‑based pricing" in 2025
- Current: Starter (free), Core ($17–$20/mo), Teams ($35/user/mo → replaced by Pro $100/mo flat in 2026), Enterprise (custom)
- Credits = AI calls + compute + deployments + outbound data

**What worked:**
- "Vibe coding" wave (natural language → deployed app) created massive consumer + prosumer demand
- All‑in‑one eliminates switching cost — write, run, host in one place
- Enterprise partnerships (Zillow, HubSpot, Google Cloud)
- Replit Agent effort‑based pricing aligns cost with value

**What flopped / risks:**
- Credit system is confusing — users report "hidden charges," "overage sticker shock"
- 1,200 min/month dev time cap on free tier is tight
- Platform lock‑in (can't easily migrate off Replit)
- Enterprise teams find it insufficient vs. local dev environments

**Conduit lesson:** Avoid opaque credit systems at launch. Replit's pricing complexity is a known pain point. Simplicity wins at early stage.

### 2.5 Tailscale

**What it is:** Zero‑trust mesh VPN built on WireGuard. Freemium → paid team/business model.

**Scale:**
- $100M Series B at $1B+ valuation (2022)
- ~5.2M monthly website visitors
- Trusted by Instacart, Cribl, Mercury, Hugging Face

**Pricing:**
- Personal (free): unlimited devices, up to 6 users, 1,000 min ephemeral resources/month
- Standard ($8/user/mo): SCIM, MDM, device posture
- Premium ($14/user/mo): device approval, ACL monitoring
- Enterprise (custom)

**What worked:**
- **Open‑core + free‑forever personal tier** built massive grassroots adoption
- **Privacy/security as a wedge** — "Zero Trust" narrative resonates with IT and developers
- **Generous free tier** (unlimited devices, 6 users) means teams organically adopt before buying
- **Community → standard → premium** tier progression maps to startup growth stages
- Content engine: blog, conference (TailscaleUp), zero‑trust report

**Conduit lesson:** This is the closest GTM analogy. Tailscale sells "private, secure connectivity." Conduit sells "private, secure agent relay." The open‑core model, generous personal tier, $8/user team upsell, and privacy‑first positioning all translate directly.

### 2.6 Linear

**What it is:** Project management/issue tracking for product teams. Keyboard‑first, opinionated, beautiful.

**Scale:**
- $1.25B valuation
- 20,000+ customers (OpenAI, Ramp, Vercel)
- 4.9 rating on PH across 400+ reviews

**Launch story (documented in Aakash Gupta's deep dive):**
- 2018: Founders (ex‑Airbnb, Coinbase, Uber) started building
- 2019: $4.2M seed from Sequoia → private beta
- June 2020: Public launch on Product Hunt (#1 of day + week → Golden Kitty Top Product 2020)
- Growth via: craft/quality signal, founder Twitter, developer advocacy, integrations with GitHub/GitLab/Slack
- No paid marketing until Series A

**What worked:**
- **Obsessive craftsmanship** — speed, design, keyboard shortcuts became the story
- **Opinionated software** — "one really good way of doing things" rather than infinite configurability
- **Developer credibility** — founders from Airbnb/Coinbase/Uber; built for ICs who hated Jira
- **Land‑and‑expand** — small team adoption → org‑wide rollout
- **Product Hunt + direct word of mouth** — no paid channels

**Conduit lesson:** Linear's playbook is opinionated quality plus founder‑led craft narrative. Don't try to be everything. Be the best at one thing (private agent relay from iOS).

### 2.7 Conan (adjacent benchmark)

**What it is:** Native macOS HUD for Claude Code. Streaming timeline of prompts, tool calls, tokens. #7 Product of the Day on June 14, 2026.

**Pricing:** Free to download. Premium unlock $29 one‑time, no subscription.

**Launch:**
- Product Hunt: #7 of day on June 14, 2026 (83 upvotes, 10 comments)
- Reddit launch: r/ClaudeAI + r/SideProject
- Hunter: Randy Daniel

**Conduit lesson:** Conan proves a focused Claude Code companion can monetize on the App Store ecosystem. The $29 one‑time price is conservative (likely too low for long‑term sustainment, but good for early velocity). Conan's privacy stance ("no telemetry, nothing about your code or prompts ever leaves the machine") mirrors Conduit's blind‑relay differentiator.

### 2.8 Blink Shell (iOS market benchmark)

**What it is:** Professional terminal for iOS/iPadOS. Mosh + SSH + VS Code integration.

**Scale:** #1 developer tool on App Store for 5+ years. 6.8K GitHub stars.

**Pricing:** 14‑day free trial, then $19.99/year subscription. In‑app purchases for advanced features (Blink Build).

**What worked:**
- **Mosh as a differentiator** — always‑on connections survive network changes, sleep, app switching
- **Hardware keyboard support + external display** — made iPad a legitimate dev machine
- **Community trust** — open‑source (GPL‑3.0), active GitHub, Discord, Reddit
- **App Store dominance** — "Developer Tool" category leadership for years

**What flopped / risks:**
- Forced trial → subscription model frustrated some users (recent reviews complain "useless app unless you pay")
- Mosh support quality complaints in recent reviews
- $19.99/yr may be underpriced relative to value

**Conduit lesson:** Blink proves a paid iOS developer tool at $19.99/yr can sustain a business. However, the forced trial friction is a warning — Conduit should keep a genuinely useful free tier. Mosh's "always on" property is exactly what Conduit should claim via its relay architecture.

---

## 3. Pricing & Monetization Options for Conduit

### 3.1 Analysis of Available Models

| Model | Example | Pros | Cons | Fit for Conduit |
|---|---|---|---|---|
| **Freemium (usage‑capped)** | Omnara (10 free sessions/mo → $9), Replit (daily credits) | Low barrier, viral potential, PLG | 2–5% conversion; free users cost money | Moderate. Good for awareness but Conduit's relay has real server costs |
| **Free‑forever Personal + Paid Pro** | Tailscale (free up to 6 users), Warp (free up to 10 seats) | Generates massive grassroots adoption; teams buy | Need clear Pro value; free tier must be useful alone | **Best fit.** Mirror Tailscale exactly |
| **One‑time purchase** | Conan ($29), Blink ($19.99/yr) | Simple, no churn mgmt | Low LTV; no expansion revenue; harder to fund relay infra | Poor fit — relay has ongoing server costs |
| **Subscription (flat)** | Cursor Pro ($20/mo), Linear ($8/user/mo) | Predictable revenue, simple messaging | High price expectation; need to justify monthly charge | Good for Pro tier |
| **Usage‑based (credits)** | Warp Build ($20 + 1,500 credits), Replit Core ($20 + $25 credits) | Aligns cost with value | Sticker shock, confusing, hard to forecast | Avoid at launch; consider later for heavy relay users |
| **Open‑core (self‑host free, relay paid)** | Tailscale, GitLab | Enterprise trust, no vendor lock‑in objection | Self‑host users never pay; support burden | **Essential.** Self‑host is Conduit's best enterprise wedge |

### 3.2 Recommended Model

**Two‑track, four‑tier:**

| Tier | Price | For | Key features |
|---|---|---|---|
| Personal (Self‑Host) | Free forever | Solo devs, privacy maximalists | Run your own relay. Full encryption. All agent integrations. Community support. AGPL. |
| Personal (Cloud Relay) | Free forever | Solo devs who want convenience | Conduit‑hosted relay. 5 active sessions/month. Push notifications. Community support. |
| Pro (Cloud Relay) | $9/mo or $89/yr | Active solo devs, power users | Unlimited sessions. Priority relay (lower latency). Team sharing (up to 5 members). Email support. |
| Teams (Cloud Relay) | $25/user/mo | Small teams, startups | Everything in Pro. Unlimited team members. SSO/SAML. Audit logs. Self‑host relay option. SLA. Slack/Discord support. |
| Enterprise | Custom | Orgs with compliance needs | Dedicated relay infra. On‑prem deployment. SOC2/HIPAA. Admin API. White‑glove onboarding. |

**Rationale:**

- **$9/mo Pro** matches Omnara's price point and undercuts Warp ($20) and Cursor ($20). It's low enough for impulse purchase by individual developers, high enough for meaningful revenue.
- **$89/yr** (≈$7.42/mo) incentivizes annual commitment. Target: 40% annual mix.
- **Free self‑host** removes the "what if you go under?" objection that kills early‑stage dev tools. It also feeds the open‑core community engine.
- **Free cloud relay (5 sessions/mo)** is enough for weekend experimentation but hits a wall for daily use. The conversion trigger is "I'm using this every day."
- **$25/user/mo Teams** is premium but reasonable for a team where Conduit replaces Slack pings, SSH config, and terminal tmux juggling.

**Conversion funnel prediction:** Free → Pro at 5–8% (consistent with PLG benchmarks for $9/mo products). Self‑host users convert at lower rates but serve as marketing/credibility engine. Teams upsell from Pro should be targeted at 8–12% of Pro users.

### 3.3 Rough Price Points (Annual equivalent)

| Tier | Monthly | Annual (per mo) | Annual (total) |
|---|---|---|---|
| Personal (Self‑Host) | $0 | $0 | $0 |
| Personal (Cloud) | $0 | $0 | $0 |
| Pro | $9 | $7.42 | $89 |
| Teams | $25/user | $21/user | $250/user |
| Enterprise | Custom | Custom | Custom |

---

## 4. Short‑Term Profit Levers (Months 0–3)

### 4.1 Launch Channels (Priority Order)

1. **Show HN ("Show HN: Conduit — Private agent relay for Claude Code on iOS")**
   - Post Tue–Thu 9 AM–12 PM EST
   - Title formula: literal, no marketing adjectives, under 80 chars
   - First comment: candid "why we built this" + technical detail (blind relay, X25519/ChaCha20, the specific architecture)
   - Expected: 100–300 points if execution is good; 5K–20K visitors
   - Source: [HN Launch Strategy Guide](https://launchweek.ai/launch/hacker-news), [HN Launch Playbook](https://ilin.pt/marketing/strategy/community/2025/07/08/show-hn-guide.html)

2. **Product Hunt (same week as HN)**
   - Launch on a Tuesday or Wednesday
   - Seed hunters from your network; aim for a known hunter in dev tools
   - Prepare: GIF demo of the iOS app receiving a push notification and approving a tool call
   - The PH audience loves: privacy narrative, clean mobile UI, "works with Claude Code/Codex"
   - Expected: Top 5 of day if well‑executed; 200–500 upvotes

3. **Reddit credibility building (Weeks 1–3, then launch post)**
   - Subreddits: r/iOSProgramming, r/ClaudeAI, r/coding, r/devops, r/netsec (for the privacy angle)
   - Phase 1 (Days 1–14): *No product mentions.* Contribute genuine technical discussion. Build karma.
   - Phase 2 (Days 15–17): Pre‑warm with a technical blog post (e.g., "How we built a blind relay with X25519 and ChaCha20")
   - Phase 3 (Day 18): Launch post in r/iOSProgramming and r/ClaudeAI
   - Phase 4 (Days 19–25): Engage on the launch threads, answer every comment, fix bugs
   - Source: [30‑day Reddit launch playbook](https://redship.io/blog/how-to-launch-saas-on-reddit)

4. **Founder‑led content**
   - Twitter/X thread: "I built an iOS app that lets me approve Claude Code tool calls from my phone — here's how the encryption works"
   - Technical blog on the blind relay architecture (cross‑post to HN as a separate "Show HN: I built a blind relay" post)
   - One loom/Loom demo video (2 min max) showing the core loop: agent runs → phone buzzes → tap approve → agent continues

5. **Discord community**
   - Launch a Discord on Day 1
   - Seed with 10–20 power users from your network
   - Channel structure: #general, #show-and-tell, #relay-self-host, #feature-requests, #security-discussion
   - Discord is where developer tools win or lose community trust

6. **App Store Optimization**
   - Keywords: "Claude Code remote", "agent control", "AI coding", "SSH terminal", "developer tools"
   - Screenshots: show the push notification, the chat view, the diff approval flow
   - Category: Developer Tools (not Productivity)
   - Pre‑submit to TestFlight 2–3 weeks before launch; recruit testers from HN/Reddit

### 4.2 Waitlist Mechanics (for the cloud relay tier)

- **Do not use a generic email waitlist.** Developers hate them. Instead:
  - Open TestFlight immediately with a "beta" label
  - Offer "early adopter pricing" — first 500 Pro subscribers lock in $5/mo forever
  - Make the waitlist *active*: users who sign up get early access within 48 hours, not "we'll email you"

### 4.3 Launch week budget

| Item | Estimated cost |
|---|---|
| Apple Developer Program | $99/yr (already paid) |
| Product Hunt featured badge | $0 (earned) |
| Relay server (launch month, low‑volume) | ~$200 on a small VPS or Fly.io |
| TestFlight (free) | $0 |
| Domain + landing page | ~$20/yr |
| **Total launch month burn** | **~$220 + time** |

---

## 5. Long‑Term Moat & Retention (Months 3–18)

### 5.1 The Privacy Moat

Privacy is Conduit's single strongest long‑term defensibility. No competitor (Omnara, Warp, Conan) offers a blind relay where *the server cannot see the content*. This is a structural advantage, not a feature bullet.

**Playbook (from Tailscale):**
- Publish a security/architecture whitepaper (cite the crypto: X25519 ECDH, ChaCha20‑Poly1305, session key rotation)
- Commission a third‑party security audit and publish the results
- Open‑source the relay server (AGPL)
- Blog posts: "Why we built a blind relay," "What Omnara/Warp don't tell you about your agent traffic"
- Enterprise will ask: "Can you see our code?" Answer: No, and here's the proof.

### 5.2 Network Effects

- **Shared relay / team sessions:** When a team uses Conduit, the relay becomes infrastructure. Switching costs go up.
- **Community agent integrations:** Conduit's value increases as it works with more agent frameworks (Claude Code → Codex → OpenCode → Cline → Aider → Gemini CLI)
- **Self‑host community:** Self‑hosted relay operators contribute back to the project, create documentation, answer questions on Discord. This compounds.

### 5.3 Switching Costs

- **Saved relay configurations:** SSH keys, host configs, agent preferences. Moving this data is friction.
- **Team onboarding:** Once a team uses Conduit's team relay, switching means re‑inviting everyone.
- **Notification muscle memory:** Developers learn Conduit's notification patterns. Breaking that habit is hard.

### 5.4 Content Engine

| Content type | Cadence | Goal |
|---|---|---|
| Technical blog posts | Bi‑weekly | SEO, HN front‑page, developer credibility |
| Security audit updates | Quarterly | Enterprise trust, compliance checklist |
| Agent integration announcements | Per new agent support | Reach new communities |
| "State of mobile agent control" report | Annual | Thought leadership, PR, lead gen |
| Changelog (public) | Weekly | Community transparency (Warp/Linear playbook) |

### 5.5 Enterprise / Team Upsell Path

The ideal upsell pattern (proven by Cursor, Linear, Tailscale):
1. Solo developer uses Personal (Cloud Self‑Host) → loves it
2. Developer shows teammate → teammate signs up
3. Both hit Pro limits → team needs shared relay management
4. Org adopts → needs SSO, audit logs, SLA → Teams or Enterprise

### 5.6 The "Open‑Core" Wedge

Self‑hosting is not a revenue loss — it's an enterprise entry point.
- GitLab proved open‑core works: self‑host CE → paid EE.
- Tailscale proved personal free → team paid.
- Conduit should ship the self‑host relay as a single Docker container (`docker run conduit-relay`) with clear docs. It costs near‑nothing to support and eliminates the "what if you shut down?" objection that kills early‑stage dev tools.

---

## 6. Risks & Anti‑Patterns

### 6.1 App Store Rejection Risk (CRITICAL)

**Conduit operates in a gray area:** It relays agent commands from a phone to a remote machine. Apple may classify this as "remote execution" or "code downloading," triggering rejection under Guideline 2.5.2 (self‑contained apps) or 2.1 (app completeness).

**Mitigation:**
- Submit an earlier build for TestFlight review (well before launch)
- Be explicit in App Review notes: "This app relays user‑authored commands between the user's own devices. It does not download executable code from external sources."
- Remove any "agent runs code on cloud" features from the initial submission — keep it pure device‑to‑device relay
- Reference Blink Shell ($19.99/yr, SSH terminal) as a precedent — if they pass, Conduit should pass
- Budget for 1–3 rejection cycles (3–7 days each per [SwapTest analysis](https://swaptest.net/blog/ios-preflight-check-app-store-rejection-guide))

### 6.2 Pricing Mistakes

**Anti‑pattern: Launching with credit‑based usage pricing.**
- Replit's credit system is widely criticized as opaque and anxiety‑inducing.
- Warp's credit‑per‑agent model creates "I don't know what I'll pay" fear.
- **Fix:** Flat $9/mo subscription. Add credits only if/when you introduce cloud agent execution.

**Anti‑pattern: No free tier.**
- Blink's forced trial → subscription model attracts bad reviews ("useless app unless you pay").
- Cursor's free Hobby tier is why it grew to $100M ARR in 12 months.
- **Fix:** Keep a genuinely useful free self‑host tier forever.

**Anti‑pattern: Pricing too low.**
- Conan's $29 one‑time purchase is a hobby project price. It won't sustain real infra.
- **Fix:** $9/mo is the floor. Don't go below it for the paid tier.

### 6.3 No Distribution / Build‑It‑And‑They‑Will‑Come

**The #1 cause of dev‑tool failure** (40–42% of SaaS startups die from no market need, per [Novative 2026 analysis](https://www.novative.dev/blog/saas-launch-playbook)). Omnara had YC distribution; Warp had 6 PH launches; Cursor had a VS Code fork with instant familiarity.

**Conduit action:** Don't ship without a distribution plan. The HN/PH/Reddit launch must be coordinated and rehearsed. Have 50 beta testers ready to upvote and comment on launch day.

### 6.4 Premature Scaling

- Don't hire sales people before product‑market fit.
- Don't build cloud agent execution (Conduit runs agents on your machine) until the core relay is validated.
- Don't support 10 agent frameworks at launch. Ship with Claude Code + Codex. Add OpenCode, Aider, Cline when users ask for them.

### 6.5 Security‑Critical Product + Indie Team Risk

Conduit handles SSH keys, agent traffic, and push notification relay. If the relay is compromised, user trust is destroyed permanently.

- **Must:** Third‑party security audit before any paid tier launches.
- **Must:** Bug bounty program (HackerOne or similar) from month 3.
- **Must:** Publish a security.txt and responsible disclosure policy.
- **Must:** Open‑source the relay server so the community can audit it.

### 6.6 Android / Desktop Neglect

- Developers who love Conduit on iOS will ask for Android. **Say no for the first 12 months.** A single‑platform focus is how Linear succeeded (macOS + web only for 2 years before iOS/Android).
- Conduit's web dashboard is the Android substitute (responsive web works on any device).

---

## 7. 90‑Day Launch Checklist (Prioritized)

### Phase 0: Pre‑Launch (Days −60 to −30)

- [ ] **Submit early TestFlight build** — start the App Review relationship
- [ ] Write the blind‑relay architecture blog post (draft for Day 0)
- [ ] Create 2‑minute demo video (phone receiving push → approving tool call)
- [ ] Build landing page with: privacy hero text, waitlist/TestFlight signup, demo GIF
- [ ] Recruit 20 beta testers from personal network (Discord, Twitter, former colleagues)
- [ ] Open Discord: #general, #beta-feedback, #security, #self-hosting
- [ ] Define Show HN title (test 5 options in beta group)
- [ ] Security audit engagement (get it scheduled; publish results Day 60)

### Phase 1: Community Seed (Days −30 to −7)

- [ ] **Begin Reddit credibility building** (r/iOSProgramming, r/ClaudeAI, r/netsec) — 0 product mentions
- [ ] Start Twitter/X presence: post about the blind relay architecture 2–3×/week
- [ ] Publish 1–2 technical blog posts: (1) "Blind E2EE relay with X25519/ChaCha20", (2) "How we built an iOS agent control plane without a cloud backend"
- [ ] Hacker News meta‑preparation: submit 1–2 non‑Conduit technical posts to build account history
- [ ] Product Hunt account: engage with similar products, follow hunters, build network
- [ ] Finalize pricing page: Personal (Self‑Host) = free, Personal (Cloud) = free (5 sessions), Pro = $9/mo

### Phase 2: Launch Week (Days 1–7)

- [ ] **Day 0 (Tuesday):** Submit Show HN. Post first comment immediately. Stay in thread for 4+ hours.
- [ ] **Day 0:** Cross‑post to r/iOSProgramming, r/ClaudeAI with honest "we're the ones who built this" framing
- [ ] **Day 1 (Wednesday):** Launch on Product Hunt. 7 AM PT. Activate beta testers for first‑hour upvotes.
- [ ] **Day 1:** Twitter/X thread from founder account. Pin the demo video.
- [ ] **Day 1:** Discord goes live with all beta testers in #general
- [ ] **Day 2:** Follow‑up blog: "What we learned from launching Conduit" (ride the wave)
- [ ] **Days 3–7:** Answer every HN/PH/Reddit comment. Fix bugs. Ship 1–2 small improvements.

### Phase 3: Post‑Launch Sustain (Days 8–30)

- [ ] Market the security audit results (blog + HN submission)
- [ ] Publish the self‑host relay Docker image + setup guide
- [ ] Release first agent integration beyond Claude Code (Codex or OpenCode)
- [ ] Feature requests triage → build the #1 requested feature
- [ ] Email every beta tester individually: "What do you need to pay for Conduit?"
- [ ] Set up Stripe billing for Personal → Pro upgrade

### Phase 4: Monetization & Growth (Days 31–90)

- [ ] **Open paid Pro tier.** Announce with a blog + Twitter + Reddit post.
- [ ] First month pricing analysis: conversion rate, churn, feedback
- [ ] Apply for Apple's "App of the Day" / "Developer Tool" feature (requires 4.5+ rating)
- [ ] Survey users: "What would make you switch from [competitor]?" → feed into roadmap
- [ ] Begin Teams tier planning (SSO, shared relay management)
- [ ] Content cadence established: 2 blog posts/month, weekly changelog, bi‑weekly Discord AMAs
- [ ] **Month 3 milestone:** 500 active users, $2K MRR, <5% monthly churn — or iterate on pricing/messaging

### Ongoing (Beyond 90 Days)

- [ ] Android app (only when iOS retention > 80% at month 6)
- [ ] Teams tier launch
- [ ] Enterprise sales (inbound only; no outbound team)
- [ ] Annual "State of Agent Security" report
- [ ] Reliable 9‑figure net retention through team expansion
- [ ] Self‑host relay community contributions (GitHub stars, community‑built integrations)

---

## 8. Sources & References

### Competitor Data
- Omnara: [HN Show](https://news.ycombinator.com/item?id=44878650), [HN Launch](https://news.ycombinator.com/item?id=46991591), [omnara.com](https://omnara.com/), [YC Launch](https://www.ycombinator.com/launches/PFp-omnara-run-claude-code-from-anywhere), [Fondo analysis](https://fondo.com/blog/omnaras25-launches)
- Cursor: [ZBuild review 2026](https://www.zbuild.io/resources/news/cursor-review-2026), [usama.codes ARR history](https://usama.codes/blog/cursor-ai-visual-editor-billion-dollar-ide-2025), [NextBigFuture $100M ARR](https://www.nextbigfuture.com/2025/02/cursor-grew-to-100m-in-annual-recurring-revenue-in-12-months.html), [Forum on pricing](https://www.chargebee.com/pricing-repository/cursor)
- Warp: [warp.dev/pricing](https://www.warp.dev/pricing), [Product Hunt launches](https://www.producthunt.com/products/warp), [PH discussion (15× revenue growth)](https://www.producthunt.com/p/warp/one-month-since-product-hunt-launch-warp-sees-2-million-agents-daily-and-15x-revenue-growth)
- Replit: [FlexPrice guide](https://flexprice.io/blog/replit-ai-pricing-guide), [Superblocks breakdown](https://www.superblocks.com/blog/replit-pricing), [StartupHub.ai $100M ARR](https://www.startuphub.ai/ai-news/startup-news/2025/replit-hits-100m-arr-and-introduces-effort-based-pricing-model)
- Tailscale: [Pricing page](https://tailscale.com/pricing), [2021 pricing changes](https://tailscale.com/blog/2021-06-new-pricing), [Open‑source GitHub orgs](https://tailscale.com/blog/community-github-pricing), [TechCrunch $100M raise](https://techcrunch.com/2022/05/04/tailscale-lands-100-million-to-transform-enterprise-vpns-with-mesh-technology)
- Linear: [Aakash Gupta deep dive](https://www.news.aakashg.com/p/how-linear-grows), [Product Hunt](https://www.producthunt.com/products/linear), [Linear Agent launch](https://linear.app/changelog/2026-03-24-introducing-linear-agent)
- Conan: [Product Hunt](https://www.producthunt.com/products/conan), [conan.sh](https://www.conan.sh/), [ChatGate review](https://chatgate.ai/post/conan)
- Blink Shell: [blink.sh](https://blink.sh/), [App Store](https://apps.apple.com/us/app/blink-shell-build-code/id1594898306), [GitHub](https://github.com/blinksh/blink)

### Launch & Pricing Strategy
- [Novative SaaS Launch Playbook 2026](https://www.novative.dev/blog/saas-launch-playbook)
- [GTM Technical Product Pricing (MCP skill)](https://mcpservers.org/agent-skills/github/gtm-technical-product-pricing) — freemium threshold design, usage‑based vs seat‑based
- [Maxio 2025 SaaS Pricing Trends](https://www.maxio.com/resources/2025-saas-pricing-trends-report) — hybrid models highest growth at 21%
- [ProductLed Benchmarks 2025](https://productled.com/blog/product-led-growth-benchmarks) — 36% Cursor conversion, 9% median PLG free‑to‑paid
- [2026 PLG Benchmarks (conversion, activation, NRR)](https://growthengineer.ai/blog/plg-benchmarks-2026)
- [SaaS Activation Rate Benchmarks 2026](https://productquant.dev/blog/saas-activation-rate-benchmarks-2026)
- [Developer GTM metrics guide (StateShift)](https://blog.stateshift.com/how-to-measure-go-to-market-success-for-developer-audiences)
- [Freemium vs Trial conversion (Dodopayments)](https://dodopayments.com/blogs/saas-free-trial-vs-freemium)
- [SaaS Pricing Lessons from Failed Launches](https://clackyai.com/blog/saas-pricing-lessons-from-failed-launches)

### Product Hunt & HN Playbooks
- [Product Hunt Launch Guide 2025 (MarketingIdeas)](https://www.marketingideas.com/p/how-to-successfully-launch-on-product)
- [29 strategies for 20K+ PH signups](https://founderpath.com/blog/launch-on-product-hunt)
- [HN Launch Strategy: 0 to front page](https://thegrowthterminal.com/blog/hacker-news-launch-strategy-from-0-to-front-page)
- [Show HN 2025 statistics](https://news.lavx.hu/article/show-hn-2025-the-numbers-behind-hacker-news-launchpad)
- [HN Launch Playbook (data‑driven guide, 2025)](https://ilin.pt/marketing/strategy/community/2025/07/08/show-hn-guide.html)
- [Developer tools Show HN tactics (daily.dev)](https://business.daily.dev/resources/hacker-news-marketing-developer-tools-show-hn-launch-day-sustained-coverage)

### Reddit Strategy
- [30‑day Reddit launch playbook for SaaS (RedShip)](https://redship.io/blog/how-to-launch-saas-on-reddit)
- [How to launch SaaS on Reddit (RedditSchedule)](https://redditschedule.com/how-to-launch-a-saas-on-reddit-and-get-your-first-paying-customers/)
- [Top subreddits for SaaS founders 2025](https://redditagency.com/subreddits/saas-founders)

### App Store Risk
- [How to get App Store approval in 2026 (Appbot)](https://appbot.co/blog/app-store-app-review-approval-vibe-coded-delays-2026)
- [iOS PreFlight check — avoidance guide (SwapTest)](https://swaptest.net/blog/ios-preflight-check-app-store-rejection-guide)
- [App Store rejection guide 2026 (RevenueCat)](https://www.revenuecat.com/blog/growth/the-ultimate-guide-to-app-store-rejections)
- [Guideline 2.5.2 dynamic code resolution (PTKD)](https://ptkd.com/journal/rejection-guideline-2-5-2-dynamic-code)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

### General SaaS/Dev‑Tool Failure Patterns
- [40–42% of SaaS fails from no market need (CBInsights, via Novative)](https://www.novative.dev/blog/saas-launch-playbook)
- [7 mistakes developers make building SaaS (DEV)](https://dev.to/shayy/7-mistakes-every-developer-makes-when-building-their-first-saas-and-how-i-fixed-them-4mi3)
- [Anti‑patterns that kill startups (Ginkida)](https://ginkida.dev/en/posts/anti-patterns-that-kill-startups-from-within)
- [Mitigating key SaaS errors (CloudEster)](https://cloudester.com/saas-startup-errors-and-fixes/)
