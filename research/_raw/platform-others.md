# Platform Survey — OTHER AI-coding / dev-infra vendors vs Lancer

> Scope: remote-execution, background-agent, mobile, notification, approval, and multi-agent
> capabilities that overlap with **Lancer** (third-party iOS "mission control" for AI coding agents
> running on a developer's own machines: cross-provider, governed approvals from the phone,
> multi-machine visibility, notifications, emergency stop).
> Compiled 2026-06-23. Buckets: (1) Available now (2) Announced (3) Experimental (4) Community workaround (5) Speculation.
> Evidence strength: **Strong** (official docs/changelog) / **Moderate** (vendor blog/marketing or reputable press) / **Weak** (secondary blog) / **Inference** / **Unknown**.

---

## Source ledger

| # | Source | URL | Date | Used for | Strength |
|---|---|---|---|---|---|
| S1 | Cursor — Agent on web and mobile (blog) | https://cursor.com/blog/agent-web | 2025 | Cursor web/mobile/PWA agent control | Strong |
| S2 | Cursor Docs — Cloud Agents web & mobile | https://cursor.com/docs/cloud-agent/web-and-mobile | 2026 | PWA install, manage agents from phone | Strong |
| S3 | Cursor Docs — Slack integration | https://cursor.com/docs/integrations/slack | 2025 | @Cursor launch from Slack, notifications | Strong |
| S4 | Cursor changelog 1.1 — Background Agents in Slack | https://cursor.com/changelog/1-1 | 2025-06 | Slack-launch background agents | Strong |
| S5 | TechCrunch — Cursor web app to manage agents | https://techcrunch.com/2025/06/30/cursor-launches-a-web-app-to-manage-ai-coding-agents/ | 2025-06-30 | Mobile assign-from-phone | Moderate |
| S6 | InfoQ — Cursor 3 agent-first interface | https://www.infoq.com/news/2026/04/cursor-3-agent-first-interface/ | 2026-04 | Agent-first pivot | Moderate |
| S7 | HN — Cursor 3 discussion | https://news.ycombinator.com/item?id=47618084 | 2026 | User reactions / lock-in critique | Moderate |
| S8 | GitHub Blog — Meet the new coding agent | https://github.blog/news-insights/product-news/github-copilot-meet-the-new-coding-agent/ | 2025-05 | Assign issue → PR loop, can't self-approve | Strong |
| S9 | GitHub Blog — Assigning & completing issues w/ coding agent | https://github.blog/ai-and-ml/github-copilot/assigning-and-completing-issues-with-coding-agent-in-github-copilot/ | 2025 | Assign on GitHub Mobile/CLI | Strong |
| S10 | GitHub Changelog — Remote control for Copilot CLI sessions GA | https://github.blog/changelog/2026-05-18-remote-control-for-copilot-cli-sessions-now-generally-available-on-mobile-web-and-vs-code/ | 2026-05-18 | **Approve/deny perms + steer LOCAL CLI from mobile** | Strong |
| S11 | GitHub Docs — About remote control of Copilot CLI sessions | https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-remote-control | 2026 | Non-GitHub repos / local dirs, approvals | Strong |
| S12 | GitHub Blog — Introducing Agent HQ | https://github.blog/news-insights/company-news/welcome-home-agents/ | 2025-10-28 | **Cross-vendor "mission control" across mobile** | Strong |
| S13 | VentureBeat — Agent HQ central control | https://venturebeat.com/ai/githubs-agent-hq-aims-to-solve-enterprises-biggest-ai-coding-problem-too | 2025-10 | Too-many-agents / central control framing | Moderate |
| S14 | Google Dev Blog — Jules extension for Gemini CLI | https://developers.googleblog.com/en/introducing-the-jules-extension-for-gemini-cli/ | 2025 | Async background agent in VM, plan approve | Strong |
| S15 | Google Dev Blog — Jules Tools CLI + API | https://developers.googleblog.com/en/meet-jules-tools-a-command-line-companion-for-googles-async-coding-agent/ | 2025-10-02 | Jules API/CLI orchestration | Strong |
| S16 | Jules docs — getting started | https://jules.google/docs/ | 2025 | Plan approve, notifications, web UI | Strong |
| S17 | Jules changelog 2025-12-10 — suggested tasks | https://jules.google/docs/changelog/2025-12-10/ | 2025-12-10 | Proactive scanning, approve/dismiss | Strong |
| S18 | Replit blog — Agent on iOS and Android | https://blog.replit.com/try-agent | 2025 | Native mobile app builds + deploys in cloud | Moderate |
| S19 | Replit mobile-apps page | https://replit.com/mobile-apps | 2025 | Mobile Agent scope (web apps on the go) | Moderate |
| S20 | Devin Docs — Slack | https://docs.devin.ai/integrations/slack | 2025 | Slack-driven async runs + notifications | Strong |
| S21 | Cognition blog — Dec '24 product update | https://cognition.com/blog/dec-24-product-update | 2024-12 | Devin Slack/async, scheduled sessions | Moderate |
| S22 | Factory — Web and Mobile product | https://factory.ai/product/web | 2025/26 | **Approve diffs / unblock droids from phone** | Strong |
| S23 | Factory — Slack product | https://factory.ai/product/slack | 2025 | Slack droids | Moderate |
| S24 | Factory — GA news | https://factory.ai/news/factory-is-ga | 2025 | Droids across CLI/Web/Slack/Mobile | Moderate |
| S25 | Sourcegraph — Amp homepage | https://ampcode.com/ | 2026 | "Drive your agents from anywhere: web, CLI, mobile" | Moderate |
| S26 | Amp Owner's Manual | https://ampcode.com/manual | 2026 | Thread sync across devices | Moderate |
| S27 | ChatForest — Windsurf 2.0 review | https://chatforest.com/reviews/windsurf-2-0-cognition-devin-agent-command-center-ide-review/ | 2026-04 | Devin-in-IDE, Agent Command Center | Weak |
| S28 | AIToolTier — Windsurf → Devin Desktop | https://aitooltier.com/tools/windsurf | 2026-06 | Rebrand to Devin Desktop | Weak |
| S29 | OpenCode docs — TUI / intro | https://opencode.ai/docs/tui/ | 2026 | Client/server, mobile client beta | Moderate |
| S30 | Kilo Code docs — using agents / orchestrator | https://kilo.ai/docs/code-with-ai/agents/using-agents | 2026 | Sub-agents, multi-surface (no mobile control) | Moderate |
| S31 | Cloudflare changelog — Code Sandboxes | https://developers.cloudflare.com/changelog/2025-06-24-announcing-sandboxes/ | 2025-06-24 | Agent sandbox infra (platform, not control) | Strong |
| S32 | InfoQ — Cloudflare Sandboxes GA | https://www.infoq.com/news/2026/04/cloudflare-sandboxes-ga/ | 2026-04 | PTY, snapshot, credential injection | Moderate |
| S33 | Vercel — Agents / Open Agents | https://vercel.com/agents | 2025/26 | Background agent runtime, v0 iOS app | Moderate |
| S34 | Railway changelog — Agent sandbox | https://railway.com/changelog/2026-05-22-chat-agent-sandbox | 2026-05-22 | Sandbox exec infra | Moderate |
| S35 | Modal/Mastra sandbox docs | https://mastra.ai/docs/workspace/sandbox | 2026 | Modal/Railway sandbox exec tooling | Moderate |
| S36 | Marc Nuri — AI coding agent dashboard across devices | https://blog.marcnuri.com/ai-coding-agent-dashboard | 2026 | Community: live terminal + approve perms from phone | Weak |
| S37 | BloopAI Vibe Kanban (GitHub) | https://github.com/BloopAI/vibe-kanban | 2025/26 | Cross-vendor desktop orchestrator (shutdown→OSS) | Moderate |
| S38 | Augment — open-source agent orchestrators | https://www.augmentcode.com/tools/open-source-agent-orchestrators | 2026 | Conductor/Claude Squad/etc. landscape | Weak |
| S39 | linkalls/jules-mobile-client (GitHub) | https://github.com/linkalls/jules-mobile-client | 2025 | Unofficial Jules iOS/Android client (community) | Moderate |
| S40 | TechCrunch — Jules enters toolchains | https://techcrunch.com/2025/10/02/googles-jules-enters-developers-toolchains-as-ai-coding-agent-competition-heats-up/ | 2025-10-02 | Jules API/competition context | Moderate |

