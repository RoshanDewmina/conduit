# Omnara — Competitor Dossier (PRIMARY direct competitor to Lancer)

> Research date: 2026-06-23. Analyst: market-research pass for Lancer.
> Omnara = "The command center for your coding agents." YC S25. Mobile/web/voice control of
> Claude Code & Codex running on the user's own machine. This is the closest existing product
> to Lancer's thesis ("phone steers and approves agents on your own host").
>
> **Top-line finding:** Omnara has built the *obvious* version of this category and shipped it to
> production with real users — but it is **NOT governed-approval / E2EE / security-first**. It
> stores plaintext conversations on its servers, has no true E2EE, pivoted away from its
> open-source CLI (archived Feb 2026) to a closed-source cloud-SDK product, and its actionable-
> approval loop has documented reliability holes. Lancer's defensible wedge is exactly there.

---

## Source ledger

| URL | type | date accessed | access status | what it backs |
|---|---|---|---|---|
| https://www.omnara.com/ | vendor site | 2026-06-23 | OK (JS-thin; only tagline rendered) | Positioning/tagline |
| https://www.omnara.com/pricing | vendor pricing | 2026-06-23 | PARTIAL (JS-rendered, body not extractable) | Pricing (corroborated elsewhere) |
| https://www.ycombinator.com/companies/omnara | YC profile | 2026-06-23 | OK | Founders, batch, team size, pricing ($20/mo), positioning |
| https://news.ycombinator.com/item?id=46991591 | Launch HN (Feb 2026) | 2026-06-23 | OK | Architecture, E2EE admission, pricing reaction, competitor list |
| https://news.ycombinator.com/item?id=44878650 | Show HN (Aug 2025) | 2026-06-23 | OK | Original pitch, moat objections, privacy concerns, bugs, $9 price |
| https://github.com/omnara-ai/omnara | GitHub repo | 2026-06-23 | OK | 2.6k stars, Apache-2.0, ARCHIVED 2026-02-02, architecture |
| https://github.com/omnara-ai/omnara/releases | GitHub releases | 2026-06-23 | OK | v1.7.0 (2025-11-09) deprecation notice; release history |
| https://github.com/omnara-ai/omnara/issues?q=is%3Aissue | GitHub issues | 2026-06-23 | OK | 40 issues; reliability/auth/approval bug titles |
| https://github.com/omnara-ai/omnara/issues/276 | GitHub issue | 2026-06-23 | OK | Approval popup → "becomes unresponsive" (HIGH severity) |
| https://github.com/omnara-ai/omnara/issues/270 | GitHub issue | 2026-06-23 | OK | Mic/voice discards text on screen lock |
| https://github.com/omnara-ai/omnara/issues/272 | GitHub issue (title) | 2026-06-23 | OK | "Add a 'stop' button" — no stop button existed |
| https://github.com/omnara-ai/omnara/discussions/91 | GitHub discussion | 2026-06-23 | OK | Security Q&A: no E2EE, Supabase, no SOC2/audit, self-host |
| https://apps.apple.com/us/app/omnara-claude-codex-mobile/id6748426727 | App Store | 2026-06-23 | OK (reviews thin) | 4.4★ / 32 ratings, free, v2.0.5 (Apr 7), 4 reviews |
| https://play.google.com/store/apps/details?id=com.omnara.app | Google Play | 2026-06-23 | PARTIAL (review body not extractable directly; one review captured via search) | Android app exists; notification complaint |
| https://www.producthunt.com/products/omnara | Product Hunt | 2026-06-23 | OK | 442 upvotes, "Claude Code in your Pocket", comments (all positive) |
| https://happy.engineering/docs/comparisons/alternatives/ | competitor doc (Happy) | 2026-06-23 | OK | Omnara=$9/mo, plaintext on servers, no E2EE (competitor framing — flag bias) |
| https://docs.omnara.com/quickstart | vendor docs | 2026-06-23 | OK | Install/auth flow, WSL note, desktop+CLI |
| https://omnaradocs.com/ | vendor docs (legacy) | 2026-06-23 | PARTIAL (titles only) | Voice-first positioning, push notifications |
| https://x.com/omnara_ai | X/Twitter | 2026-06-23 | BLOCKED (HTTP 402) | — could not access posts/replies |
| https://www.omnara.com/blog/sandbox-sync | vendor blog | 2026-06-23 | PARTIAL (JS-thin) | Cloud sandbox sync (corroborated via search snippet) |

