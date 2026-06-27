---
title: Mobile UX patterns for technical/operations apps — research for Lancer
type: research-raw
captured_at: 2026-06-23T23:16:40Z
status: draft
confidence: moderate
tags: [ux/mobile, devtools, ssh, incident, git, lancer]
---

# Mobile UX patterns for developer/ops apps — evidence base for Lancer

Purpose: extract evidence-backed UX lessons from adjacent mobile apps (SSH/terminal, infra
monitoring, incident/on-call, git clients, notification-to-action) that Lancer — an iOS "mission
control" for AI coding agents (inbox, governed approvals, notifications, diff/log review,
multi-machine, block terminal) — should adopt or avoid.

Evidence labels: **Strong** (direct first-party reviews/threads, multiple corroborating),
**Moderate** (single credible source or aggregator paraphrase), **Weak** (passing mention),
**Inference** (my analytical synthesis, not stated by a source), **Unknown** (gap). Vendor/affiliate
content is flagged. Quotes are paraphrases from search-result summaries unless wrapped in quotes from
a fetched page; I did not fabricate any quote or number.

---

## Source ledger

| # | Source | URL | Date accessed | Type | Notes / bias |
|---|--------|-----|---------------|------|--------------|
| S1 | Termius App Store reviews (aggregated via search) | https://apps.apple.com/us/app/termius-modern-ssh-client/id549039908?see-all=reviews | 2026-06-23 | App Store reviews | first-party user reviews |
| S2 | Termius — Marlvel sentiment intel report | https://marlvel.ai/intel-report/developer-tools/termius-modern-ssh-client | 2026-06-23 | aggregator/sentiment | 3rd-party analytics; paraphrase |
| S3 | Argsment "Top 5 iOS SSH Clients 2026" | https://www.argsment.com/blog/top-5-ios-ssh-clients-2026 | 2026-06-23 | review blog | possible affiliate; comparative |
| S4 | Moshi "Best iOS Terminal App for AI Coding Agents 2026" | https://getmoshi.app/articles/best-ios-terminal-app-coding-agent | 2026-06-23 | vendor blog | **PROMO** (Moshi's own product); most directly on-topic for Lancer |
| S5 | Blink Shell HN thread (id=21061803) | https://news.ycombinator.com/item?id=21061803 | 2026-06-23 | forum / direct quotes | named-user opinions |
| S6 | Blink Shell HN Show HN (id=12932592) | https://news.ycombinator.com/item?id=12932592 | 2026-06-23 | forum | (listed, not deep-read) |
| S7 | Secure ShellFish — MacStories review | https://www.macstories.net/reviews/secure-shellfish-review-adding-your-mac-or-another-ssh-or-sftp-server-to-apples-files-app/ | 2026-06-23 | independent review | credible indie-mac press |
| S8 | Secure ShellFish App Store / site | https://secureshellfish.app/ | 2026-06-23 | vendor + reviews | mixed |
| S9 | PagerDuty mobile app docs | https://support.pagerduty.com/main/docs/mobile-app | 2026-06-23 | vendor docs | feature truth, **PROMO** framing |
| S10 | PagerDuty Google Play reviews (via search) | https://play.google.com/store/apps/details?id=com.pagerduty.android | 2026-06-23 | store reviews | first-party complaints |
| S11 | Opsgenie reviews (Capterra/Play/TrustRadius via search) | https://www.capterra.com/p/170236/OpsGenie/reviews/ | 2026-06-23 | review aggregators | first-party complaints paraphrased |
| S12 | incident.io "Opsgenie vs JSM mobile on-call usability" | https://incident.io/blog/opsgenie-vs-jsm-mobile-app-on-call-usability | 2026-06-23 | vendor blog | **PROMO** (incident.io competitor); useful eval framework |
| S13 | Datadog mobile app docs | https://docs.datadoghq.com/mobile/ | 2026-06-23 | vendor docs | feature truth |
| S14 | Datadog App Store reviews (via search) | https://apps.apple.com/us/app/datadog/id1391380318 | 2026-06-23 | store reviews | first-party complaints |
| S15 | Working Copy App Store + reviews | https://apps.apple.com/us/app/git-client-working-copy/id896694807 | 2026-06-23 | reviews + vendor | strong praise corpus |
| S16 | GitHub "Enhanced Code Review on Mobile" changelog | https://github.blog/changelog/2024-04-09-introducing-enhanced-code-review-on-github-mobile/ | 2026-06-23 | vendor changelog | feature truth |
| S17 | GitHub community discussions (PR review friction) | https://github.com/orgs/community/discussions/10830 , /163932 , /168685 , /39341 | 2026-06-23 | forum / first-party | complaints about large-PR/diff review |
| S18 | Grafana IRM reviews + iOS issues (via search) | https://apps.apple.com/us/app/grafana-irm/id1669759048 | 2026-06-23 | store reviews + GH issues | alert-sound complaints |
| S19 | Push-notification UX best-practice articles (UX Mag, Appbot, Toptal, Eleken) | https://uxmag.com/articles/push-notification-best-practices-7-questions-designers-should-ask | 2026-06-23 | UX practitioner blogs | design heuristics, alert-fatigue stats |