---

## Vendor capability matrix

Legend: ✅ = available now · ◐ = partial/limited · 📣 = announced/preview · ✱ = experimental/beta · 🛠 = community workaround · ✖ = no · ? = unknown.
"Mobile control" = can you **start / steer / approve** an agent from a phone today.

| Vendor | Remote exec | Background agents | Mobile control | Notifications | Approvals | Multi-agent | Bucket | Overlap w/ Lancer | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| **GitHub Copilot (coding agent + CLI remote control + Agent HQ)** | ✅ cloud (Actions) **+ ✅ your local CLI session streamed** | ✅ | ✅ **approve/deny perms, steer, plan-review from GitHub Mobile** | ✅ mobile/web | ✅ tool/file/URL perm prompts; can't self-merge | ✅ fleet, parallel | (1) Available now; Agent HQ cross-vendor (2) Announced/rolling | **Highest** — phone-based governed approval of a CLI agent incl. non-GitHub/local dirs; Agent HQ is literal "mission control" across mobile | S8–S13 Strong |
| **Cursor (Cloud/Background Agents, Web+Mobile, Slack)** | ✅ cloud VMs | ✅ | ✅ assign/steer from mobile browser/PWA | ✅ Slack + web | ◐ review/edit/takeover; less granular per-tool gating | ✅ parallel cloud agents | (1) Available now | **High** — start/steer agents from phone PWA; but Cursor-only, cloud-hosted (not your machines) | S1–S7 Strong/Moderate |
| **Factory (Droids — Web & Mobile, Slack)** | ✅ local + remote droids | ✅ | ✅ **approve diffs, unblock droids, leave feedback from phone (web)** | ✅ Slack | ✅ diff approval, mobile-first review flow | ✅ droid "army" | (1) Available now | **High** — explicit "ship from your phone," approve diffs; web (not native iOS), Factory-only | S22–S24 Strong/Moderate |
| **Sourcegraph Amp** | ✅ agent runs locally/CI | ✅ loops to done | ✅ "drive your agents from anywhere: web, CLI, **mobile**"; threads sync | ◐ (thread sync; explicit push unclear) | ◐ (in-thread steer) | ✅ plugins spawn agents | (1) Available now | **Moderate-High** — mobile drive + cross-device threads; Amp-only | S25–S26 Moderate |
| **Devin / Cognition** | ✅ cloud VM | ✅ most-autonomous async | ◐ Slack-from-phone (no first-party mobile control app) | ✅ Slack DMs per-run | ◐ via Slack/PR review | ✅ multiple Devins, scheduled | (1) Available now | **Moderate** — async + Slack notifications mirror Lancer's loop; control via Slack not a control app | S20–S21 Strong/Moderate |
| **Windsurf → "Devin Desktop" (Cognition)** | ✅ Devin Cloud in IDE | ✅ Agent Command Center (Kanban) | ✖ (desktop IDE; no mobile control) | ◐ | ◐ in-IDE | ✅ session Kanban | (1) Available now | **Low-Moderate** — desktop multi-agent command center; not mobile | S27–S28 Weak |
| **Google Gemini CLI + Jules** | ✅ Jules cloud VM | ✅ async | ◐ mobile **web** UI (no native notifications yet); 🛠 unofficial mobile client | ◐ in-app; native mobile notifs not yet | ✅ **plan approve before code**; suggested-tasks approve/dismiss | ✅ multiple parallel Jules | (1) Available now; native mobile notifs (5) not shipped | **Moderate** — plan-approval + async loop; mobile is web-only, no phone push | S14–S17, S39–S40 Strong/Moderate |
| **Replit (Agent, iOS/Android app)** | ✅ cloud (Google Cloud) | ◐ (interactive, not headless fleet) | ✅ **native app** builds web apps w/ Agent on the go | ◐ (app push for built apps) | ✖ (no governed external-machine approvals) | ✖ | (1) Available now | **Low** — native mobile + cloud agent, but builds *Replit-hosted* apps; not control of *your* machines | S18–S19 Moderate |
| **OpenCode (sst/anomaly)** | ✅ local agent server | ✅ | ✱ **mobile client in beta** (server is a daemon, drivable remotely) | ? | ◐ permission prompts in TUI | ✅ sub-agents | (3) Experimental (mobile) | **Watch** — open-source client/server arch is architecturally closest to Lancer's daemon model; mobile beta | S29 Moderate |
| **Kilo Code** | ✅ VS Code/JetBrains/CLI/cloud | ✅ sub-agents | ✖ | ? | ◐ in-editor | ✅ orchestrator/sub-agents | (1) Available now | **Low** — multi-agent but editor-bound, no mobile/approval-from-phone | S30 Moderate |
| **Cloudflare (Agents, Sandboxes, Code Mode)** | ✅ sandboxed Workers/Linux | ✅ (your agents) | ✖ (infra, no app) | ✖ | ✖ | n/a (substrate) | (1) Available now | **None direct** — platform substrate to *build* something Lancer-like, not a competitor | S31–S32 Strong/Moderate |
| **Vercel (v0, Agent, Open Agents)** | ✅ Fluid compute / sandboxes | ✅ Open Agents template | ◐ v0 iOS app (builds apps, not agent-fleet control) | ◐ | ◐ Vercel Agent = PR review bot | ✅ (build-your-own) | (1) Available now | **Low** — v0 mobile builds apps; Open Agents = DIY background coding-agent kit | S33 Moderate |
| **Railway** | ✅ ephemeral sandboxes | ✅ deploy background agent | ✖ | ✖ | ✖ | n/a | (1) Available now | **None direct** — exec substrate / self-host background-agent host | S34 Moderate |
| **Modal** | ✅ sandbox exec (AgentCoreRuntimeSandbox) | ✅ | ✖ | ✖ | ✖ | n/a | (1) Available now | **None direct** — sandbox exec primitive for agent builders | S35 Moderate |
| **Community orchestrators (Vibe Kanban, Conductor, Claude Squad)** | ✅ local worktrees | ✅ parallel | ◐ web UI reachable on phone (Vibe Kanban); 🛠 not mobile-first | ◐ | ◐ visual diff review | ✅ **cross-vendor** (Claude/Codex/Gemini/Copilot) | (1)/(4) Available / workaround | **Moderate** — cross-vendor parallel orchestration is Lancer-adjacent; desktop-first, Vibe Kanban vendor shut down (now OSS) | S37–S38 Moderate/Weak |

