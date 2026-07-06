# Second Opinion — Away Mode V1 (Codex thread `019f2ebf-513f-73e0-91ff-13cd74e0a412`)

Prepared: 2026-07-04
Status: second opinion, not a decision — for comparison against the Codex thread's conclusion
Source reviewed: Codex session "Review features one by one" (`019f2ebf-513f-73e0-91ff-13cd74e0a412`),
which continued from `019f2dec-b131-7fa2-b96a-ca5dca31b095` and produced
`docs/product/2026-07-04-v1-paid-away-workflow-spec.md`.

> **Superseded 2026-07-05** by `docs/product/2026-07-05-lancer-feature-master-plan.md` — kept for
> historical record only. Its core pushback (proof alone isn't the differentiator; governance is)
> is carried forward as a first-class principle there.

**For the full consolidated picture** (all 3 chained Codex sessions, competitor repo findings, the
full six-stage sweep, business/validation gate) see
`docs/product/2026-07-04-away-mode-master-consolidation.md`. This doc stays short and focused for
direct comparison inside the Codex thread; that one is the long-form reference.

## Where I agree with Codex

The elimination method was good discipline and I'd keep the calls:

- Killing **Evidence Inbox**, **Mission Draft/plan-mode clone**, **Return-to-Desk Packet as a
  separate feature**, **Team/Client Proof Layer for V1**, **Deploy/Release for V1**, **Terminal for
  V1** — all correctly identified as either redundant with what the underlying agent/model already
  does, or scope creep the V1 loop doesn't need yet.
- Keeping **Away Launch Contract (thin, not a plan)**, **Question Cards**, **Away Digest as Home**,
  **Interruption Budget**, **Stop-and-Snapshot**, **Repo Playbook**, **Agent Readiness Check**,
  **Flight Recorder** — these are genuinely app-side value that no CLI agent coordinates on its own
  across multiple runs/hosts/lock-screen state. Good calls, still hold up.
- **Mobile QA Annotation** (pause proof at a frame/timestamp, mark it, dictate, send back) is the
  single most differentiated idea in the whole session. Nothing in the competitor set below does
  this. Keep it as a headline feature, not a "v2 if time" item.

## Where I'd push back

### 1. The "proof is our differentiator because competitors only do basic remote control" claim needs re-checking — I checked it just now, and it's weaker than the thread assumed

The Codex thread's competitive read (deep in the transcript) was a single research pass done
mid-brainstorm, reading local docs + a handful of Apple/WWDC links, and concluded: "basic remote
control is now table stakes... the differentiator should be proof and shipping, not control."

Two problems with that conclusion as stated:

**(a) The repo's own structured competitive dataset never actually measured this.** I checked
`docs/competitive-intelligence/data/{features,competitor-features}.jsonl` — the 37-agent,
19-competitor audit from 2026-07-03. The feature taxonomy defines dimensions like "diffs",
"live-web-preview", "test-results" — but `live-web-preview` and `test-results` have **zero scored
rows for any competitor**, and "proof/video/visual-diff/device-matrix" were never defined as
dimensions at all. So when the Codex thread says "the competitor docs say proof is the gap," that
claim was never actually tested with the same rigor as the rest of that audit. It's an assumption
carried over from an earlier, differently-scoped research pass — not a verified finding.

**(b) I ran a fresh check just now (live web search, 2026-07-04), and the gap is smaller than
assumed:**

- **Codex in ChatGPT mobile** (OpenAI, shipped May 2026, all ChatGPT plans including Free, iOS +
  Android): the phone already receives "terminal logs, screenshots, diffs, test results" and shows
  "compressed diffs, screenshot previews of UI changes, and terminal output summaries" for review.
  [Work with Codex from anywhere](https://openai.com/index/work-with-codex-from-anywhere/),
  [9to5Mac](https://9to5mac.com/2026/05/14/openai-brings-codex-control-to-chatgpt-for-iphone-and-android/)
- **Cursor for iOS** (public beta, paid plans, shipped): "Cloud agents produce demos, screenshots,
  and logs that make it easy to validate their work. When an agent is done, you can review these
  generated artifacts, inspect diffs, leave follow-up instructions, **or merge the PR directly from
  the app**." Plus Live Activities on lock screen and push when an agent needs input or is done.
  [Cursor iOS blog](https://cursor.com/blog/ios-mobile-app),
  [Cursor iOS changelog](https://cursor.com/changelog/ios-mobile-app)

That is close to a bullet-for-bullet match with the "Proof Suite + Git/PR/Merge from phone"
flagship the Codex thread spent the second half of the session building toward. Two first-party
incumbents with far more distribution than Lancer already ship "review artifacts → diff → merge
from phone." The unconfirmed part is whether Cursor's "demos" are actual video (I fetched the
announcement directly and it doesn't specify format) — so Lancer may still have room on
**video-specific, narrated, annotatable proof** and **device-matrix proof** specifically. But
"proof exists, you can review it and merge" as a category claim is not green field. It's parity
work now, not differentiation.

**Recommendation:** don't market Proof Suite (thin version: test/diff/screenshot cards + merge) as
the headline reason to use Lancer. It's necessary — skipping it makes Lancer worse than Cursor/Codex
mobile, which would be fatal — but it isn't sufficient to win on. The things that still look
genuinely uncontested after this check are narrower: **Mobile QA Annotation**, **Device Matrix
Proof**, and **cross-vendor Second-Agent Review**.

### 2. Cross-vendor Second-Agent Review got skipped too fast

The owner skipped this ("skip this for now") and Codex agreed without pushing back. I'd push back:
this is one of the few things in the entire feature list that is **structurally impossible** for
Cursor, Codex-mobile, Factory, or Omnara to do as well — they're single-vendor or
single-orchestration-model by construction. Lancer already dispatches to 4 vendors
(`daemon/lancerd/dispatch.go`). "Have Claude's fix independently checked by Codex, one tap" is cheap
to build (it's a second `dispatch` call against the same mission contract) and is a real moat, not
a nice-to-have. I'd move it back into the V1 discussion, at least as an action on the Proof Suite
card, before dropping it.

### 3. The two committed docs already disagree with each other on Proof Reel staging — worth resolving explicitly

`docs/product/2026-07-04-v1-paid-away-workflow-spec.md` (produced earlier from the same overall
effort) recommends: *"Hold full Proof Reel video capture until the proof object and digest loop
work... paying users need trust and repeatability before they need polish."* Proof Reel is Slice 4
of 5, after the plain proof object ships.

This Codex session later reached a different sequencing (transcript ~line 564–618): make the full
Proof Suite — including Device Matrix Proof and Auto Bug Replay — **the V1 flagship**, "the
product's wow feature," staged in depth but present from the start.

Given finding #1 above (Cursor/Codex-mobile already ship the plain diff/screenshot/merge loop), I'd
side with the earlier spec's sequencing: ship the thin proof object + digest + merge loop first,
prove it's reliable, and add video/device-matrix/annotation depth once the base loop is trustworthy
— rather than committing V1 scope to the polished version of a feature two funded incumbents already
have a version of.

### 4. The governance stack (the one thing that's actually hard to copy) nearly disappeared from the pitch

The 2026-07-03 structured audit's own conclusion (`docs/competitive-intelligence/reports/current-product-baseline.md`
§6) was: hash-chained audit, real policy engine with presets/matrix/simulator, and fleet-drift
detection are Lancer's one wedge that's real code today and structurally hard to copy quickly. This
Codex session's final pitch line — *"Lancer is the mobile proof and shipping cockpit for agent
work"* — doesn't mention governance at all. That's a swing from one narrow pitch (governance-only,
which the owner already correctly rejected earlier as "too abstract") to another narrow pitch
(proof-only, which this check shows is less exclusive than assumed), instead of stating the
combination: **govern and verify agent work across every vendor you use, from your phone, with an
audit trail that survives a dispute.** Proof answers "did it work"; governance answers "was it safe
and can I prove that to someone else afterward." Cursor and Codex-mobile answer the first question
now. Neither has a policy engine, hash-chained audit, or cross-vendor coverage. I'd keep both in
the one-liner, not drop one for the other.

## Bottom line

The V1 feature list this session converged on is basically right and well-scoped — I would ship
almost exactly that list. The part I'd change before committing is the **positioning**, not the
feature set: don't lead with "proof" as if it's uncontested (it isn't, per the fresh check above),
don't drop cross-vendor second-opinion review, don't drop governance from the one-liner, and
resolve the Proof Reel staging conflict between the two existing docs in favor of thin-first.

## Addendum (2026-07-04) — features dismissed too fast, and new ideas

### Dismissed features worth reconsidering

- **Second-Agent Review / cross-vendor verification** — skipped in one line with no pushback.
  Structurally hard for single-vendor competitors to copy, and cheap to build on top of the
  existing 4-vendor `dispatch.go`. See the correction below on how sharp this claim can still be.
- **Terminal Escape Hatch** — skipped "for V1" as if it needs building. It doesn't: the SSH/PTY
  terminal engine already exists and works in code (`SessionFeature/TerminalEngine`), just unwired
  from V1 nav by an earlier decision. Skipping the *feature* is fine; treating it as unbuilt is not.
- **Watch/wearable support** — same shape: `PhoneWatchConnector`/`WatchApprovalTransfer` already
  push live state with stop/deny wired. Surfacing what exists is a near-zero-cost win, not a build.
- **Proof Becomes Regression** — cut twice. It's one of the few features that makes the product
  compound in value the longer it's used (a growing regression suite per repo) — a retention/data
  mechanic, not just a nice-to-have. Fine to leave out of the V1 launch surface; don't let it drop
  off the roadmap entirely.
- **Multi-Agent Showdown** — deferred only because Second-Agent Review was deferred; resurfaces if
  that one does.

### Correction to the "cross-vendor is our moat" claim above

Fresh research (2026-07-04) found **GitHub Agent HQ** is GA on GitHub Mobile and explicitly
orchestrates Anthropic, OpenAI, Google, Cognition, and xAI agents under one Copilot subscription —
cross-vendor, on mobile, first-party. [GitHub Copilot app](https://github.blog/news-insights/product-news/github-copilot-app-the-agent-native-desktop-experience/),
[Copilot agents](https://github.com/features/copilot/agents). This doesn't kill Second-Agent Review,
but it sharpens what's actually defensible: Agent HQ requires each vendor to have a GitHub
integration deal and routes through GitHub's control plane / a Copilot subscription. Lancer execs
whatever CLI is literally installed on the user's own box — including vendors with no GitHub deal
(OpenCode, Kimi) — with no dependency on the repo living on GitHub or a Copilot subscription. State
the claim that precisely, not as "nobody else does cross-vendor."

One architectural advantage worth turning into a user-facing signal: Anthropic's own Remote Control
times out after ~10 minutes offline and runs only one session at a time
([VentureBeat](https://venturebeat.com/orchestration/anthropic-just-released-a-mobile-version-of-claude-code-called-remote)).
Lancer's resident daemon already survives SSH drops — surface "session survived a host sleep/network
drop" explicitly in Away Status instead of leaving it as an invisible architectural detail.

### New feature ideas — desktop workflows not yet covered

1. **Mobile Command Palette** — Cmd+K-style global fuzzy search/action launcher (jump to a mission,
   run a command, open a repo from anywhere). Distinct from "Work Search," which only searches
   Flight Recorder history, not live actions.
2. **Inline mobile git blame** — tap a diff line, get "added 3 weeks ago, fixing X" instead of raw
   `git blame`, since there's no desktop git tooling to fall back on mid-review.
3. **Run Comparison (single-vendor A/B)** — re-run the same mission with one tweaked constraint and
   diff two attempts side by side. Cheaper than Multi-Agent Showdown; doesn't need Second-Agent
   Review to be un-deferred first.
4. **Dependency/security alert intake** — Dependabot/Snyk findings auto-become mission candidates
   ("3 high-severity deps flagged, fix while away") instead of only reactive paste/share-sheet intake.
5. **Container/dev-service status** — Docker Compose service up/down shown in Away Status, with
   restart-service Command Cards. Extends Preview Cockpit/Command Cards to the app's dependencies,
   not just the app itself.
6. **"Away Mode" weekly digest** — longitudinal, not per-session: "shipped 4 fixes while away this
   week, proof pass rate 90%." Away Digest answers "what do I decide now"; this answers "is this
   paying off" — the retention lever missing from both existing feature docs.

### New ideas — competitor gaps found in this pass

7. **Slack/Teams-triggered missions** — Factory already supports `@`-mentioning it in a channel to
   kick off/check a task, posting results back to the thread
   ([Factory Slack](https://factory.ai/product/slack)). Lancer has zero Slack/Teams coverage today;
   flagging as a real V2 gap, reportedly winning Factory agency/team deals.
8. **Whole-thread context ingestion** — Factory's "Context-Aware Thread Intelligence" understands a
   full incident discussion, not one message. Fold into Universal Link Intake / Mission Contract
   parsing: accept a whole pasted Slack/Linear thread as one input, not just a single screenshot.

### New ideas — Apple-platform-native (mobile-adapted, not desktop-shrunken)

9. **Siri / App Intents voice query** — "Hey Siri, what's the status of the checkout fix?" as a
   hands-free status *query*, distinct from "Voice Everywhere" (dictating *input*).
10. **StandBy mode dashboard** — phone docked overnight shows a nightstand-style live Away Digest.
    No competitor here has a reason to build this; none are positioned around "leave your desk and
    your phone both."
11. **Interactive Home Screen widget** (not just Live Activity) — act on a "3 need you" badge
    straight from the widget, without opening the app.
12. **True Handoff** (Apple Continuity, not just a data packet) — open the Mac and land on the exact
    scroll position/hunk being reviewed on the phone, deeper than the current data-only
    Return-to-Desk concept.

Priority pick if only a few get added: **#3 (Run Comparison), #6 (weekly digest), #9 (Siri query),
#10 (StandBy dashboard)** — cheap, genuinely mobile-native, and not something any competitor
researched here is doing.

## Full stage sweep (2026-07-04) — final report

Consolidated everything above into a full walk of the six away-mode stages from the committed
spec (Start Mission → Run While Away → Interrupt Only When Useful → Produce Proof → Decide →
Return To Desk), this time checking each stage against **verified iOS 27 / WWDC 2026 APIs** rather
than assumption. Full visual report:
https://claude.ai/code/artifact/4c313d75-ee73-4f20-ba1c-453ef09a0b4a

Headline findings not covered above:

- **Foundation Models (iOS 27)** is now genuinely multimodal (image input on-device), supports a
  third-party model protocol (any LLM can implement the same `LanguageModelSession` API), and adds
  `PrivateCloudComputeLanguageModel` — a 32K-context Apple-hosted fallback with no account/API keys,
  even on watchOS 27. This changes the on-device-compression fallback chain from two tiers to
  three: on-device model → PrivateCloudComputeLanguageModel → active coding agent vendor.
- **Vision's new tap-to-segment API** upgrades Mobile QA Annotation from a hand-drawn circle to a
  precise object mask, and (combined with multimodal Foundation Models) upgrades Auto-Highlight
  Diff Frame to name *what* changed, not just *when*.
- **Siri was rebuilt (Gemini-powered) with a new View Annotations API** that lets an app expose its
  own on-screen entities to Siri conversationally, plus true multi-step commands. This makes two
  new ideas credible that weren't before: **Siri-Answerable Question Cards** (answer a Question
  Card by voice, referencing what's on screen) and **Siri Multi-Step Decision Batch** ("approve
  everything low-risk and ready, and open the checkout one").
- **WidgetKit full-screen widgets (new in iOS 27)** enable a StandBy/full-screen "Proof Ready" and
  "Decide Now" widget, distinct from a general digest widget.
- Explicitly cut this pass (recorded, not silently dropped): Live Activity Risk Meter, Haptic Risk
  Language, Live Shadow Second Opinion, Break-Point-Aware Nudges, Live Camera Bug Repro — all "not
  the best, or too much effort for uncertain gain" per direct owner call.
- Reiterated for revisiting: **Cross-Vendor Second-Agent Review** and **Proof Becomes Regression**,
  both cut fast in the Codex thread, both still look worth a second look given the competitive
  findings above.

Priority order across the *entire* brainstorm, not just this pass: Time-Travel Scrubber +
Fork-From-Timestamp, Tap-to-Isolate Annotation, Siri-Answerable Question Cards, Auto-Highlight Diff
Frame + Semantic Diff Captions, Session-Survives-Disconnect Signal.
