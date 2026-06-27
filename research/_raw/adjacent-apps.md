# Adjacent & companion apps for Lancer — market research

Researcher: Claude (market-research pass). Date of research: **2026-06-23**.
Scope: products adjacent to Lancer (iOS mission-control for AI coding agents on the developer's own machines).

> **Evidence labels** used throughout: **Strong** (primary source, direct quote/listing), **Moderate** (reputable secondary/independent), **Weak** (single low-authority source), **Inference** (my reasoning, not stated), **Unknown** (not found). Promo/marketing copy is flagged inline. No quotes/numbers were invented; where a page was access-walled it is recorded in §6.

---

## 1. Source ledger

| URL | Type | Date accessed | Access status | What it backs |
|---|---|---|---|---|
| https://www.blume.codes/ | Vendor homepage | 2026-06-23 | OK | Blume positioning, taglines, feature list |
| https://www.blume.codes/about | Vendor about page | 2026-06-23 | OK | Blume founders (Peder Aaby, Olav Ljosland), mission |
| https://www.blume.codes/blog | Vendor blog index | 2026-06-23 | OK (index only) | Blume blog post titles/dates; thesis on agent memory/context |
| https://www.blume.codes/blog/blume-codes-vision (+ /vision, /claude-code-has-a-memory-now) | Vendor blog posts | 2026-06-23 | **404 on individual posts via fetch** | Could not retrieve full vision text; titles only |
| https://x.com/BlumeDotCodes | Vendor X account | 2026-06-23 | **402 Payment Required (walled)** | Account exists; posts not retrievable |
| https://www.blume.codes/docs | Vendor docs | 2026-06-23 | OK (landing only) | One setup guide ("Make Claude usage work on Mac"); deeper docs not surfaced |
| https://locallyai.app | Vendor homepage | 2026-06-23 | OK | Locally AI positioning, models, privacy copy, socials |
| https://apps.apple.com/us/app/locally-ai-by-lm-studio/id6741426692 | App Store listing | 2026-06-23 | OK | Rating 4.7/5 (1.2K), free, dev "Element Labs Inc", reviews |
| https://lmstudio.ai/blog/locally-ai-joins-lm-studio | Vendor blog | 2026-06-23 | OK (via search snippet) | LM Studio acquired Locally AI (~2026-04-08); creator Adrien Grondin |
| https://lmstudio.ai/blog/locally-lm-link | Vendor blog | 2026-06-23 | OK | LM Link = E2E-encrypted phone↔desktop relay (architecturally parallel to Lancer relay) |
| https://9to5mac.com/2026/06/04/lm-studio-now-lets-you-use-your-iphone-to-talk-to-local-models-on-your-mac/ | Independent press | 2026-06-23 | OK (via search) | Confirms LM Link launch 2026-06-04 |
| https://github.com/stablyai/orca | OSS repo (README) | 2026-06-23 | OK | Orca ADE, ~6.3k stars, MIT, mobile companion, multi-agent |
| https://www.onorca.dev/ | Vendor homepage | 2026-06-23 | OK (via search) | Orca product positioning |
| https://www.clauderc.com/ | Vendor homepage | 2026-06-23 | OK | Tactic Remote (ex-"Claude Remote"); approvals, tmux, Cloudflare Tunnel |
| https://nimbalyst.com/blog/best-mobile-apps-for-claude-code-2026/ | Vendor blog (Nimbalyst) | 2026-06-23 | OK | Comparative review of mobile Claude Code apps (vendor-authored — bias flag) |
| https://www.explainx.ai/blog/claude-code-mobile-remote-control-phone-guide-2026 | Independent blog | 2026-06-23 | OK | Methods to control Claude Code from phone; daemon/security notes |
| https://code.claude.com/docs/en/remote-control | Vendor docs (Anthropic) | 2026-06-23 | OK (via search) | Official Remote Control feature (shipped 2026-02-25) |
| https://github.com/BloopAI/vibe-kanban | OSS repo | 2026-06-23 | OK (via search) | Vibe Kanban; Bloop shut down 2026-04-10, now Apache-2.0 community |
| https://www.conductor.build/ | Vendor homepage | 2026-06-23 | OK (via search) | Conductor (Melty Labs, YC S24); Mac parallel-agent orchestrator |
| https://venturebeat.com/orchestration/anthropic-just-released-a-mobile-version-of-claude-code-called-remote | Independent press | 2026-06-23 | OK (via search) | Anthropic Remote Control release |

---

## 2. User-feedback rows

Real end-user statements are scarce for the newest products (Blume, Tactic Remote) — most public text is vendor marketing. App Store reviews exist for Locally AI. Recorded honestly; absence of feedback is itself a finding (see §6).

| Product | Source | Date | URL | User statement (paraphrased unless quoted) | Sentiment | Category | Severity | Engagement | Evidence strength | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Locally AI | App Store reviews | 2026-06-23 | apps.apple.com/...id6741426692 | "does not collect any of my data"; tested multiple models on iPad Pro | Positive | Privacy | — | App rated 4.7/5, 1.2K ratings | Strong | Quoted phrase from review excerpt |
| Locally AI | App Store reviews | 2026-06-23 | (same) | Shortcuts integration "amazing"; "checks nearly all of the boxes" | Positive | UX/automation | — | (same listing) | Strong | |
| Locally AI | App Store reviews | 2026-06-23 | (same) | "best local AI generative app on MacOS/iOS, and it's free" | Positive | Value | — | | Strong | |
| Locally AI | App Store reviews | 2026-06-23 | (same) | Requests DeepSeek V3, GPT-OSS, Llama 4 lightweight — "the only thing missing" | Mixed | Model availability | Low | | Strong | Model-catalog gap is the recurring ask |
| Locally AI | App Store reviews | 2026-06-23 | (same) | Reports "unexpected crashes", asks for bug fixes | Negative | Stability | Medium | | Moderate | Single review; severity capped |
| Locally AI | App Store reviews | 2026-06-23 | (same) | Wants file attachment (PDF/Word), search & deep-research | Mixed | Feature gap | Low | | Strong | Mobile-AI feature-completeness expectation |
| Blume | — | — | — | No public end-user reviews/discussion found | — | — | — | — | Unknown | New product; no HN/Reddit thread surfaced (§6) |
| Tactic Remote | — | — | — | No independent user reviews found | — | — | — | — | Unknown | Vendor copy only |
| Orca | GitHub | 2026-06-23 | github.com/stablyai/orca | ~6.3k stars (proxy for adoption/interest) | Positive (signal) | Adoption | — | 6.3k★ | Strong | Stars ≠ active users (Inference: meaningful traction) |

---

## 3. Blume

**What it is (Strong, vendor homepage + about, 2026-06-23):** A **desktop, local-first "sidecar"** that watches multiple coding agents (Claude Code, Cursor, Codex, omp, Pi) and manages the *hidden config that shapes them* — `AGENTS.md`, `CLAUDE.md`, rules, skills, hooks. It is **not** a phone app and **not** a remote-control tool.

**Taglines (Strong, marketing copy):** "Watch every coding agent, effortlessly" / "Give every coding agent the same context."

**Founders (Strong, /about):** Peder Aaby (Oslo; AWS solutions architect, appsec) and Olav Ljosland (Toronto; previously helped build **Wordware, YC S24**). Met at NTNU Trondheim. No funding disclosed. Contact `hello@blume.codes`. X: `@BlumeDotCodes` (account exists; **content walled — §6**).

**Feature set (Strong, homepage):**
- **Agent Overview** — real-time status: working / finished / needs approval.
- **Hidden files & rules tracking** — surfaces `AGENTS.md`, rules, skills, hooks.
- **Multi-agent** — Cursor, Codex, Claude Code, omp, Pi.
- **Local & private** — on-device; preview changes before approval.
- **Usage dashboard** — token consumption across providers before limits hit.
- **Automatic improvement suggestions** — proposes fixes to rules/skills; preview/approve/dismiss.
- **Intent–agent mismatch detection** — flags when agent setup diverges from chat instructions; "proposes the fix; you approve."
- *Coming soon:* auto-fixes, setup-performance analytics, a **local domain model for project-wide intent consistency**, team-wide conflict resolution, intent harvesting from Slack/transcripts/reviews, auto-improve mode with automated testing.

**Blog thesis (Moderate — index titles + snippets only; full posts 404'd, §6):** Blume frames the problem as *the workflow around agents not keeping pace with the agents themselves*. Notable post titles (all 2026-06-16/17/23): "Blume.codes vision" ("Your coding agent got dramatically smarter this year. The workflow around it didn't."), "Claude Code Has a Memory Now. That's the Good News and the Bad News.", "CLAUDE.md vs AGENTS.md: you're going to maintain both", "What the top 10 AGENTS.md files have in common", and a scoring tool for `CLAUDE.md`/`AGENTS.md` quality. This is a **deliberate content-marketing bet that context/instruction management is a real, growing pain** — they're seeding the category.

### Classification: **Adjacent, with integration potential — NOT a direct competitor.**

- **Different surface:** Blume is a *desktop sidecar that edits/curates config*; Lancer is a *phone that steers and approves remote runs*. Zero overlap on form factor or core job.
- **Shared philosophy:** local-first/privacy, multi-vendor agents, approval-gated changes ("you approve"), surfacing live agent status. The *governed-approval* and *multi-vendor dispatch* DNA is common ground.
- **Overlap risk (Inference, Moderate):** Both want to own "agent status + approvals." If Blume adds remote/mobile, or Lancer adds config management, they collide. Today they don't.

### Strategic question for Lancer: should we add context-management?

- **Is it a real problem?** Evidence that *vendors* believe so is **Strong** (Blume's whole thesis; Anthropic shipped CLAUDE.md memory; the genre of "best AGENTS.md" content is large). Evidence that *end users actively demand a separate tool* is **Weak/Unknown** — no user complaints or threads were found validating willingness to pay for a dedicated context manager. The owner's own repo (heavy `CLAUDE.md`/`AGENTS.md`/skills/rules discipline) is anecdotal corroboration that the pain is real for power users (Inference).
- **Recommendation:** **Do not build context-management into V1.** It is a different product with a different primary surface (desktop file curation), unproven standalone demand, and would dilute Lancer's wedge (remote steer + governed approvals + E2E relay + push). Treat Blume as a **potential integration/partner**, not a feature to absorb. A *thin, read-only* "config drift / rules health" signal on the phone (you already have a drift-detector in flight per memory) is the most Lancer should consider — and even that should ship after the live loop.

---

## 4. Locally AI

**What it is (Strong, homepage + App Store):** An iOS/iPadOS/Mac app to **run open-source LLMs fully on-device** via Apple's MLX. "Run AI models locally on your iPhone, iPad, and Mac." Free. Developer now **Element Labs Inc**; **acquired by LM Studio ~2026-04-08** (creator **Adrien Grondin** joined LM Studio). App Store: **4.7/5, ~1.2K ratings**.

**Models (Strong):** Llama 3.1/3.2, Gemma 2/3/3n, Qwen 2/2.5/3, DeepSeek R1, SmolLM, IBM Granite, Deep Cogito, Liquid LFM. Claims on-device perf "rivals GPT-4o-mini."

**Positioning/privacy (Strong, marketing):** "runs completely offline… No internet connection or login required"; "Your data never leaves your control." Voice mode, "Hey, Locally AI" Siri, Control Center/Lock Screen, Shortcuts, vision models.

**LM Link (Strong, lmstudio.ai blog, launched 2026-06-04) — the load-bearing lesson:** Post-acquisition, LM Studio shipped **LM Link**: the **phone runs as a client to your desktop LM Studio instance**, so you "use your largest models running in LM Studio, directly from your phone." **All device-to-device data is end-to-end encrypted; chats saved locally.** Pairing: install desktop LM Studio → enable LM Link → install Locally on iPhone → follow in-app instructions to "add your iPhone to your Link." Free during preview; paid plans later. **This is architecturally the same shape as Lancer's E2E relay** (phone steers, compute stays on the trusted machine, E2E crypto, pairing flow) — applied to chat instead of coding agents.

### Classification: **Adjacent / inspiration — NOT a competitor.**

### Lessons for Lancer
- **Local-first + E2E pairing is a proven, well-received message** (4.7★, privacy praised in reviews). Lancer's "phone steers, code/keys stay on your machine, E2E relay, TOFU host keys" should be marketed just as boldly — it's the same trust story buyers already reward.
- **LM Link validates Lancer's relay architecture** from a credible vendor: heavy compute stays on the desktop, the phone is a thin authenticated client over an E2E channel. Reuse this as external proof the model is sound and shippable.
- **Onboarding a technically complex product:** Locally hides MLX/model-management behind a clean catalog + Shortcuts/Siri. Lesson: Lancer should hide daemon/relay/pairing complexity behind an equally clean pairing flow (QR pairing already exists per repo).
- **Complaint patterns to pre-empt:** (1) model-catalog gaps → for Lancer, *vendor-adapter* gaps (Claude/Codex/OpenCode/Kimi must all "just work"); (2) stability/crashes; (3) feature-completeness expectations (file attach, search). Mobile-AI users expect polish fast.
- **Monetization signal:** free app + later paid plans on the *remote-link* feature (LM Link). Implies the **remote-control/relay layer is the monetizable surface** — directly relevant to where Lancer can charge.

### Could any Lancer function run locally on the phone?
Mostly **no** — Lancer's value is steering agents on *remote, more powerful, trusted machines*; running coding agents on-device defeats the premise. **Inference:** the only plausibly-local pieces are non-agent niceties (approval policy evaluation, summarization of diffs/output, a tiny on-device model for "explain this approval"). Per memory, "approval-aware summaries" are already a designed differentiator — an on-device small model could power that privately, echoing Locally's on-device-summary UX. Low priority vs the live loop.

---

## 5. Other companion apps

| Product | What it is (1-line) | Classification | Key lesson / threat (evidence) |
|---|---|---|---|
| **Anthropic Remote Control** (official) | Toggle in Claude Code → continue a local session from the Claude app/`claude.ai/code`; compute stays local (shipped 2026-02-25). | **Direct competitor (biggest threat)** | First-party, zero-setup, "no ports/servers." **Threat:** owns the default path for Claude-only users. **Gap to exploit:** Claude-only (no Codex/OpenCode/Kimi), terminal-centric, no governed multi-vendor approvals — Lancer's multi-vendor + approval governance is the differentiator (Strong, Anthropic docs + VentureBeat). |
| **Orca** (stablyai, MIT, ~6.3k★) | Open-source ADE: run a *fleet* of parallel agents in isolated git worktrees, desktop **+ iOS/Android companion** to monitor/steer; 25+ agents. | **Direct competitor (closest in spirit)** | Strongest OSS traction in the space; mobile "monitor & steer + completion notifications + follow-ups." **Threat:** open-source + multi-agent + mobile = Lancer's exact pitch, free. **Lesson:** worktree-per-task fan-out and "fan one prompt across 5 agents, merge the winner" is a compelling UX Lancer lacks. Architecture (daemon/relay/E2E) undocumented — possible security-posture gap to out-position (Strong, README; Moderate on mobile internals). |
| **Tactic Remote** (clauderc.com; ex-"Claude Remote", renamed 2026-03) | iPhone/iPad control layer for Claude Code + Codex: live terminal stream, tmux persistence, file browsing, **approval workflows**, plan review, prompt queue, push notifications. | **Direct competitor** | Closest feature-for-feature to Lancer's "steer + approve" loop, incl. **approval notifications** and **local-first (Cloudflare Tunnel TLS, API-key auth, path sandbox)**. **Threat:** already ships the governed-approval flow Lancer is racing to prove. **Gap:** Cloudflare-Tunnel/API-key vs Lancer's E2E relay + TOFU + Keychain/biometric = stronger security story to claim (Strong, vendor copy; no independent reviews — §6). |
| **Nimbalyst** (nimbalyst.com) | AI-native desktop workspace (kanban for parallel Claude Code/Codex, visual editors) **+ iOS companion** with visual diff review, push notifications, "team visibility." | **Adjacent → competitor on mobile** | iOS app requires Nimbalyst desktop host (daemon parallel to Lancer's). **Lesson:** mobile **visual diff review** + **team visibility** are features Lancer should consider. NB: its blog is a comparison-marketing engine — **bias flag** when citing its app rankings (Moderate). |
| **Happy** | Native iOS app: monitor Claude Code sessions, push notifications, status indicators. | **Adjacent (read-mostly)** | "Read-mostly, limited interaction." **Lesson:** notifications-only is the low-end; Lancer's *governed write-path (approve/steer)* is the up-market wedge (Moderate, Nimbalyst review — bias flag). |
| **Conductor** (conductor.build, Melty Labs, YC S24) | macOS app: run parallel Claude Code/Codex/Cursor agents, each in its own worktree; diff-first review/merge. **Desktop only.** | **Adjacent (desktop sibling)** | No mobile = not a phone competitor, but defines the "parallel-agents + diff review" UX bar. **Lesson:** diff-first review ("review time scales with change size, not codebase size") is a UX principle worth porting to Lancer's approval screens (Moderate). |
| **Vibe Kanban** (BloopAI) | Kanban for orchestrating multiple coding agents. **Bloop shut down 2026-04-10** ("no viable business model"); now Apache-2.0, community-maintained, fully local. | **Adjacent (cautionary tale)** | **Threat/lesson:** a well-known multi-agent orchestrator **failed to monetize** and shut down — a warning that "agent orchestration UI" alone may not be a business. Lancer's monetizable wedge (relay/approvals/security, à la LM Link's paid remote layer) matters (Moderate, Nimbalyst + search). |
| **clauder** (ZohaibAhmed, GitHub) | "Control Claude Code remotely from your iPhone." | **Adjacent (small OSS)** | Single-dev project; low footprint. **Lesson:** the "control Claude Code from iPhone" niche is crowded with small OSS — Lancer must differentiate on governance/security/multi-vendor, not on existence (Weak). |
| **Tailscale+mosh+Termux / tmux-over-SSH** | DIY: encrypted mesh / SSH session persistence for raw terminal mobile access. | **Substitute (DIY competitor)** | The "free, technical" alternative the target user already knows. **Threat:** power users may stay DIY. **Counter:** Lancer's value = governed approvals + push + clean UX over raw terminal (Strong, explainx.ai). |

---

## 6. Coverage limitations

- **Blume X account (`x.com/BlumeDotCodes`) is paywalled** — returned **HTTP 402** to fetch. Could not read posts/replies/follower count or founder commentary. Account confirmed to exist (search snippet + /about link).
- **Blume individual blog posts 404'd** via direct fetch (slugs guessed; only the `/blog` index rendered). Thesis captured from index summaries + search snippets, not full text — graded **Moderate**, not Strong.
- **No public end-user feedback found for Blume or Tactic Remote** — no HN "Show HN", Reddit, or independent review threads surfaced (searched HN/Reddit/Show HN). These are **new products**; absence of community footprint is recorded as a finding, not padded. Treat their feature claims as **vendor-stated** until users corroborate.
- **Locally AI Reddit search returned no usable links** (one query returned empty). App Store reviews were available and used instead.
- **Orca / Tactic Remote mobile internals** (exact daemon/relay/E2E mechanics) **not documented** in fetched pages — comparisons to Lancer's relay are partly **Inference**.
- **Nimbalyst's comparative blog is vendor-authored** (it ranks itself favorably) — **bias-flagged** wherever cited.
- No paywalled financials/funding found for any vendor (Blume funding undisclosed).

---

## 7. Verdict for Lancer

**Is Blume solving a more valuable adjacent problem?** No — **different, not bigger.** Blume's bet (curating `CLAUDE.md`/`AGENTS.md`/rules/hooks + intent-mismatch detection) is a *real but unproven-to-monetize* desktop problem with **no surfaced end-user demand signal** and a cautionary neighbor (Vibe Kanban shut down for lack of a business model). Lancer's wedge — **remote steer + governed approvals + E2E relay + push, across multiple vendors** — is validated by *more* converging evidence: Anthropic shipped official Remote Control, Tactic Remote ships the same approval loop commercially, Orca has ~6.3k★ for multi-agent mobile steering, and LM Studio's LM Link (E2E phone↔desktop relay, with a *paid* remote tier planned) independently validates both the architecture and the monetization surface.

**Should Lancer add context-management?** **No, not in V1.** It is a separate product surface (desktop config curation) with weak standalone-demand evidence and high focus cost. Keep Lancer pointed at closing the **live governed-approval loop on a real device** (the #1 V1 gate per the repo). Treat Blume as a **partner/integration**, not a feature to absorb. The only context-adjacent move worth queuing — *after* the live loop — is a thin, read-only **config-drift / rules-health signal** on the phone (you already have a drift-detector in flight), and possibly an **on-device small model for private approval summaries** (mirroring Locally's on-device-summary UX).

**Sharpest competitive truths:**
1. **Anthropic Remote Control is the gravity well** — beat it on *multi-vendor* (Codex/OpenCode/Kimi) and *governed approvals*, not on existence.
2. **Tactic Remote is the closest commercial threat** — out-position on *security posture* (E2E relay + TOFU + Keychain/biometric vs Cloudflare-Tunnel/API-key).
3. **Orca is the closest OSS threat** — its worktree-fan-out UX is a feature gap; its undocumented security model is an opening.
4. **LM Link is your best external proof** that the phone-steers-desktop E2E-relay model is real, polished, and monetizable.
