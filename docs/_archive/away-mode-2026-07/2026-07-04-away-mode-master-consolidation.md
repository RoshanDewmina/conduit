# Away Mode — Master Consolidation

Prepared: 2026-07-04
Status: consolidated reference, not a decision document — pulls together every session, doc,
artifact, and piece of research produced across this brainstorm so far

> **Superseded 2026-07-05** by `docs/product/2026-07-05-lancer-feature-master-plan.md` — kept for
> historical record only. That doc is now the canonical feature source of truth.

Companion artifact: https://claude.ai/code/artifact/4c313d75-ee73-4f20-ba1c-453ef09a0b4a (six-stage
sweep, updated alongside this doc)
Companion doc: `docs/product/2026-07-04-second-opinion-away-mode-v1.md` (shorter, "traveling" doc
for direct comparison inside the Codex thread)

## 1. Executive summary

Lancer's Away Mode positioning went through four real pivots in one day (2026-07-04), across three
chained Codex sessions and one Claude Code session: generic "mobile agent client" → "governance/
policy/audit" → a radical, explicitly-scoped-as-inspiration-only widening toward "phone as primary
coding device" → the landed V1 pitch, **"Lancer is the mobile proof and shipping cockpit for agent
work."** That landed pitch is well-scoped and its feature list (22 items, narrowed by elimination)
is sound. Its *positioning*, however, doesn't fully survive a fresh competitive check: "proof" is
closer to parity with Cursor iOS and Codex-in-ChatGPT-mobile than to a blue ocean, and the one thing
that's actually hard to copy — Lancer's governance stack (hash-chained audit, policy engine, drift
detection) — nearly dropped out of the final pitch. The single open strategic call this document
argues for: **ship the core loop on iOS 26 now; don't gate the whole launch on iOS 27**, because
most of the real differentiation doesn't need it, and the parts that do (Siri View Annotations)
have a real EU/China regulatory gap. There is also a dated business fact worth surfacing prominently
here: a **2026-07-21 validation gate** (10 contacted / 5 repeat-use / 3 paying / 1 team customer)
that is roughly 2.5 weeks out as of this writing.

## 2. Provenance timeline

All times EDT, all sessions 2026-07-04 unless noted.

| Order | Session / doc | What happened |
|---|---|---|
| 1 | Codex `019f2dec-b131-7fa2-b96a-ca5dca31b095` ("Review Claude Code conversation") | Arc: generic mobile client → governance/policy/audit → owner pushback ("competitors have these points too") → **"Away Mode with proof."** Also: pricing ($25/mo solo, $99/mo team) + validation gate (10/5/3/1 by 2026-07-21), Builder.io Clips integration idea, `lancer.proof` schema concept, 11-stage capture→learn loop breakdown, verified Live Activity technical constraint (button/toggle-only, no free text), Stop Conditions detail. |
| 2 | Codex `019f2e40-bf54-7830-b4eb-be1e156cf17f` ("Continue brainstorming thread," 13:50–14:05) | Owner explicitly widened scope for inspiration-gathering only: *"developer's-only tool... phone as primary way of coding."* Separate competitor sweep (Blink Shell, Termius, Working Copy, VS Code Remote Tunnels, Replit mobile). Compiled the 24-pillar mobile-primary-cockpit inventory. |
| 3 | `docs/product/2026-07-04-lancer-mobile-primary-pivot-feature-inventory.md` | Committed output of session 2 — 24 feature pillars, explicit "do NOT build" list (no terminal-first positioning, no desktop split panes, no local iOS build tools, no hosted-cloud-as-main-story, no gamified trust scores, no automatic destructive rollback, no raw log stream default UI). |
| 4 | Codex `019f2ebf-513f-73e0-91ff-13cd74e0a412` ("Review features one by one") | Narrowed ~22 candidates one at a time (redundant-with-the-model vs genuinely app-side) to the final V1 list and the "mobile proof and shipping cockpit" pitch. |
| 5 | `docs/product/2026-07-04-v1-paid-away-workflow-spec.md` | Committed output of session 4 — the paid V1 spec: Mission Contract, Away Digest, Lock Screen Question Cards, proof objects, Return-to-Desk Packet; explicit staging recommendation to ship thin proof cards before full Proof Reel video. |
| 6 | `docs/competitive-intelligence/reports/2026-07-04-away-mode-feature-brainstorm.md` | Untracked running log written from a secondhand read of session 1 — faithful on positioning arc, but missed most of what's in row 1 above (confirmed by this session's full re-read). |
| 7 | This Claude Code session | Read session 4 in full; gave a second opinion (`2026-07-04-second-opinion-away-mode-v1.md`); ran fresh competitive + WWDC26/iOS27 research; ran a free-association "wow ideas" pass; ran the full six-stage sweep and published it as an HTML artifact; discussed iOS-27-only and desktop-companion strategy; then re-read sessions 1 and 2 in full and cloned/studied three competitor repos for this consolidation. |