---

## Per-app notes

### Termius (SSH client) — S1, S2, S3
**Strengths.** Best-in-class cross-platform UI; cloud sync of hosts/keys/snippets across devices is the
headline praise. Reviewers single out the **port-forwarding UI** as making "lots of confusable details
fairly straightforward" — i.e. it tames a fiddly technical task with good form design (Moderate, S1).
Defenders accept the subscription because sync "gets better over time" as their fleet grows (Moderate, S1).
**Weaknesses.** The **subscription pivot (2024)** is the dominant complaint: "an SSH app with all the
bells and whistles should be a one-time purchase"; $8/mo for something "that doesn't rely on definition
updates" reads as rent-seeking (Strong, S1/S3). **Mandatory account creation is called out as a top driver
of instant uninstalls / negative sentiment** (Moderate, S2). No mosh — flagged as a mobile-reliability
"dealbreaker" by a competitor (Weak/biased, S4).
**Pricing.** Freemium; ~$8.33/mo Pro (sync, SFTP, snippets gated). Subscription resentment is high.

### Blink Shell (SSH/mosh terminal) — S4, S5
**Strengths.** "Desktop-grade" terminal; **mosh** is the standout — local echo hides latency and, crucially,
**sessions survive network changes and device sleep** ("jump from home, to the train, to the office… your
connections will be intact"). Heavy keyboard customization; Magic Keyboard support praised (Strong, S5).
Named HN users: "fantastic terminal that works wonderfully," "best terminal app I could find" (Strong, S5).
**Weaknesses.** Input dropout on weak Wi-Fi (problematic mid-`sudo`); rough edges in **split-screen / app
switching**; Caps-Lock-as-Ctrl state desyncs after backgrounding (iOS limitation) (Moderate, S5). The
**subscription pivot drew the same resentment** as Termius — "5 stars if there were a one-time purchase"
(Strong). Competitor notes Blink "can't notify you when your agent needs input" (Weak/biased, S4 PROMO).
**Pricing.** Subscription (historically ~$20 one-time; now sub). Some defend the price for a pro tool.

### Secure ShellFish (SSH/SFTP) — S7, S8
**Strengths.** **Killer feature = native Files.app integration** — mount remote servers as drives, edit with
any document-based app, drag-and-drop, offline caching (Strong, S7). Deep **Shortcuts/automation** (run
command, upload/download, list dir) and **Home/Lock/StandBy/Watch widgets driven by server data** (Moderate,
S7/S8). Reframes SSH around *files* rather than *shell* — a different, lower-friction mental model.
**Weaknesses.** Free tier shows **ads in the terminal** (paid removes); some power features gated. Fewer
explicit complaints surfaced (lower review volume) (Weak — coverage gap).
**Pricing.** Useful free; Pro unlocks unlimited servers, Files uploads, ad-free terminal.

### Moshi (SSH/mosh terminal purpose-built for AI agents) — S4 (PROMO)
Directly adjacent to Lancer; **treat all claims as vendor marketing.** The *framing* is the value:
- **Push notifications replace polling** — webhook-triggered "agent needs input" alerts fan out to iPhone/
  iPad/Watch so you don't babysit a terminal (Inference-worthy framing; unverified efficacy).
- **Voice input to approve** — speaking a response beats typing on a phone keyboard when an agent asks
  permission (on-device speech) (Moderate as a *pattern*, Unknown as quality).
- **In-app diffs + web previews** so review happens without leaving the app.
- **Live Activities** for long-running agent runs; **image paste** for visual debugging.
- Reiterates the **mosh/session-persistence** thesis as table stakes for mobile.

### PagerDuty (incident/on-call) — S9, S10
**Strengths.** **Three ways to Ack, ranked by speed:** swipe-left → Ack on the list; Ack button on detail;
**long-press the push notification → Ack without opening the app** (Strong, S9). Home surfaces **top open
incidents + your on-call shifts** first (right info first) (Strong, S9).
**Weaknesses.** "App has **more management functionality than is appropriate** — should be a small feature set
designed for responders" (Strong user quote, S10). Widget too large; missing a "you're now on-call"
notification; "interface not helpful for admin tasks" (Moderate, S10). **Lesson: a responder app should
stay lean; don't port the whole web console.**

### Opsgenie (incident/on-call) — S11
**Strengths.** Instant push; Ack/take-action in-app; team sees who acknowledged (Moderate, S11).
**Weaknesses (concrete, repeated).** After Ack a **bottom popup blocks the next swipe** — you must tap to
dismiss before acting again (friction in bulk triage). **Swipe gestures reset** when the prior row closes,
breaking rapid list triage. App **force-maxes notification volume and never restores it.** **2FA re-auth
required just to silence an alarm** that's actively going off — hostile under stress (Strong cluster, S11).
On-call schedule only shows now/next, not the week ahead (Moderate).

### incident.io eval framework — S12 (PROMO, but useful)
Four mobile on-call metrics worth stealing as Lancer's own approval-UX rubric:
1. **TTA (time/taps to Acknowledge)** — "how many taps from notification to Ack?"
2. **Alert context** — show what's broken *without* extra navigation.
3. **Escalation ease** — page another team in two taps, not via menu-digging.
4. **Notification reliability** — iOS Critical Alerts (bypass Silent Mode) + **insistent/repeating alerts
   until acknowledged**; auto-unmute the device. Calls missing insistent alerts "a reliability gap… longer
   MTTR," not a cosmetic issue. Mantra: **"A ticket can wait. A P1 at 3 AM cannot."** (Strong as framework.)

### Datadog mobile (monitoring) — S13, S14
**Strengths.** From an alert (On-Call/Slack/email) you can **jump straight into monitor graphs, dashboards,
logs, traces, incidents**; rich **widgets** (active incidents, on-call rotations, pages, monitors, SLOs)
(Moderate, S13).
**Weaknesses.** "In 2025, on-call devs must have an app with **all the same functionality as desktop**…
Datadog's needs to be completely redesigned" (Strong complaint, S14). **Alert-sound bug**: tapping the
alert while half-asleep dismisses the visual but **the sound won't stop without powering off the phone**
(Strong, S14). Dense desktop data doesn't shrink gracefully.

### Working Copy (git client) — S15
**Strengths.** Reference example of **dense git on a phone done well.** Diff viewer praised for text *and*
images; **commit-graph you can zoom out (overview) / zoom in (detail)** — "speed and beauty you won't find
in desktop Git" (Strong, S15). Explicitly valued **as a review/discussion companion even if you never edit
a line on iOS** — exactly Lancer's "steer, don't IDE" posture (Strong, S15). Handles conflicts/merges
gracefully.
**Weaknesses.** **Discoverability** — features are buried on iPhone; users "dig to find" them; non-obvious
that tapping the remote name fetches (Moderate, S15). A "tappable checkbox" markdown feature introduced a
wrong-line bug (Weak).
**Pricing.** One-time / IAP — notably *not* resented, unlike the SSH-app subs.

### GitHub Mobile (PR/diff review) — S16, S17
**Strengths.** Enhanced code review: **tap `+` on a line for inline comments, long-press for multi-line
select, "Jump To" file navigator, toggle split/unified diff** to fit the screen, approve/request-changes
in-app (Strong, S16).
**Weaknesses.** **Officially recommended only for small/medium PRs — "avoid approving huge PRs from
mobile"** (Strong, S17). "Files Changed" UX: incorrect scroll position, misbehaving sticky headers,
scroll jumps; poor perf on large file trees (Strong, S17). **Notifications are event-driven not
state-driven** — clearing a notification doesn't bring it back even if the PR still needs you, so review
requests silently fall through (Strong, S17). Missing push for mentions inside PR *reviews* (Moderate).
**Lesson: a phone is for the small, urgent slice of review; design for that, and make state (not events)
drive what still needs the user.**

### Grafana IRM / dashboards on mobile — S18
**Weaknesses.** Critical-alert tone is a "**fire-alarm sound that causes panic**" (Strong, S18). Dashboards
break on iOS (missing fields, panel editing needs landscape) — desktop dashboards don't translate (Moderate).
**Lesson: pick alert sounds carefully; let users choose; never weaponize panic.**

### Notification-UX heuristics (cross-product) — S19
- A notification should answer **what happened / what it concerns / what to do** — and ideally let the user
  **decide without leaving the lock screen** (Strong heuristic, S19).
- **Alert fatigue is quantified:** ~46% of users disable push after 2–5 *irrelevant* notifications/week
  (Moderate, S19). Relevance and user control matter more than volume.
- "A single Allow-notifications toggle is no longer acceptable" — users want **granular control**, not
  on/off (Moderate, S19).
- Keep **private/sensitive content off the lock screen** unless opted in (Strong heuristic — directly
  relevant to Lancer showing code/secrets in approval pushes).

---

## User-feedback rows

| Product | Source | Date | URL | Statement (paraphrase unless quoted) | Sentiment | Category | Severity | Engagement | Evidence | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Termius | S1 | 2026-06 | apps.apple.com…id549039908 | Best UI for port-forwarding; tames a confusing task | + | onboarding/forms | low | high (top review) | Strong | praise for taming complexity |
| Termius | S1/S3 | 2026 | argsment / store | Subscription pivot resented; "should be one-time purchase" | − | pricing | high | high | Strong | recurring theme |
| Termius | S2 | 2026 | marlvel.ai | Mandatory account = top driver of instant uninstalls | − | onboarding/auth | high | med | Moderate | aggregator paraphrase |
| Blink | S5 | (HN) | news.ycombinator…21061803 | "best terminal app I could find"; mosh keeps sessions alive across networks | + | terminal/session | — | med | Strong | named users |
| Blink | S5 | (HN) | …21061803 | Input dropout on weak Wi-Fi during sudo; split-screen rough | − | terminal/reliability | med | med | Moderate | edge cases |
| Blink | S5 | (HN) | …21061803 | "$20 steep" vs "is it really, for a pro tool?" | ± | pricing | low | med | Moderate | divided |
| ShellFish | S7 | 2026-06 | macstories.net | Files.app mount of remote servers = killer feature | + | files/diff | — | high | Strong | indie press |
| ShellFish | S8 | 2026-06 | secureshellfish.app | Free tier shows ads in terminal | − | pricing | low | low | Weak | vendor-stated |
| Moshi | S4 | 2026-06 | getmoshi.app | Push "agent needs input" to phone/watch replaces polling | + | notifications/approvals | — | n/a | Moderate(PROMO) | vendor framing |
| Moshi | S4 | 2026-06 | getmoshi.app | Voice approval beats typing on phone | + | approvals | — | n/a | Moderate(PROMO) | pattern, unverified quality |
| PagerDuty | S9 | 2026-06 | support.pagerduty.com | Long-press push → Ack without opening app | + | notifications | — | n/a | Strong | feature truth |
| PagerDuty | S10 | 2026 | play.google.com | "More management functionality than appropriate — should be lean responder set" | − | navigation/scope | high | med | Strong | user quote |
| PagerDuty | S10 | 2026 | play.google.com | Missing "you're now on-call" notification; widget too big | − | notifications | low | low | Moderate | |
| Opsgenie | S11 | 2026 | capterra/play | Post-Ack popup blocks next swipe; swipe resets in bulk triage | − | approvals/list | med | med | Strong | concrete friction |
| Opsgenie | S11 | 2026 | capterra/play | 2FA re-auth required to silence an active alarm | − | auth/stress | high | med | Strong | hostile-under-stress |
| Opsgenie | S11 | 2026 | capterra/play | App force-maxes volume, never restores | − | notifications | med | med | Moderate | |
| incident.io | S12 | 2026-06 | incident.io/blog | TTA + context + 2-tap escalate + insistent-until-ack = the rubric | + | approvals/notifications | — | n/a | Strong(PROMO) | eval framework |
| Datadog | S14 | 2025-26 | apps.apple.com…id1391380318 | Alert sound can't be stopped without powering off phone | − | notifications | high | med | Strong | painful bug |
| Datadog | S14 | 2025 | store | "needs all desktop functionality / complete redesign" | − | navigation/density | med | med | Strong | density complaint |
| Working Copy | S15 | 2025 | apps.apple.com…id896694807 | Zoomable commit graph; great companion for *reviewing* code | + | diff/review | — | high | Strong | review-not-edit |
| Working Copy | S15 | 2025 | store | Features buried/hard to discover on iPhone | − | navigation/discoverability | med | med | Moderate | |
| GitHub Mobile | S16 | 2024 | github.blog | Inline comment via `+`, multi-line long-press, split/unified toggle, Jump-To | + | diff | — | n/a | Strong | feature truth |
| GitHub Mobile | S17 | 2024-26 | github.com/orgs/community | "Avoid approving huge PRs from mobile"; Files-Changed scroll/perf bugs | − | diff/scale | high | high | Strong | scale limit |
| GitHub Mobile | S17 | 2024 | community disc. | Event-driven (not state-driven) notifications → review requests silently lost | − | notifications | high | high | Strong | key insight |
| Grafana IRM | S18 | 2025 | apps.apple.com…id1669759048 | Critical-alert tone = panic-inducing fire alarm | − | notifications | med | med | Strong | sound choice |
| (general) | S19 | 2025-26 | uxmag/appbot | ~46% disable push after 2–5 irrelevant alerts/week | − | notifications/fatigue | high | n/a | Moderate | stat |

---

## Cross-cutting mobile UX patterns (the lessons)

Each tagged with the Lancer surface it informs and an evidence strength.

1. **Act from the notification, not the app.** The fastest, most-praised flow is long-press push →
   Ack/Approve without unlocking into the app (PagerDuty). Build approve/deny/hold as **notification
   actions** with the decision context (what command, which machine, diff summary) on the card itself.
   → *notifications, approvals.* **Strong** (S9, S12, S19).

2. **Minimize TTA (taps-to-decision) and show context inline.** incident.io's rubric: count taps from
   alert to action; never make the user navigate to *find* what's broken. For Lancer: the approval card
   shows the agent's proposed action + risk + relevant diff/command up front; the primary action is one
   tap. → *approvals, inbox.* **Strong** (S12).

3. **Session persistence is the terminal's whole game on mobile.** mosh-style survival across Wi-Fi↔cellular
   and device sleep is the single most-praised terminal capability (Blink); SSH-only freezing is the most
   common terminal complaint. Lancer's daemon/relay must make agent sessions feel **durable and
   auto-reconnecting**, never "your connection dropped, start over." → *terminal, multi-machine.*
   **Strong** (S4 PROMO + S5).

4. **Be a lean *responder/steerer*, not a shrunk-down console.** The loudest structural complaint across
   PagerDuty and Datadog is porting the entire desktop product to the phone. Lancer's own thesis ("steer
   and approve, not a phone IDE") is *validated by users complaining when apps violate it.* Keep the phone
   surface to: triage inbox, approve, review the decisive diff/log, light steering. → *inbox, navigation,
   whole-app IA.* **Strong** (S10, S14).

5. **Make state drive the inbox, not events.** GitHub Mobile's worst notification failure: clearing a push
   doesn't restore the "still needs you" state, so requests silently vanish. Lancer's inbox must be
   **state-driven** — an approval stays visibly pending until actually resolved, regardless of whether the
   push was dismissed. → *inbox, notifications.* **Strong** (S17).

6. **Diff/log review: zoomable, foldable, split/unified, jump-between — and scoped to the urgent slice.**
   Working Copy (zoom-out graph / zoom-in detail) and GitHub Mobile (inline `+`, multi-line long-press,
   split/unified toggle, Jump-To) show density done well; both warn the phone is for *small/urgent* review,
   not 2,000-line PRs. Give Lancer's diff/log viewer fold-by-default, change-only view, and a "this is the
   part that needs your call" highlight. → *diff, review.* **Strong** (S15, S16, S17).

7. **Reframe complexity around a familiar object.** ShellFish turned "SSH" into "files in the Files app";
   Termius turned port-forwarding into a clean form. The win comes from mapping a scary technical task onto
   a concrete, familiar mental model. For Lancer: frame governed approvals as a simple **inbox of
   decisions**, and a multi-machine view as **a list of named machines with health**, not a topology. →
   *onboarding, inbox, multi-machine.* **Moderate** (S1, S7).

8. **Notification design: choose tone carefully, give granular control, keep secrets off the lock screen.**
   Grafana's panic siren and Datadog's unstoppable sound are cautionary tales; ~46% disable push after a
   few irrelevant alerts. Lancer should: distinguish **actionable** (agent needs approval — louder,
   insistent, iOS Critical Alert opt-in) from **informational** (run finished — quiet/badge); per-category
   toggles; and **never spill code/secrets onto the lock screen** without opt-in. → *notifications,
   security.* **Strong** (S18, S14, S19) + Lancer security posture.

9. **Insistent/repeating alerts for the genuinely urgent — but only those.** "A P1 at 3 AM cannot wait":
   approvals that block a run should be repeat-until-acknowledged; routine status should not. Mis-applying
   insistence is how you train users to disable notifications. → *notifications, approvals.* **Strong/Inference**
   (S12 + S19).

10. **Voice / low-friction input for approvals.** Typing on a phone is the friction; a one-tap or spoken
    "approve / deny / hold" sidesteps it (Moshi framing). Worth prototyping for Lancer's approval and
    light-steering paths. → *approvals, terminal.* **Moderate (PROMO source)** (S4).

11. **Widgets + Live Activities for ambient status.** ShellFish (server-data widgets), Datadog (incident/
    on-call widgets), Moshi (Live Activities for long runs). A Lock-Screen/Live-Activity surface for "agent
    running / N approvals pending" gives ambient awareness without opening the app. → *notifications, inbox,
    multi-machine.* **Moderate** (S8, S13, S4).

12. **Discoverability is a real tax on dense apps.** Working Copy's depth is praised but its features are
    "buried." Lancer should keep primary actions (approve, view diff, continue) on the surface and not hide
    them behind long-press-only gestures or unlabeled affordances. → *navigation, onboarding.* **Moderate** (S15).

13. **Don't make auth fight the user mid-emergency.** Opsgenie requiring full 2FA just to silence a blaring
    alarm is the anti-pattern. Lancer's BiometricGate is correct *for sensitive actions*, but acknowledging
    /silencing or viewing an approval prompt must stay fast (Face ID, not a re-login). → *security,
    approvals.* **Strong** (S11) + Lancer fail-closed posture.

---

## Anti-patterns (avoid)

- **Porting the desktop console to the phone.** "More management functionality than appropriate" / "needs a
  complete redesign." Keep Lancer lean: triage + approve + decisive review. (Strong — S10, S14)
- **Event-driven notifications that lose state.** Dismissing a push must never make a still-pending approval
  disappear. (Strong — S17)
- **Approving/reviewing huge diffs on the phone.** Even GitHub says don't. Summarize + scope; defer the
  giant review to desktop with a deep link. (Strong — S17)
- **Unstoppable / panic alert sounds; force-maxing volume.** Datadog's un-silenceable sound, Grafana's fire
  alarm, Opsgenie's volume-max. Let users pick tone/volume; make "silence this alert" one tap. (Strong —
  S14, S18, S11)