---

## User-feedback rows

| Product | Source | Date | URL | User statement (quote / faithful summary) | Sentiment | Category | Severity | Engagement | Evidence strength | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Omnara | Launch HN | 2026-02 | news.ycombinator.com/item?id=46991591 | jdmoreira: "If you can see the messages that's a deal breaker for me" | Neg | Security/privacy | High | HN thread | Strong | Direct quote; core E2EE objection |
| Omnara | Launch HN | 2026-02 | …46991591 | isehgal (founder): "We don't have true E2EE yet…we need access for voice agents" | Neutral (admission) | Security | High | founder reply | Strong | **Company admits no E2EE**, architectural, not roadmap-able cheaply |
| Omnara | Launch HN | 2026-02 | …46991591 | sneak: "That means you don't have E2EE, period" | Neg | Security | High | HN | Strong | Independent reinforcement |
| Omnara | Launch HN | 2026-02 | …46991591 | lalo2302: "Feels expensive for something an engineer can hack in a couple hours with tailscale" | Neg | Pricing/moat | Med | HN | Strong | Recurring moat objection |
| Omnara | Launch HN | 2026-02 | …46991591 | quotz: "$20/month seems overly expensive when Happy has E2E encryption" | Neg | Pricing | Med | HN | Strong | Confirms $20 price + Happy as cheaper E2EE rival |
| Omnara | Launch HN | 2026-02 | …46991591 | fluidcruft: switching "to Happy instead" | Neg | Churn/competitor | Med | HN | Moderate | Stated switch |
| Omnara | Launch HN | 2026-02 | …46991591 | jpallen: "Your demo looks like it nails it…excited to try!" | Pos | Praise | Low | HN | Moderate | |
| Omnara | Show HN | 2025-08 | news.ycombinator.com/item?id=44878650 | herval: "what's your moat against Anthropic just launching the same thing a week from now?" | Neg | Moat | High | HN | Strong | Founder conceded Anthropic likely building it |
| Omnara | Show HN | 2025-08 | …44878650 | _1tem: "No way I'm sending my code to your central servers" (advocated P2P/Tailscale) | Neg | Security | High | HN | Strong | Core trust objection |
| Omnara | Show HN | 2025-08 | …44878650 | stpedgwdgfhgdd: worried about someone pressing 'continue' remotely → executing "export database" | Neg | Security/approval | High | HN | Moderate | Approval-safety concern = Lancer's governed-approval thesis |
| Omnara | Show HN | 2025-08 | …44878650 | wilde: "The main omnara command just exits complaining of a missing session id" | Neg | Reliability/onboarding | Med | HN | Strong | First-run break |
| Omnara | Show HN | 2025-08 | …44878650 | macrolime: copy-paste broken on iOS app, "useless" without it | Neg | UX bug | Med | HN | Strong | Founder promised fix |
| Omnara | Show HN | 2025-08 | …44878650 | stavros: "My problem is QAing/reviewing the code…none of these tools solves that" | Neg | Diffs/review gap | Med | HN | Strong | Mobile diff-review remains unsolved across category |
| Omnara | Show HN | 2025-08 | …44878650 | Multiple users: Android "coming soon"; "Google's been giving us a tough time" (Play approval) | Neg | Platform gap | Med | HN | Strong | Android lagged iOS |
| Omnara | GH discussion #91 | 2025 | github.com/omnara-ai/omnara/discussions/91 | Founder: relies on "Supabase managed…encryption at rest and in transit"; **no SOC2/ISO, no pen-test yet**; no data residency for non-US | Neutral (admission) | Security/compliance | High | maintainer reply | Strong | Self-reported compliance gaps |
| Omnara | GH discussion #91 | 2025 | …/discussions/91 | Founder: "We do not store third-party API keys…Users manage those locally." Only Omnara creds server-side. | Neutral | Security | Med | maintainer | Strong | Mitigates key-theft, but conversation plaintext still on server |
| Omnara | GH issue #276 | 2025-10 | github.com/omnara-ai/omnara/issues/276 | "Omnara becomes unresponsive when Claude Code displays any confirmation popup…cannot respond" (CC 2.0.33) | Neg | **Approval loop reliability** | High | open issue, archived unresolved | Strong | The actionable-approval path BROKE on a CC update; no fix documented |
| Omnara | GH issue #270 | 2025-10 | github.com/omnara-ai/omnara/issues/270 | Mic feature "discards text" on iOS, suspected screen-lock kills recording; user reverts to keyboard mic | Neg | Voice reliability | Med | open issue | Strong | Voice = demo-fragile |
| Omnara | GH issue #272 | 2025 | github.com/omnara-ai/omnara/issues/272 | "[FEATURE] Add a 'stop' button" | Neg | Session control gap | Med | open issue | Strong | No way to STOP a run was missing |
| Omnara | GH issues list | 2025 | …/issues | #279 "Can not establish a auth token"; #285 browser auth fails over SSH; #273 connect failure (Retry backoff_max); #283 "No way to interact from the cli after last update" | Neg | Auth/connect reliability | Med-High | multiple issues | Strong | Cluster of connect/auth breakage |
| Omnara | Google Play (via search) | 2026 | play.google.com/…com.omnara.app | "biggest annoyance is it does not raise actual Android notifications when agents need input, so you have to go open the app and check" | Neg | **Notifications not actionable** | High | Play review | Moderate | Notifications informational, not push-actionable on Android |
| Omnara | App Store | 2026-02 | apps.apple.com/…id6748426727 | cms1919 (5★): "Great way to use Claude and Codex while not at my laptop…Better than the alternatives imo" | Pos | Praise | Low | review | Moderate | |
| Omnara | App Store | 2025-08 | …id6748426727 | AceSolver (5★): "crazy how fast the team ships/updates" | Pos | Praise (velocity) | Low | review | Moderate | Possible early-adopter/insider tone — mild promo flag |
| Omnara | Product Hunt | 2025-08 | producthunt.com/products/omnara | Nitesh Padghan: "being stuck at a desk for every little agent ping was killing flow…push approvals on mobile just clicked" | Pos | Praise (core value) | Low | PH comment | Moderate | PH comments uniformly positive — typical launch-day boosterism; **flag as promotional context** |
| Omnara | Product Hunt | 2025-08 | …/omnara | Several "Congrats on the launch" one-liners (Huisong Li, Sanjoy Ahir, etc.) | Pos | Low-info praise | Low | PH | Weak | Deduped; promotional noise, low signal |