---

## Notable threats & substitutes

**1. GitHub Agent HQ + Copilot CLI remote control — the existential threat (Strong, S10–S13).**
Two GitHub moves converge directly onto Lancer's positioning:
- **Copilot CLI remote control (GA 2026-05-18):** stream a **local CLI session** and, from **GitHub Mobile**, "approve or deny permission requests" for **tool, file path, and URL** actions, "steer midsession," "review and tweak plans before Copilot starts implementing," "stop a session at any time," and respond to the agent's questions — explicitly including **non-GitHub repositories and directories not associated with a repository** (S10/S11). That is governed, phone-based approval of a CLI agent on a developer's own working directory — the core Lancer loop, shipped by the platform owner.
- **Agent HQ (announced Universe 2025-10-28):** a "unified command center … a consistent interface across GitHub, VS Code, **mobile**, and the CLI," bringing **third-party agents from Anthropic, OpenAI, Google, Cognition, and xAI** under one mission-control surface, included in paid Copilot subscriptions (S12/S13). This is *cross-vendor mobile mission control* — Lancer's exact tagline — backed by GitHub's distribution. Caveat: GitHub's gravity is the cloud/PR loop and GitHub-managed runners; Lancer's wedge is **agents on the developer's own arbitrary machines/servers** (SSH/daemon, self-host), multi-vendor CLIs that may never touch GitHub, and an emergency-stop / fleet-health framing. But the conceptual moat is shrinking fast.

