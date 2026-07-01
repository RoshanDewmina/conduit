# 05 — Competitor and Pattern Research

> Organized by **workflow**, not by app (per the plan). Each row distills the strongest evidence from Waves 2; deep per-workflow treatment lives in docs 06–12. Every pattern names the source and its Lancer fit.

## Navigation & product shell

| | |
|---|---|
| **Examples** | GitHub Mobile (home triage), Slack (workspace switcher), Notion (sidebar + recents), Linear (command menu over dense lists), Vercel/Cloudflare (global search), Tailscale/Termius (host list → terminal drill-in), Raycast/Arc (command-first). |
| **Common pattern** | One attention-first home + sidebar/drawer for hierarchy + global search/command + dense lists for objects + drill-down for detail. |
| **Contrasting** | Consumer chat apps (ChatGPT/Claude) put a new-chat prompt at home; ops/dev tools put **work/status** at home. Bottom tabs (GitHub) imply peer product areas — wrong for Lancer. |
| **Works / fails** | Works: sidebar shell scales to technical sprawl. Fails: too many roots (Slack), tab bars implying peers. |
| **Lancer recommendation** | Keep the **sidebar / Command Home** shell; account/host switcher at drawer top; add a cross-surface search/command primitive. Full detail → [06](06-information-architecture.md). |

## Chat & agent interaction

| | |
|---|---|
| **Examples** | ChatGPT/Claude/Gemini/Copilot (discoverability affordances), Perplexity (visible work checklist), Codex mobile / GitHub Copilot agent (background work, diffs, PRs), Cursor (queued follow-ups, checkpoints), Linear (delegated agent tied to an issue). |
| **Common pattern** | Familiar composer + recents sidebar; agents increasingly show **explicit work state** (planning/editing/testing) and **evidence artifacts** (diff/test/file) over prose. |
| **Contrasting** | Consumer AI = "ask an assistant" home; developer agents = "supervise delegated work." Linear's human-owns-the-work model is the strongest fit for Lancer. |
| **Works / fails** | Works: Perplexity's process checklist, Linear's delegation. Fails: copying Claude's chat-home makes Lancer a generic AI clone. |
| **Lancer recommendation** | Chat is a **depth surface / dispatch primitive**, not home; keep chat grammar, change the noun hierarchy to governance-first. Full detail → [07](07-chat-and-agent-experience.md). |

## Approvals & high-risk actions

| | |
|---|---|
| **Examples** | Revolut Business (approve-request card + resolved state), Manus (diff toggle), Codex (lock-screen approve + approval modes), YNAB (batch review), Visible/Clubhouse/Moleskine (typed-delete confirm), Discord (audit log), Apple HIG Alerts. |
| **Common pattern** | Summary-first comprehension → raw detail secondary; friction proportional to consequence; resolved/already-handled states explicit; audit trail of who-did-what. |
| **Contrasting** | Finance gates the *most* destructive ops behind typed confirmation while routine ops are one-click — **proportional**, never uniform. Over-gating trains bypass. |
| **Works / fails** | Works: Revolut card anatomy, Manus diff, YNAB batch (low-stakes only). Fails: batching critical actions; fake undo. |
| **Lancer recommendation** | Risk-tier spine (low/med/high/critical → proportional friction); diff drill-in; "allow for session"; notification gating; Watch = deny + stop only. Full detail → [08](08-approval-and-security-experience.md). |

## Onboarding & pairing / trust

| | |
|---|---|
| **Examples** | Copilot (sample-first value), WhatsApp linked-devices (QR + reassurance + revoke), Brave VPN (pre-permission explanation), Marcus (step indicator + security rationale), adidas (non-blocking setup checklist), Telegram/WhatsApp (device management). |
| **Common pattern** | Value before account; setup as a **checklist** not a wall; explain each scary permission **before** the system dialog; show devices + revoke. |
| **Contrasting** | Consumer apps front-load hard onboarding paywalls; trust/dev/security apps lead with value + a demo. |
| **Works / fails** | Works: demo-first, contextual permissions, "skip-able" optional steps. Fails: onboarding paywall before value; login wall; camera prompt with no pre-explanation. |
| **Lancer recommendation** | First run = trust-building setup checklist (demo approval → mode → install bridge → pair → verify → policy → contextual permissions). Full detail → [10](10-onboarding-and-pairing.md). |