---

## Findings

### Positioning
Omnara markets itself as **"The command center for your coding agents"** (note: near-identical
framing to Lancer's "mission control"). Pitch: run Claude Code / Codex on *your own* machine and
"monitor, steer, and approve live AI coding sessions in real time from anywhere" — phone, web,
voice, even Apple Watch. The founders' emotional hook (Strong, Show HN 2025-08): agents stall
"whenever they needed follow-up input" while you're away from the desk — *exactly* Lancer's
problem statement. They've reframed the product over time from "Claude Code in your pocket"
(2025) to a **"voice-first conversational engineering agent"** built on the Claude Agent SDK (2026).

### Strengths (evidence-labeled)
- **Real shipping product with traction** (Strong): 2.6k GitHub stars, 442 PH upvotes, App Store
  4.4★/32 ratings, native iOS + Android + web + desktop + Apple Watch. YC S25, 4-person team, SF.
- **No-SSH/no-tunnel connection model** (Strong): headless daemon holds an outbound authenticated
  WebSocket to Omnara's servers — genuinely zero-config networking vs. Tailscale/ngrok. This is
  their best differentiator vs. roll-your-own.
- **Cloud sandbox continuity** (Moderate): when the local machine goes offline, the session
  resumes in a hosted sandbox, syncing code via git commits per turn. This is a real capability
  Lancer does *not* claim (Lancer's daemon is resident-only).
- **Multi-vendor + multi-agent orchestration** (Moderate): Claude Code, Codex, plus n8n / GitHub
  Actions / custom agents via Python SDK + REST; "Orchestrator Mode" spawns parallel sub-agents.
- **Voice** (Moderate, but see weakness): two-way voice "coding mode" is a headline feature.
- **Ship velocity** (Strong): release cadence was very high through late 2025.

### Weaknesses (the openings for Lancer)
1. **No true E2EE; plaintext on their servers** (Strong). Founder admission: "We don't have true
   E2EE yet…we need access for voice agents." Conversations, git diffs stored in their DB
   (Supabase, encrypted in transit/at rest = *server can read it*). Competitor Happy and HN
   commenters hammer this. This is **architecturally hard for Omnara to fix** because their voice
   agent and cloud sandbox *require* server-side plaintext access. Lancer's E2EE relay is a direct
   structural advantage.
2. **No governed-approval rigor** (Strong inference). There is no hook→policy→audit pipeline; the
   approval is "tap continue." HN user raised the "press continue → `export database`" danger;
   issue #276 shows the **approval surface literally broke** ("becomes unresponsive when Claude
   Code displays any confirmation popup") on a Claude Code update — and there was **no 'stop'
   button** (#272). Their approval loop is informational/fragile, not policy-gated/auditable.
3. **Brittle CLI-wrapper foundation → forced pivot** (Strong). The original open-source Omnara
   parsed `~/.claude/projects` session files + terminal output. They **archived the repo
   2026-02-02** and deprecated the PyPI package, explicitly because wrapping the Claude Code CLI
   "became unfeasible to maintain with Claude Code's constant updates." They rebuilt on the Claude
   Agent SDK as a **closed-source** product. Implication: (a) the open-source/self-host story is
   now legacy/sunset (legacy dashboard at claude.omnara.com sunset end-2025); (b) they're now
   coupled to Anthropic's SDK and roadmap.
4. **Notifications not reliably actionable** (Moderate). Play review: Android doesn't raise real
   OS notifications when the agent needs input — "you have to open the app and check." That's the
   *opposite* of Lancer's APNs-push-while-closed governed approval (Lancer's verified C2 gate).
5. **Auth/connect reliability cluster** (Strong): issues #273/#279/#283/#285 — connection
   failures, auth-token failures, SSH-server auth break, "no way to interact from CLI after last
   update." First-run breakage also reported on Show HN (#"missing session id").
6. **Voice is demo-fragile** (Moderate): #270 — mic discards text on screen lock; user fell back
   to the keyboard mic. The headline feature isn't robust in real mobile conditions.
7. **No compliance posture** (Strong, self-admitted): no SOC 2 / ISO, no pen-test/audit, no
   non-US data residency. Enterprise blocker.

### Repeated user requests
- True E2EE / "don't send my code to your servers" / self-host parity (multiple, Strong).
- A **stop** button / real session control (#272, Strong).
- Android feature + notification parity with iOS (Strong).
- Mobile **code review / QA** that actually works (stavros, Strong) — unsolved category-wide.
- Copy-paste, @file referencing, token-usage display (Show HN, Moderate).

### Misunderstood / overclaimed features
- "Run from anywhere securely, no SSH/port-forward/tunnel" is true for *connectivity* but is often
  read by users as a *security* claim — it is not; data still flows in plaintext to Omnara's cloud.
- "Cloud sandbox continuation" sounds like local execution but actually means **your code is
  pushed to Omnara's cloud** (git-commit sync) to run there when offline — a meaningful trust/data
  expansion many users may not register (Inference, from sandbox-sync description).

### Unvalidated company claims
- "Reliability and latency advantages over Happy," worktrees, richer git, preview URLs (cmsparks,
  HN) — vendor-side claim, **Unverified**.
- Apple Watch support — listed, not independently tested here (**Unknown** depth).
- Voice "perfect for coding while commuting" — contradicted by the real-world mic bug (#270).

### Momentum signal
**Moderate-to-strong but inflected.** Strong 2025 launch momentum (stars, PH, fast shipping, well-
received Launch HN). BUT the Feb-2026 archival of the OSS repo + closed-source pivot + price hike
($9→$20) suggests a strategic reset and a move up-market / toward monetization. Only 32 App Store
ratings = modest paid install base. 4-person team, ~$500K raised (Tracxn, Weak/secondary source).

### Pricing reaction
Free tier = 10 sessions/month. Paid went from **$9/mo (Aug 2025) → $20/mo (Feb 2026)** (YC profile
+ HN both confirm $20 current; happy.engineering's "$9" is stale). The doubling drew explicit
"too expensive vs. free E2EE alternatives (Happy)" pushback on Launch HN. Enterprise = custom.

### Threat level to Lancer: **HIGH on category, MODERATE on Lancer's specific wedge.**
Omnara has already occupied the headline real estate ("command center for coding agents," mobile
control of Claude Code/Codex on your own machine) with a polished, multi-platform, shipping
product and YC backing. If Lancer competes on *generic* "control your agent from your phone,"
Omnara wins on maturity and breadth today. **But** Omnara has deliberately traded away the things
Lancer is built on: end-to-end encryption, fail-closed governed approvals with policy+audit,
no-cloud-data-egress, and rock-solid actionable push. Those are not roadmap items for Omnara —
they're in tension with its voice + cloud-sandbox architecture. That is Lancer's defensible lane.

---

## Lancer-vs-Omnara head-to-head

| Category | Omnara | Lancer | Who wins & why |
|---|---|---|---|
| Core problem | Keep agents moving when you're away from the desk; control Claude Code/Codex from phone/web/voice (Strong) | Same problem, framed as governed "mission control": steer + **approve** agents on your own host (context) | **Tie / slight Omnara today** — same thesis; Omnara is further along in market, Lancer is more sharply scoped to governance |
| Target user | Solo devs / vibe-coders + "leaders" wanting agents on the go; voice-commute crowd (Strong) | Devs who run agents on their own machines/servers and need control + auditable safety (context) | **Lancer** for security-conscious/pro/team buyers; **Omnara** for the broad prosumer wave |
| Mobile experience (control vs chat vs terminal) | Chat-style dashboard + voice + live diffs + 1-tap approve; iOS/Android/web/Watch/desktop (Strong) | Sidebar/Command-Home shell, durable chat threads, **block terminal** (unified-PTY → BlockRenderer) (context) | **Omnara** on breadth/maturity; **Lancer** if its block terminal gives truer fidelity than Omnara's parsed-output chat |
| Agent/provider support | Claude Code, Codex, n8n, GitHub Actions, custom via SDK/REST (Strong) | Claude Code, Codex, OpenCode, Kimi — multi-vendor dispatch w/ continue/follow-up (context) | **Tie** — both multi-vendor; Lancer adds OpenCode/Kimi, Omnara adds n8n/Actions automation surface |
| Session control (start/pause/steer/stop/resume) | Start/steer/resume yes; **stop button was missing** (#272); cloud-sandbox resume when offline (Strong/Moderate) | Start, steer, continue/follow-up, resume across transports; phone Emergency Stop in scope (context/memory) | **Lancer** on stop/kill-switch governance; **Omnara** on offline cloud-resume (a capability Lancer lacks) |
| Approvals | "Tap continue" informational approval; **broke on CC popup update** (#276), no policy/audit (Strong) | Governed loop: hook→policy→inbox→approve→audit, fail-closed, hold-on-unreachable (context) | **Lancer, decisively** — Omnara's approval is fragile & ungoverned; Lancer's is the core differentiator |
| Diffs & files | Live diffs in app; @file/copy-paste gaps reported; review/QA "unsolved" (stavros) (Strong/Moderate) | Review diffs + approve next steps (context); depth not independently benchmarked here | **Tie / Unknown** — both weak at true mobile code-review; needs head-to-head test |
| Multi-agent / machine mgmt | Orchestrator Mode (parallel sub-agents), one dashboard; multi-machine via cloud (Moderate) | Multi-vendor dispatch; fleet/host-health concepts in app (context/memory) | **Tie** — Omnara has named orchestration UX; Lancer has fleet/host-health framing; neither clearly proven superior |
| Context continuity | Desktop↔mobile↔web handoff; git-commit-per-turn; cloud sandbox preserves state offline (Strong) | Continue/follow-up per vendor, new runId per turn, session-resume across transports (context/memory) | **Omnara, slightly** — offline cloud-sandbox continuity is a real edge Lancer doesn't match |
| Notifications (actionable vs informational) | Push approvals on iOS praised; **Android raises no OS notification** — must open app (Moderate) | APNs push **while app closed**, governed approve verified live on device (C2 PASSED) (memory) | **Lancer** — verified actionable-while-closed push; Omnara's is inconsistent across platforms |
| Voice (useful vs demo) | Headline two-way voice; but mic **discards text on screen lock** (#270), user reverts to keyboard mic | No voice (not in context) | **Omnara on paper / Tie in practice** — Omnara has the feature but it's demo-fragile; Lancer simply doesn't compete here yet |
| Security (what leaves the machine) | **No E2EE** (admitted); plaintext convos+diffs on Omnara servers; **code pushed to cloud sandbox**; 3rd-party keys stay local; no SOC2/audit (Strong) | E2EE relay; TOFU host-key prompt; keys in Keychain behind BiometricGate; never log secrets; fail-closed (context) | **Lancer, decisively** — Omnara's architecture *requires* server-side plaintext; Lancer's is E2EE/least-egress by design |
| Setup difficulty | `curl … install.sh \| bash` or desktop app; uses existing CC/Codex auth; **WSL-only on Windows**; first-run breakage reported (Strong) | Resident daemon install + E2EE-relay pairing + APNs (context); pairing flow is heavier (memory) | **Omnara** — lighter, no-SSH onboarding; Lancer's daemon+pairing is more involved (a real adoption cost) |
| Reliability on disconnect | Cloud-sandbox failover when host offline (Strong claim); BUT auth/connect bug cluster (#273/#279/#283/#285) & approval freeze (#276) (Strong) | Hooks default to hold-on-unreachable / fail-closed (context); resident-daemon model (no cloud failover) | **Split** — Omnara wins *graceful offline continuation*; Lancer wins *safe-on-disconnect* (won't silently auto-proceed) |
| Business model | Free (10 sess/mo) / **$20/mo** unlimited / enterprise custom; pivoted OSS→closed-source SaaS (Strong) | Not finalized in context (TestFlight stage) (memory) | **Unknown/Omnara** — Omnara has a live, validated paid funnel; Lancer pre-revenue. Omnara's $9→$20 hike drew churn-to-Happy |

---

## Coverage limitations

- **X/Twitter (x.com/omnara_ai): BLOCKED** — HTTP 402 Payment Required. Could not read company
  posts, replies-beneath-posts, quote-posts, founder posts, or unanswered questions on X. This is
  the biggest gap vs. the brief's "read replies, not marketing" mandate for X specifically.
- **App Store / Google Play reviews: thin extraction.** Apple page yielded only 4 reviews (all
  positive); Play review body wasn't directly extractable (one negative captured via search
  snippet). Negative/refund/cancel reasons on the stores are under-sampled — likely more exist.
- **Pricing page (omnara.com/pricing) and several blog/marketing pages are JS-rendered**; WebFetch
  returned only the tagline. Pricing ($20/mo) corroborated via YC profile + HN, not the page itself.
- **No substantive Reddit thread found** for Omnara complaints (queries returned nothing on-topic).
  Either low Reddit presence or not surfaced; recorded as not-found, not fabricated.
- **Cloud-sandbox security internals** (exactly what code/data is uploaded, retention) inferred
  from a search snippet of the sandbox-sync blog, not the full text — labeled Inference where used.
- **No independent YouTube/third-party hands-on review** was located and verified within scope.
- **Promotional flagging:** Product Hunt comments and some early App Store reviews ("crazy how fast
  the team ships") read as launch-day boosterism/early-adopter tone — treated as Weak/Moderate and
  deduped; not weighted as independent reliability evidence.

---

## One-line verdict

**Omnara has captured the *category headline* (mobile command center for Claude Code/Codex on your
own machine) but NOT Lancer's defensible core:** it runs on plaintext-to-cloud with no true E2EE
(founder-admitted), an ungoverned "tap-continue" approval that has literally broken on Claude Code
updates and lacked a stop button, inconsistent actionable push (no real Android notifications), and
a brittle CLI-wrapper past it just archived for a closed-source Anthropic-SDK rebuild — so Lancer
can win materially on **fail-closed governed approvals (hook→policy→inbox→audit), end-to-end-
encrypted least-egress security, and verified push-while-closed approval**, the exact things Omnara
has architecturally traded away for voice + cloud convenience.