**2. Cursor (Strong, S1–S7) and Factory (Strong, S22–S24) — phone-based agent control TODAY.**
Both let you **start, steer, and approve from a phone right now**. Cursor: web app + installable PWA to dispatch background agents by natural language and take over the remote desktop; Slack `@Cursor` launch + completion notifications. Factory's Web & Mobile product is even more on-the-nose: "Approve diffs, leave feedback, and ship without waiting until you're back at your desk … unblock Droids from your phone," with a mobile-first review flow. Both are **single-vendor and cloud-hosted** (their agents, their VMs) — Lancer's differentiation is cross-provider + your-own-machines + governance, but a user who lives in one vendor already has "approve from phone."

**3. Devin (Moderate, S20–S21) — the async/Slack substitute.**
Devin's Slack-native loop (tag Devin, it works async, DMs you status updates, opens a PR; can schedule recurring sessions and trigger other Devins) is a **behavioral substitute** for "get notified, approve/steer from your pocket." No first-party mobile control app, but Slack-on-phone covers ~80% of the felt need for many teams. Auto-Triage / event-driven runs push it toward an autonomous loop where the human is a Slack approver.

**4. Sourcegraph Amp (Moderate, S25–S26) — quiet mobile-drive claim.**
Marketing states you can "watch and drive your agents from anywhere: web, CLI, and **mobile**," with threads syncing across devices. Less detailed/granular than GitHub or Factory, but another vendor asserting phone-driven agent control.