## 3. Positioning corrections (the "signal check")

- **"Proof is our differentiator" is weaker than assumed.** The repo's own 37-agent competitive
  dataset (`docs/competitive-intelligence/data/*.jsonl`) never actually scored any competitor on
  video-proof/visual-diff/device-matrix dimensions — `live-web-preview` and `test-results` are
  defined in the taxonomy but have zero filled rows. A fresh check found:
  - **Codex in ChatGPT mobile** (OpenAI, shipped May 2026): reviews diffs, screenshots, test
    results, terminal summaries on the phone.
    [openai.com](https://openai.com/index/work-with-codex-from-anywhere/) ·
    [9to5Mac](https://9to5mac.com/2026/05/14/openai-brings-codex-control-to-chatgpt-for-iphone-and-android/)
  - **Cursor for iOS** (shipped, public beta): "review demos, screenshots, and logs, inspect diffs,
    leave follow-up instructions, or merge the PR directly from the app" — near-identical to the
    flagship Proof Suite pitch. [cursor.com/blog/ios-mobile-app](https://cursor.com/blog/ios-mobile-app)
  - **Factory's Slack integration** already posts short result videos to threads.
    [factory.ai/product/slack](https://factory.ai/product/slack)
- **GitHub Agent HQ** is GA on GitHub Mobile, orchestrating Anthropic/OpenAI/Google/Cognition/xAI
  under one Copilot subscription — cross-vendor, first-party, on mobile.
  [github.blog](https://github.blog/news-insights/product-news/github-copilot-app-the-agent-native-desktop-experience/)
  This sharpens, not kills, Lancer's cross-vendor claim: Lancer execs whatever CLI is installed
  locally — including vendors with no GitHub deal (OpenCode, Kimi) — with no Copilot subscription or
  GitHub-hosted-repo dependency.
- **Anthropic's own Remote Control** times out after ~10 minutes offline and runs one session at a
  time. [venturebeat.com](https://venturebeat.com/orchestration/anthropic-just-released-a-mobile-version-of-claude-code-called-remote)
  Lancer's resident daemon already survives SSH drops — an advantage that should be surfaced in the
  UI (see Stage 2 below), not left as an invisible implementation detail.
- **The governance stack is the one real moat and nearly vanished from the pitch.** Hash-chained
  audit, a real policy engine (presets/matrix/simulator), and fleet-drift detection are real,
  shipping code (`docs/competitive-intelligence/reports/current-product-baseline.md` §6) that no
  competitor researched has an equivalent of. The final "proof and shipping cockpit" one-liner
  should keep both halves: *govern and verify agent work across every vendor you use, from your
  phone, with an audit trail that survives a dispute.*

## 4. Complete feature catalog, by stage

Stages follow the committed spec's own six-step workflow (`v1-paid-away-workflow-spec.md`): **Start
Mission → Run While Away → Interrupt Only When Useful → Produce Proof → Decide → Return To Desk.**
An earlier, more granular **11-stage breakdown** existed upstream (capture → clarify → contract →
dispatch → execute → steer → prove → decide → handoff → learn, each with its own named feature:
Mission Draft, Agent Router, Away Timeline, Needs Attention Cards, Done Card, Proof Review, Review
Decision Sheet, Mission Memory) — shown here for provenance only; the 6-stage version is what's
actually committed and is used below.

Status tags: **NEW** (surfaced this pass) · **UPGRADED** (existing idea, sharper with an iOS 27
API) · **APPROVED** (agreed earlier this session — the "wow" ideas) · **CARRIED** (settled in the
Codex thread, unchanged) · **RECONSIDER** (cut too fast, worth revisiting) · **CUT** (dismissed,
reason logged).

### Stage 1 — Start Mission

*Turn messy phone input into a bounded, agent-ready contract without making mission start feel like
paperwork.*

- **CARRIED**: Away Launch Composer + lightweight contract (not a plan) · Mobile Attachments +
  Share Sheet/Universal Link intake · Whole-thread context ingestion (Factory-inspired) · Repo
  Playbook · Agent Readiness Check · Smart Default Target
- **NEW — Tap-to-Segment Bug Capture**: photograph a bug, then use Vision's tap-to-segment right in
  the composer to isolate the exact broken element before sending. *(Vision · tap-to-segment, iOS 27)*
- **NEW — On-Device Contract Drafting**: the on-device Foundation Model (multimodal as of iOS 27)
  privately drafts goal/scope/done-criteria from an attached screenshot before any vendor agent is
  dispatched. *(Foundation Models · multimodal, iOS 27)*
- **NEW — Full-Screen "Quick Mission" Widget**: launch a voice or template mission from a docked/
  StandBy phone, no unlock required. *(WidgetKit · full-screen, iOS 27)*
- **RECONSIDER — richer Stop Conditions**: settable caps beyond time/retry — "stop if tests fail
  twice," "do not exceed $3," "only modify UI files" (a scope-limiting condition, not just a
  budget). Originally proposed in `019f2dec`, only partially reflected in the current Run Budget
  scope.
- **CUT**: Evidence Inbox (original, richer version — universal adapter for Clips/Jam/Sentry/
  PostHog/Vercel-preview-comments/GitHub/Linear) — correctly cut later as redundant with the
  composer; the model already interprets messy input. Real provenance, not a contradiction: the idea
  existed, was richer, and was properly killed once the composer covered the same job.
- **CUT**: heavy Mission Draft / plan-mode clone — redundant with what Claude/Codex/Cursor already do.

### Stage 2 — Run While Away

*Track meaningful state, not token-by-token noise — and make the ambient status genuinely native
to the hardware it's running on.*

- **CARRIED**: Away Status (minimal phase/elapsed/last milestone) · Smart Default Target
- **UPGRADED — Session-Survives-Disconnect Signal**: explicitly surface "reconnected after network
  drop" / "host slept, resumed automatically" in Away Status. The daemon already does this;
  Anthropic's own Remote Control does not, past ~10 minutes offline. *(architecture advantage, no
  new API)*
- **NEW — Landscape Dynamic Island Mission Strip**: a fuller horizontal strip (phase, risk, elapsed)
  when the phone is propped landscape, using iOS 27's wider landscape Dynamic Island layout.
  *(ActivityKit · landscape Dynamic Island, iOS 27)*
- **NEW — "Read Me the Status" on-demand narration**: a manual pull, distinct from the existing
  driving-mode auto-narration. *(Foundation Models + on-device speech)*

### Stage 3 — Interrupt Only When Useful

*The phone-specific mechanics for making a question or a risky action legible and answerable in
seconds — not the interruption policy itself.*

- **CARRIED**: Question Cards + Lock Screen Question Cards · Interruption Budget · Stop and
  Snapshot · Voice Everywhere
- **NEW — Question Ladder** (from `019f2dec`, previously uncaptured): a graduated 5-level structure
  for how much a question needs — **Glance → Lock Screen chips → Evidence reveal → Typed
  instruction → Contract update** — rather than a binary "structured chip vs. open the app."
  Grounded in a verified technical constraint: Live Activities only support button/toggle App
  Intents, not free-text entry; typed replies require `UNTextInputNotificationAction` or a deep link
  into the app. Lancer already has real code seams for the lower rungs:
  `ApprovalActionIntent: LiveActivityIntent`, `LancerLiveActivityWidget.swift` — this is a
  build-on-existing-code item, not new UI to invent from scratch.
- **NEW — Siri-Answerable Question Cards**: expose the current Question Card as a Siri-referenceable
  entity via the new View Annotations API, so "Hey Siri, tell it to use the existing pattern"
  answers the card directly. *(App Intents · View Annotations, iOS 27)*
- **NEW — Multimodal Clarifying Cards**: a Question Card can carry an inline annotated image
  reasoned about on-device instead of round-tripping to the vendor agent to summarize a picture.
  *(Foundation Models · multimodal, iOS 27)*

### Stage 4 — Produce Proof

*The headline family. A run is not done because the agent says so — it is done when Lancer can
show it.*

- **CARRIED**: Proof Suite core — Proof Reel · Proof Timeline · Visual Diff Review · Device Matrix
  Proof · Auto Bug Replay
- **APPROVED — Time-Travel Scrubber**: drag a scrubber across the mission and reconstruct the real
  repo diff at that exact point — not a video, the actual file state.
- **APPROVED — Fork-From-Timestamp**: "continue from here instead" — spin up a new mission from any
  historical snapshot the scrubber exposes. Pairs directly with Time-Travel Scrubber; together these
  are the single most differentiated mechanic in the entire brainstorm — nothing in the competitor
  set models a mission as scrubbable repo state.
- **UPGRADED — Auto-Highlight Diff Frame**: on-device Vision + multimodal Foundation Models can now
  name *what* changed ("error banner removed, checkout button now green"), not just find the
  timestamp to scrub to. *(Vision + Foundation Models, iOS 27)*
- **APPROVED — Searchable Proof Transcripts**: every narrated Proof Reel gets an on-device
  transcript, searchable across every mission.
- **APPROVED — Slide-to-Compare Diff Viewer**: draggable before/after slider, the native iOS
  Photos-style comparison gesture.
- **UPGRADED — Tap-to-Isolate Annotation**: Mobile QA Annotation, upgraded — pause a proof frame,
  tap the broken element, get a precise Vision object mask instead of a hand-drawn circle.
  *(Vision · tap-to-segment, iOS 27)*
- **NEW — On-Device Proof Narration**: Lancer's own on-device model generates the narration script
  from before/after evidence directly, so narration quality is consistent across all four vendors
  instead of depending on whichever agent bothers to narrate well. *(Foundation Models · multimodal,
  iOS 27)*
- **NEW — Semantic Diff Captions**: every Proof Timeline chapter gets an automatic one-line
  on-device caption, feeding Searchable Proof Transcripts even with no spoken narration.
- **NEW — Full-Screen "Proof Ready" Widget**: a StandBy/full-screen widget tuned for the single "it's
  done" glance. *(WidgetKit · full-screen, iOS 27)*
- **NEW — Clips (agent-native) integration** (from `019f2dec`, a genuine gap in everything
  consolidated before this pass): owner reaction on seeing the announcement — *"support for this
  would be awesome," "genuinely some next level work good job."* Two phases: **Clip-In → Mission**
  (paste a Clips URL, fetch its `agent-context.json`/transcript/frames, draft a mission from it) and
  **Clip-Out** (publish Lancer's own proof reel as a Clips-compatible artifact, not a proprietary
  format). Security notes from the original session: treat Clip content as untrusted, no-store/
  redact, short-lived scoped links. Positioning line worth keeping verbatim: *"Send Lancer a Clip.
  Walk away. Get back a proof Clip showing the fix works."*
- **NEW — `lancer.proof` schema** (from `019f2dec`): make proof objects themselves a portable,
  agent-readable JSON format mirroring Clips' own schema, not just a UI artifact — pairs directly
  with the Clips integration and Searchable Proof Transcripts.
- **NEW — Frustration Signal Missions** (from `019f2dec`, genuinely new, not in any prior doc):
  rage-click/dead-click detection during Preview/QA sessions auto-proposes a mission.
- **NEW — Regression Watchlist** (from `019f2dec`, distinct from Proof Becomes Regression): proof
  proactively re-runs when a *watched flow* is touched by any future mission, rather than a single
  proof becoming a single future check.
- **RECONSIDER — Cross-Vendor Second-Agent Review**: dismissed too fast. Structurally hard for
  single-vendor competitors (Cursor, Cognition, GitHub Agent HQ's own vendor-deal model) to copy —
  Lancer needs no GitHub integration and works with vendors that have none at all (OpenCode, Kimi).
  Cheap on top of the existing four-vendor `dispatch.go`. OpenCode's own multi-provider dispatch
  pattern (one normalized interface, N vendor adapters — see §5) is a reasonable shape to converge
  `dispatch.go` toward if this gets built.
- **RECONSIDER — Proof Becomes Regression**: cut twice. One of the few features that compounds in
  value the longer the product is used.
- **CUT**: Live Activity Risk Meter, Haptic Risk Language, Live Shadow Second Opinion,
  Break-Point-Aware Nudges, Live Camera Bug Repro — all "not the best, or too much effort for
  uncertain gain" per direct owner call this session.

### Stage 5 — Decide

*The moment away-work becomes a real decision, not just a status check.*

- **CARRIED**: Away Digest (needs-you-first ordering, home screen default) · Git/PR/Merge Actions ·
  Command Cards · Changed Files Review
- **CARRIED — Run Comparison** (single-vendor A/B): re-run the same mission with one tweaked
  constraint and diff two attempts side by side — cheaper than full Multi-Agent Showdown, doesn't
  need Second-Agent Review un-deferred first. **Confirmed genuinely unshipped**: Vibe Kanban already
  has the exact data-model prerequisite (many `Workspace` attempts per `Task`) but has not built any
  side-by-side comparison UI on top of it — see §5.
- **NEW — Siri Multi-Step Decision Batch**: "Hey Siri, approve everything low-risk and ready, and
  open the checkout one" — possible only because iOS 27 Siri chains multi-step, app-specific
  actions and each digest card is a referenceable entity via View Annotations.
- **NEW — Full-Screen "Decide Now" Widget**: the single highest-priority decision, not the whole
  digest, as a full-screen glanceable widget.
- **CARRIED — "Away Mode" weekly digest**: longitudinal, not per-session — "shipped 4 fixes while
  away this week, proof pass rate 90%." The retention lever missing elsewhere.

### Stage 6 — Return to Desk

*Continuity as a system feature now, not just a data packet.*

- **CARRIED**: Return-to-desk context folded into Work Thread (correctly not standalone) · Flight
  Recorder + Work Search
- **CARRIED — True Handoff**: real Apple Continuity, not just a data summary — open the Mac and land
  on the exact scroll position/hunk being reviewed on the phone.

### Cross-cutting (not tied to one stage)

- **CARRIED**: Mobile Command Palette · Inline Mobile Git Blame · Dependency/Security Alert Intake ·
  Container/Dev-Service Status · Slack/Teams-Triggered Missions (flagged competitor gap — Factory
  already does this, Lancer has zero coverage) · Provider Capability Badges

## 5. Competitor repo findings

Three public competitor repos were cloned fresh (`research_repos/{omnara,opencode,vibe-kanban}/`,
gitignored) since the earlier 37-agent audit produced web-research dossiers, not actual source
clones. Findings below cite exact file paths so they're independently checkable.

### Omnara — dossier claims checked against real code

| Dossier claim | Verdict | Evidence |
|---|---|---|
| No true E2EE, plaintext conversations on Supabase | **CONFIRMED** | `src/shared/database/models.py:276` stores message content as a plain SQLAlchemy `Text` column; a repo-wide search for `encrypt`/`nacl`/`libsodium`/`e2ee` across `apps/mobile`, `apps/web`, `src/backend`, `src/shared`, `src/servers` returned zero hits |
| Original OSS CLI wrapper archived Feb 2026 for a closed rebuild | **CONFIRMED** | `README.md:1-14`: *"This version of Omnara is no longer maintained... We've migrated to a new voice-first coding agent platform at omnara.com built using the Claude Agent SDK"* — the legacy dashboard is frozen, the new platform isn't in this repo at all |
| Voice mic drops text on screen lock (GH #270) | **Couldn't verify the exact issue number, but architecturally plausible** | `apps/mobile/src/hooks/useAudioTranscription.ts` has no `AppState` listener at all; `app.json` declares mic/speech-recognition usage strings but no `UIBackgroundModes` audio entry — iOS would suspend recognition on screen lock with no app-level save of the in-progress transcript |
| Android push is informational only, not actionable | **CONFIRMED** | Server: `src/servers/shared/notifications.py:74-89` builds every `PushMessage` with `category=None`. Client: `apps/mobile/src/services/notifications.ts` never calls `Notifications.setNotificationCategoryAsync`; its response listener (line 407-417) only navigates to the instance screen on tap — no approve/deny action handling anywhere |

**Other notable findings, not in the original dossier:**
- **No native iOS project, no Live Activity/Dynamic Island implementation at all** — `apps/mobile`
  is a managed Expo/React Native app with no `ios/`/`android/` prebuild folders and zero
  ActivityKit code anywhere. This is a clear, confirmed gap versus Lancer, which already has
  `LiveActivityManager.swift` and `ApprovalActionIntent.swift` shipping.
- Push token registration is asynchronous/best-effort with up to 5-minute backoff — a window after
  login where push doesn't work yet.
- Voice transcription is fully OS-native (`ExpoSpeechRecognitionModule` wrapping iOS
  `SFSpeechRecognizer` / Android `SpeechRecognizer`), not a custom audio pipeline — meaning any
  lock-screen bug is inherited from the OS speech API's lifecycle, not bespoke audio-session logic.

### OpenCode — validates Lancer's own plugin integration, no changes needed

Lancer's `daemon/lancerd/opencode_plugin_install.go` was checked directly against OpenCode's real,
current plugin API — **no discrepancy found; the integration is correct as shipped:**
- `tool.execute.before` is a live, documented hook (`packages/plugin/src/index.ts:266`, part of the
  `Hooks` interface), triggered at the real call site `packages/opencode/src/session/tools.ts:106-110`
  via `yield* plugin.trigger("tool.execute.before", ...)` *before* the tool executes. Because this
  is an Effect `yield*`, a thrown error aborts execution before the tool runs — validating Lancer's
  block-via-throw design.
- Plugin discovery matches exactly: `.opencode/plugins/` (project) and `~/.config/opencode/plugins/`
  (global) per `packages/web/src/content/docs/plugins.mdx:22-23`, identical to
  `opencodePluginPath()` in `opencode_plugin_install.go:92-95`. The loader
  (`packages/opencode/src/plugin/index.ts:95-121`) accepts any named export as a plugin factory, so
  Lancer's arbitrary `LancerGate` export name needs no special convention.
- One minor, unrelated note: plugin *load* errors are logged/published as a `Session.Event.Error`
  rather than crashing OpenCode (`packages/opencode/src/plugin/index.ts:220-237`) — this is about
  load-time failures, not per-call `trigger` failures, so it doesn't affect Lancer's gating.

**Patterns worth borrowing, not gaps to fix:**
- **Multi-provider dispatch**: one file per vendor (`packages/llm/src/providers/{anthropic,openai,
  google,azure,amazon-bedrock,openrouter}.ts`), each conforming to a common `ModelFactory`/
  `Definition` shape, normalized through a single `Route`/`Endpoint`/`Protocol` abstraction
  (`packages/llm/src/route/{client,endpoint,protocol,framing}.ts`). Directly analogous to what
  Lancer needs across its 4 vendor CLIs — worth comparing `dispatch.go`'s per-vendor argv handling
  against this normalized-interface shape as a future refactor, not urgent.
- **Session continue/resume flags**: a clean three-flag model — `--continue` (most recent root
  session), `--session <id>` (resume specific), `--fork` (combinable with either to branch a copy)
  — resolved at `packages/opencode/src/cli/cmd/run.ts:147-158` and `:492-517`. Lancer's own
  continue/resume argv per vendor could converge toward this same three-way shape for consistency.

### Vibe Kanban — confirms Run Comparison / Multi-Agent Showdown are genuinely unshipped

- **Data model**: `Task` (`crates/db/src/models/task.rs`) → many `Workspace` rows
  (`crates/db/src/models/workspace.rs`, one per attempt, each with its own branch/container) → each
  `Workspace` owns `Session`s and `ExecutionProcess`es (the actual agent turns). Re-running a task
  creates a new sibling `Workspace`; `CreateFollowUpAttempt`
  (`crates/server/src/routes/sessions/mod.rs:109`) sends a follow-up into an existing session rather
  than spawning a new one.
- **No side-by-side comparison feature exists anywhere** — grepped `crates/` and `packages/` for
  comparison-related terms; every workspace page
  (`packages/web-core/src/pages/workspaces/{ChangesPanelContainer,GitPanelContainer,
  FileTreeContainer}.tsx`) renders one workspace's diff in isolation, and the sidebar
  (`WorkspacesSidebarContainer.tsx`) only lists workspaces flat, without grouping/comparing
  siblings. **This directly confirms Run Comparison and Multi-Agent Showdown remain genuinely
  differentiated feature opportunities** — the data-model prerequisite (many workspaces per task)
  already exists here, but nobody has shipped the comparative UX on top of it.
- **Worktree isolation goes further than expected**: `crates/worktree-manager/` +
  `crates/workspace-manager/src/workspace_manager.rs` support **multi-repo-per-workspace** fan-out —
  one worktree per repo under a shared workspace directory, all on the same feature branch, with
  automatic rollback if any per-repo worktree creation fails, global creation locks
  (`WORKTREE_CREATION_LOCKS`), and expiry-based cleanup (72h, or 1h if archived) via
  `Workspace::find_expired_for_cleanup` (`workspace.rs:255-309`). Worth a look if Lancer's own
  git-worktree-per-run work ever needs to span more than one repo per mission.

## 6. Competitive research appendix

- Structured dataset: `docs/competitive-intelligence/data/{competitors,features,competitor-features}.jsonl`
  — 19 competitors scored across 26 feature dimensions; `live-web-preview` and `test-results` are
  defined dimensions with zero scored rows for any competitor (a real gap in the audit itself).
- Web-research dossiers (not code): `research/_raw/{omnara,platform-anthropic-openai,platform-others,
  adjacent-apps,substitutes}.md`.
- `omnara.md` key claims: no true E2EE (founder-admitted, Launch HN), plaintext conversations on
  Supabase, original OSS CLI wrapper archived Feb 2026 for a closed-source rebuild, approval-popup
  freeze bug (GH #276), voice mic drops text on screen lock (GH #270), Android push informational
  only — being checked against real code in §5/§9.
- An unrelated but relevant find: `~/Documents/mobile-coding/research_repos/` has real clones of
  `cmux` (manaflow-ai/cmux), `ghostty` (ghostty-org/ghostty), `warp` (warpdotdev/warp) from a
  separate side project studying terminal/agent-console UX, with its own `docs/research-notes.md`
  (pane/notification UX from cmux, terminal-correctness from Ghostty, workflow/agent-session
  structure from Warp) — not Lancer's competitor set, but real prior art worth a look later.

## 7. iOS 27 / WWDC 2026 platform findings

*(The apple-docs MCP's own WWDC video archive caps at 2025 — these came from live web search
against developer.apple.com and coverage sites, flagged as such throughout.)*

- **Foundation Models**: now multimodal (image input on-device, accepts UIImage/CGImage/pixel
  buffers), a third-party model protocol (any LLM, including cloud models, can implement the same
  `LanguageModelSession` API), `PrivateCloudComputeLanguageModel` (32K context, no account/API keys,
  works on watchOS 27) — a better on-device-compression fallback tier than "use the active coding
  agent vendor." [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- **Vision**: new tap-to-segment API — isolate any object in an image by tap, drawn bounds, or
  scribble. [WWDC26 session 237](https://developer.apple.com/videos/play/wwdc2026/237/)
- **Siri / App Intents**: Siri rebuilt (Gemini-powered), true multi-step commands, new **View
  Annotations API** (map an app's own on-screen entities to something Siri can reference
  conversationally), App Intents now mandatory for any Siri integration (SiriKit deprecated).
  [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/) ·
  [Apple Newsroom](https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/)
  — **regulatory caveat: not immediately available in the EU or China.**
- **ActivityKit**: landscape Dynamic Island support (`isDynamicIslandLimitedInWidth`).
  [WWDC26 session 223](https://developer.apple.com/videos/play/wwdc2026/223/)
- **WidgetKit**: full-screen widgets (new in iOS 27); StandBy widgets refresh outside the normal
  budget.
- Repo's current deployment target is **iOS 26.0** (`project.yml`); already uses ActivityKit and
  AppIntents (`LiveActivityManager.swift`, `ApprovalActionIntent.swift`); no Foundation Models,
  Vision, or Speech framework usage yet.

## 8. Cut/deferred ideas log

Nothing silently dropped — every cut idea kept here with its reason:

| Idea | Reason cut |
|---|---|
| Live Activity Risk Meter | Not the best / too much effort for uncertain gain (owner call) |
| Haptic Risk Language | Not the best / too much effort for uncertain gain (owner call) |
| Live Shadow Second Opinion | Not the best / too much effort for uncertain gain (owner call) |
| Break-Point-Aware Nudges | Not the best / too much effort for uncertain gain (owner call) |
| Live Camera Bug Repro | Moonshot, high engineering cost for an edge case |
| Evidence Inbox (original, rich version) | Redundant with the model interpreting messy composer input directly |
| Heavy Mission Draft / plan-mode clone | Redundant with what Claude/Codex/Cursor already do |
| Big Agent Router ("send to best agent") | Premature automation; most users know which agent they want |
| Return-to-Desk Packet (as standalone feature) | Everything it held already lives in Work Thread + Flight Recorder |
| Full mobile code editor / direct patch apply | Phones are bad at sustained editing; hunk comment/send-back covers the real job |
| Broad automation builder (Zapier-style) | Narrowed to "Light Automations" — the full rule engine would compete with agent judgment |
| Deploy/Release from phone | Genuinely higher-risk and more complex; right to defer past V1 |
| Terminal Escape Hatch (V1) | **Reconsider nuance**: already built in code, just unwired from V1 nav — not "unbuilt," a surfacing decision |
| Watch support (V1) | **Reconsider nuance**: same — `PhoneWatchConnector`/`WatchApprovalTransfer` already exist |

## 9. Strategy recommendations

- **Do not gate the whole V1 launch on iOS 27.** Most of the actual differentiation (governance
  stack, cross-vendor dispatch, Time-Travel Scrubber, thin Proof Suite, Away Digest) needs no
  iOS-27 API at all. Siri View Annotations specifically has a real EU/China regulatory gap that
  would exclude entire markets if load-bearing for the whole app. The real long pole to being "the
  best app in category" is App Store readiness and the un-run validation-cycle interviews — not
  feature depth. **Correction (2026-07-04, see `docs/product/2026-07-04-lancer-whole-app-consolidation.md`
  headline correction): the biometric gate cited here as "removed" was reinstated the same day via
  commit `695d2440`, risk-tiered for high/critical approvals — this line is stale.** This also
  matches the platform-floor answer already given earlier this session ("lean into iOS 27, degrade
  gracefully" — not "iOS 27 exclusive").
  Recommended: ship the core loop on iOS 26 now; land iOS-27 enhancements (Siri cards, tap-to-segment,
  full-screen widgets) as a version-gated fast-follow the week iOS 27 goes GA, not a gate in front of
  the rest.
- **Desktop companion: keep it exactly as scoped — do not expand into a full IDE surface.** The
  developer's existing CLI coding agent already is their desktop app. GitHub's new "agent-native
  desktop app" and Cursor's desktop-first model make a second full Lancer desktop surface a losing
  fight against far better-resourced incumbents, and it contradicts the away-mode positioning
  outright. LancerMac (menu-bar pairing/host-health/diagnostics app, Phase A done 2026-06-22) is
  already the right-sized answer — True Handoff and Return-to-Desk need *something* there to land
  in, which is exactly LancerMac's existing job. Don't grow it past that.

## 10. Business/validation gate callout

**Pricing**: $25/month solo, $99/month team.
**Hard validation gate**: 10 contacted, 5 repeat-use, 3 paying, 1 team customer **by 2026-07-21**.

Today is 2026-07-04 — this deadline is roughly **2.5 weeks out**. This is distinct from the broader
design-partner-interview gate in `docs/validation-cycle-v1.md`, which as of the 2026-07-03
competitive audit had no evidence of interviews having been run. Saved to Claude's memory system
separately (`project_away_mode_validation_gate_2026-07-04.md`) so it isn't lost between sessions.

## 11. Sources

External:
- [Work with Codex from anywhere (OpenAI)](https://openai.com/index/work-with-codex-from-anywhere/)
- [OpenAI brings Codex to ChatGPT mobile (9to5Mac)](https://9to5mac.com/2026/05/14/openai-brings-codex-control-to-chatgpt-for-iphone-and-android/)
- [Cursor for iOS](https://cursor.com/blog/ios-mobile-app)
- [Factory Slack integration](https://factory.ai/product/slack)
- [GitHub Copilot app — Agent HQ](https://github.blog/news-insights/product-news/github-copilot-app-the-agent-native-desktop-experience/)
- [Anthropic Remote Control (VentureBeat)](https://venturebeat.com/orchestration/anthropic-just-released-a-mobile-version-of-claude-code-called-remote)
- [What's new in the Foundation Models framework — WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
- [What's new in image understanding — WWDC26](https://developer.apple.com/videos/play/wwdc2026/237/)
- [Live Activities essentials — WWDC26](https://developer.apple.com/videos/play/wwdc2026/223/)
- [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- [Apple Newsroom — Siri/App Intents rebuild](https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/)

Cloned competitor repos (gitignored, local-only, not part of this codebase):
- `research_repos/omnara/` — `github.com/omnara-ai/omnara`, archived Feb 2026
- `research_repos/opencode/` — `github.com/sst/opencode`
- `research_repos/vibe-kanban/` — `github.com/BloopAI/vibe-kanban`

Internal:
- `docs/product/2026-07-04-v1-paid-away-workflow-spec.md`
- `docs/product/2026-07-04-lancer-mobile-primary-pivot-feature-inventory.md`
- `docs/product/2026-07-04-second-opinion-away-mode-v1.md`
- `docs/competitive-intelligence/reports/2026-07-04-away-mode-feature-brainstorm.md`
- `docs/competitive-intelligence/reports/current-product-baseline.md`
- `docs/competitive-intelligence/data/{competitors,features,competitor-features}.jsonl`
- `research/_raw/{omnara,platform-anthropic-openai,platform-others,adjacent-apps,substitutes}.md`
- Codex sessions: `019f2dec-b131-7fa2-b96a-ca5dca31b095`, `019f2e40-bf54-7830-b4eb-be1e156cf17f`,
  `019f2ebf-513f-73e0-91ff-13cd74e0a412`

## 12. Open questions / suggested next step

1. Bring this doc + the updated artifact back to the Codex thread (`019f2ebf…`) for a direct
   side-by-side comparison — this was the original ask that kicked off this whole session.
   Everything is written to travel: sourced, dated, and cross-referenced.
2. Decide whether Clips integration and the `lancer.proof` schema (both new to this consolidation)
   get scoped into V1 or deferred alongside the other Stage-4 "reconsider" items — they weren't
   evaluated by the owner directly yet, only by the earlier Codex session that proposed them.
3. If moving toward implementation, the next step is `writing-plans` for whichever slice gets
   picked first — likely Time-Travel Scrubber + Fork-From-Timestamp given the priority ranking
   already established, or Mission Contract/Away Digest if sequencing by the committed spec's own
   "ship the skeleton first" recommendation.