## Fleet / devices / activity / terminal

| | |
|---|---|
| **Examples** | Telegram/Chime (device list + last-seen + revoke), Starlink (single-device hero + metric tiles), Apple/Google Home (offline = dim + word + glyph), Tailscale (direct-vs-relay), Discord/monday.com/Squarespace (audit log structure), GitHub Mobile (checks-as-status-list), Termius/Mimo (SSH power-user terminal). |
| **Common pattern** | Status = **glyph + word + last-seen** (color reinforcement only); audit = `{actor} {action} {target} · {time}` date-grouped; mobile "terminal" = status blocks + drill-in, not a live PTY. |
| **Contrasting** | Termius (phone-IDE, full PTY) vs GitHub Mobile (watch + drill-in). Lancer's relay V1 is GitHub-Mobile-shaped; full PTY is the SSH power-user tier. |
| **Works / fails** | Works: centralized status model, link-event-back-to-session, block transcript. Fails: raw scrollback (Google TV), color-only status, building host-grouping at ≤3 hosts. |
| **Lancer recommendation** | Mandated status descriptor; Machines = adaptive sidebar root; Activity = contextual; V1 terminal = read-only block transcript + follow-up + Stop. Full detail → [09](09-fleet-activity-and-terminal.md). |

## Monetization & upgrade

| | |
|---|---|
| **Examples** | QUITTR/Sunlitt/Hevy/Fabulous (pay-once lifetime in Settings), Raycast (dev-tool Pro + usage meter), Manus/Vibecode/Revolut (usage-limit → upgrade), mymind/Vivino (contextual feature-lock sheet), Grok (onboarding paywall — anti-pattern). |
| **Common pattern** | Pay-once lives as a **persistent Settings/Billing row**; upsell at the **moment the limit is felt**, not at launch; contextual sheet names the specific locked benefit. |
| **Contrasting** | Subscription consumer apps front-load hard paywalls; pay-once prosumer/dev tools use a generous free tier + contextual upsell. |
| **Works / fails** | Works: contextual scale-friction upsell (Raycast/Manus). Fails: onboarding paywall, fake scarcity (QUITTR countdown), paywalling safety. |
| **Lancer recommendation** | StoreKit 2 direct, one-time Pro; wire the dead paywall at scale/automation triggers; never paywall safety; no onboarding paywall. Full detail → [11](11-monetization-and-upgrade-strategy.md). |

## Design system & identity

| | |
|---|---|
| **Examples** | Apple HIG (Materials/Liquid Glass, Typography, Color), GitHub iOS (disciplined mono, status = icon+color), Claude/Linear/Raycast (identity reference points). |
| **Common pattern** | Mono reserved for code-domain content; status never color-alone; glass on navigation chrome only; one recognizable accent. |
| **Contrasting** | Claude warmth vs Linear cold-precision vs Raycast neon — Lancer must avoid collapsing into any of them. |
| **Works / fails** | Works: token + risk-ramp system already built. Fails: glass-on-every-button, 5-theme accent picker, mono in UI chrome, half-tokenized adoption. |
| **Lancer recommendation** | "Warm control room" identity; enforce token adoption with CI lints; de-glass buttons; ship light+dark default dark. Full detail → [12](12-design-system-recommendations.md). |

## Source hierarchy applied

Per the plan: (1) official Apple docs/release notes/WWDC, (2) official product docs, (3) Mobbin screens/flows, (4) App Store listings, (5) reputable product-design analysis, (6) forums for pain points only. All Apple-platform claims in docs 04/08/11/12 cite developer.apple.com; all Mobbin lanes record app + platform + observed pattern + weakness + Lancer fit + reference. Full citation list: [sources.md](sources.md).