**5. Cross-vendor orchestrators (Moderate, S37–S38) + the lock-in critique.**
Vibe Kanban / Conductor / Claude Squad run **multiple agents from different vendors** (Claude Code, Codex, Gemini, Copilot) in parallel with diff-first review — the cross-provider half of Lancer's pitch — but they are **desktop/web, not mobile-native**, and Vibe Kanban's parent (Bloop) shut down (now community OSS). They validate demand for vendor-agnostic orchestration while leaving the **mobile + governed-approval + arbitrary-remote-machine** niche open. The risk is one of them (or OpenCode's daemon+mobile-beta architecture, S29) adds a phone client.

**Substitutes that are NOT threats:** Cloudflare Sandboxes, Vercel Open Agents, Railway, Modal are **execution substrate** — primitives you'd use to *build* a Lancer-like backend, not products that control agents from a phone. They're potential integration targets or self-host hosts, not competitors.

---

## User reactions

| Product | Source | Date | URL | Statement (paraphrased) | Sentiment | Category | Severity | Engagement | Evidence strength | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Cursor 3 (agent-first) | HN | 2026 | https://news.ycombinator.com/item?id=47618084 | Agent-first model feels wrong for flow: "reviewing and testing code, constantly switching contexts … practically impossible to achieve flow state." | Negative | UX / workflow fit | Medium | HN front-page thread | Moderate | Tension applies to any phone-driven async control incl. Lancer |
| Cursor 3 / agent command center | HN (via search summary) | 2026 | https://news.ycombinator.com/item?id=47618084 | "The proper agent command center I would want … is the one that I could manage all AI agents I have, **not lock into one vendor**." | Mixed (demand signal) | Cross-vendor demand / lock-in | High (validates Lancer thesis) | HN comment | Moderate | Direct validation of Lancer's cross-provider wedge |
| Cursor (cost) | HN | 2025/26 | https://news.ycombinator.com/item?id=47618084 | Spent "$2k/week with premium models" on Cursor, switched to Claude Code Max for "1/10th the price." | Negative | Cost | Medium | HN comment | Moderate | Pushes users to CLI agents (Claude Code) — Lancer's home turf |
| Cursor IDE concern | HN (Lee Robinson, Cursor) | 2026 | https://news.ycombinator.com/item?id=47618084 | Cursor eng clarifies traditional IDE view still exists; agent UI is a separate window. | Defensive/neutral | Positioning | Low | Vendor reply | Moderate | Vendor managing agent-first backlash |
| GitHub Copilot CLI remote control | GitHub community discussion | 2026 | https://github.com/orgs/community/discussions/192947 | GA announcement thread (steer sessions from any device). | Positive (vendor-announced) | Feature launch | n/a | Official discussion | Strong | Reactions not deeply mined (see limitations) |
| Cross-device agent dashboard | Marc Nuri blog | 2026 | https://blog.marcnuri.com/ai-coding-agent-dashboard | DIY dashboard: "live terminal … approve permissions, or intervene … from any device: laptop, phone, tablet." | Positive | DIY substitute | Medium | Personal blog | Weak | Shows individuals building Lancer-like tooling themselves |

(Reaction mining was light — see Coverage limitations.)

---

## Classification

- **GitHub (Copilot coding agent + CLI remote control + Agent HQ)** — **Direct competitor / platform threat.** Phone-based governed approval of a CLI agent on local/non-GitHub dirs ships today; Agent HQ is explicitly cross-vendor mobile "mission control." Highest overlap; the must-watch competitor. (S8–S13)
- **Cursor** — **Direct competitor (single-vendor).** Start/steer/review agents from phone PWA + Slack today; weaker on granular per-tool governance and on *your own arbitrary machines*. (S1–S7)
- **Factory** — **Direct competitor (single-vendor).** Approve diffs / unblock droids / ship from phone (web). Strong overlap on the approval-from-phone behavior. (S22–S24)
- **Sourcegraph Amp** — **Direct competitor (single-vendor, lighter).** Claims mobile drive + cross-device threads; less detailed governance. (S25–S26)
- **Devin / Cognition** — **Substitute.** Slack-driven async loop + notifications cover the "approve from pocket" job without a dedicated mobile control app. (S20–S21)
- **Windsurf → Devin Desktop** — **Adjacent.** Desktop multi-agent command center; no mobile. (S27–S28)
- **Google Gemini CLI + Jules** — **Adjacent → substitute.** Plan-approval + async cloud agent; mobile is web-only with no native push yet. Potential threat if native mobile lands. (S14–S17, S39–S40)
- **Replit** — **Adjacent / substitute (different segment).** Native mobile + cloud agent, but builds Replit-hosted apps; not control of the user's own machines/CLIs. (S18–S19)
- **OpenCode** — **Adjacent — watch closely.** Open-source local agent **server + mobile client (beta)** is the architecture nearest to Lancer's daemon model; could become a competitor or an integration target. (S29)
- **Kilo Code** — **Adjacent.** Multi-agent/sub-agents but editor-bound; no mobile/approval-from-phone. (S30)
- **Community orchestrators (Vibe Kanban / Conductor / Claude Squad)** — **Adjacent + demand validators.** Cross-vendor parallel orchestration (the multi-provider half) but desktop-first; one could add a phone client. (S37–S38)
- **Cloudflare / Vercel / Railway / Modal** — **Potential integration / platform (not competitors).** Execution substrate to build or self-host a Lancer-like backend; irrelevant as phone control surfaces. (S31–S35)

**Irrelevant to Lancer's control thesis:** the raw sandbox/exec layers (Cloudflare Sandboxes, Modal, Railway sandboxes) — relevant only as future hosting/integration, never as mobile competitors.

---

## Coverage limitations

1. **Reaction mining is thin.** I surfaced HN/blog reactions for Cursor and one DIY-dashboard blog, but did NOT deep-dive Reddit/X/forum sentiment for Factory, Amp, Devin, Jules, or GitHub remote control. The user-reactions table is illustrative, not exhaustive — a follow-up pass on r/ChatGPTCoding, r/cursor, and HN launch threads is warranted.
2. **No login-walled sources fabricated.** Slack Marketplace, some vendor dashboards, and X threads were not authenticated; nothing behind a login was asserted.
3. **Dates of "Available now" claims** rely on vendor docs/changelogs current as of June 2026; marketing pages (Factory, Amp) lack hard ship dates and are marked Moderate. Amp's "mobile" claim is marketing-page text not independently verified with a screenshot or docs page.
4. **Agent HQ third-party agents are "rolling out over coming months"** (announced 2025-10) — partly Announced/Experimental, not uniformly GA; matrix marks GitHub as mixed (1)/(2).
5. **Jules native mobile notifications** were explicitly "not yet supported" per docs search; treated as not-shipped (no speculation about timing).
6. **OpenCode mobile client** described as "beta" in secondary summaries; not confirmed against a first-party release note — Experimental bucket, Moderate strength.
7. **Windsurf rebrand to "Devin Desktop"** rests on a Weak-strength secondary source (aitooltier); the *substance* (Devin-in-IDE, Agent Command Center) is corroborated but the rebrand specifics are lower confidence.
8. I did not separately verify GitHub Codespaces as its own row — it functions as a runtime substrate under Copilot/Agent HQ rather than an independent mobile-control product; folded into the GitHub analysis and the "substrate" classification.