- **Heavyweight auth in the critical moment.** Full 2FA/re-login to act on an alert. (Strong — S11)
- **Bottom popups / toasts that block the next gesture in a triage list; swipe state that resets mid-batch.**
  Breaks rapid inbox clearing. (Strong — S11)
- **Mandatory account + subscription resentment for what feels like a local tool.** Forced login drives
  instant uninstalls; recurring fees for a "should-be-local" tool breed resentment (Termius/Blink). If
  Lancer monetizes, justify the cloud/relay value clearly and keep core local steering usable. One-time/IAP
  apps (Working Copy) escape this resentment. (Strong — S1, S2, S3, S5; contrast S15)
- **Burying primary actions behind undiscoverable gestures.** (Moderate — S15)

---

## Coverage limitations

- **App Store / Google Play review pages and Reddit threads are largely login- or JS-walled** to direct
  fetch; much first-party user sentiment here is **paraphrased via search-result summaries and aggregators**
  (justuseapp, Capterra, Marlvel, G2), not read verbatim. Treat exact wording as approximate; no quotes were
  fabricated, but only HN (S5) and the fetched vendor blogs gave me literal page text.
- **Prompt, Dash, Pulse, iStat-menus-mobile** were not separately deep-dived (lower review volume / time
  budget); ShellFish/Blink/Termius cover the SSH space well, Datadog/Grafana the monitoring space.
- **Three of the most on-point sources are vendor/promo** (Moshi S4, incident.io S12, PagerDuty blog S9) —
  flagged inline. Their *frameworks* are useful; their *efficacy claims* are unverified.
- **No quantitative review-score deltas or dated rating trends** were reliably extractable without the
  walled store pages; severity/engagement columns are my **Inference** from how prominently/repeatedly a
  theme appeared, not measured counts.
- Recency: most sources are 2024–2026; SSH-app subscription complaints specifically reference the **2024
  pivot** and may have evolved since.
