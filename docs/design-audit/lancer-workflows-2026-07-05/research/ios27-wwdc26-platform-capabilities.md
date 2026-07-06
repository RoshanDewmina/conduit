# iOS 27 / WWDC 2026 Platform Capabilities — Reference Doc

Prepared: 2026-07-05
Status: independent research pass, verified against primary Apple sources where the apple-docs
MCP and developer.apple.com had live iOS 27 beta content; supplemented with credible tech press
where Apple's own docs were thin or where the apple-docs MCP tool has no indexed WWDC26 video
transcripts (its own video-transcript search returns zero hits for 2026 content — only
`search_framework_symbols` / `get_apple_doc_content` against live `developer.apple.com` framework
reference pages had real iOS 27 material; WebFetch against WWDC26 video pages was the main source
for session transcripts).

## How to use this doc

When the team is discussing a feature or a design problem and someone asks **"could iOS do this
for us?"** — check here first before assuming. This doc is organized by API/framework area, one
section per area, each with: what's actually new (stated precisely, not marketing language), exact
capabilities/limits, a cited source per claim, and a clearly-separated "Lancer opportunity" note.

**Apple ships changes fast during beta cycles.** iOS 27 is still in beta as of this writing
(2026-07-05, WWDC was 2026-06-08). If a claim here turns out to be stale by the time it's acted
on, **note the discrepancy in this file rather than silently trusting it** — don't assume the doc
is still current without a quick re-check against the cited source, especially for anything with a
specific number (context window sizes, token limits, device requirements) or a beta-labeled API
that could still change shape before GA.

Known internal tension already flagged in prior research (`docs/product/2026-07-04-away-mode-master-consolidation.md`
§9): Lancer's own repo currently targets iOS 26 as its deployment floor, with iOS 27 APIs treated as
a version-gated fast-follow, not a launch gate. Nothing in this pass changes that recommendation —
if anything it reinforces it, given the EU/China Siri gaps and the number of iOS-27/watchOS-27-only
or Beta-labeled APIs below.

---

## 1. Siri rebuild, App Schemas, and the View Annotations API

### What's new, precisely

- **Siri was rebuilt** for iOS 27 around **App Intents + a new App Schemas layer**, not SiriKit.
  App Schemas are "predefined, Siri-specific structures that specialize App Intents" — they define
  the kinds of actions Siri understands, the expected parameter shape, and the natural-language
  mapping, grouped into domains (Messages, Photos, Mail, Calendar, etc.) that act as a contract
  between an app and Siri. Once entities conform to a schema, Siri already knows how to reason
  about them with no custom NL handling.
  [WWDC26 Session 240 — Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/)
- **View Annotations API** (new): a SwiftUI view modifier, `.appEntityIdentifier(EntityIdentifier(for:identifier:))`,
  that maps an on-screen view (e.g. a row in a `List`) to an App Entity, so Siri can resolve
  contextual references like "this message" / "that conversation" to the specific thing on screen.
  Apple's own guidance: use **View Annotations** when *multiple* meaningful items are visible at
  once (a list, a conversation); use the older **`NSUserActivity`** (now paired with a companion
  `.userActivity(with:)` modifier) when there's *one* primary thing on screen (a document, a
  message compose view). Both were demonstrated together in the CometCal code-along: list rows get
  `.appEntityIdentifier`, the detail/compose view gets `.userActivity`.
  [WWDC26 Session 240](https://developer.apple.com/videos/play/wwdc2026/240/) ·
  [WWDC26 Session 344 — Code-along: Make your app available to Siri](https://developer.apple.com/videos/play/wwdc2026/344/)
- **Multi-step / cross-app commands** are enabled by combining on-screen awareness (View
  Annotations/`NSUserActivity`) with a new **content transfer** mechanism (`Transferable` +
  `IntentValueRepresentation` / `IntentValueQuery`) that lets structured content move between apps
  — Apple's example: "Email my wife this reply from Bubbles" or "Text my wife her plane ticket."
  This is genuinely new — it's not just intent chaining, it's typed content handoff between two
  different apps' entity graphs.
  [WWDC26 Session 240](https://developer.apple.com/videos/play/wwdc2026/240/)
- **App Intents Testing framework** (new): validates an app's entire Siri/Shortcuts/Spotlight
  integration through real system pathways, without UI automation — `AppIntentsTesting` for
  isolated business-logic tests, plus system-level validation via Shortcuts/Spotlight/Siri.
  [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/) ·
  [WWDC26 Session 344](https://developer.apple.com/videos/play/wwdc2026/344/)
- **SiriKit deprecation status: not addressed in either session watched.** Neither WWDC26 Session
  240 nor 344 mentions SiriKit deprecation explicitly — both talk exclusively about App Intents as
  the (already-established, not brand new) mechanism. **This contradicts the prior research's claim
  that "App Intents is now mandatory, SiriKit deprecated" as a clean, sourced fact** — I could not
  find a primary-source statement to that effect in the sessions fetched. Treat that specific claim
  as unverified/likely-directional-truth-but-not-confirmed until a session or doc page states it
  outright.
- **Regulatory gaps are real and specific, not vague.** Apple confirmed at WWDC 2026 (2026-06-08)
  that the new Siri AI/Apple Intelligence will **not ship on iOS 27 or iPadOS 27 in the EU**, citing
  DMA (Digital Markets Act) interoperability requirements the EU rejected Apple's proposed
  workarounds for (a "Trusted System Agent" framework, phased rollout) — **no timeline given** for
  when it will arrive. Notably the block is **iOS/iPadOS/Watch-specific**: macOS 27 and visionOS 27
  in the EU are unaffected.
  [Apple Newsroom — Due to DMA, Siri AI delayed in EU for iOS 27 and iPadOS 27](https://www.apple.com/newsroom/2026/06/due-to-dma-siri-ai-delayed-in-eu-for-ios-27-and-ipados-27/) ·
  [MacRumors — New Siri AI features won't be available in EU](https://www.macrumors.com/2026/06/08/siri-ai-not-available-eu-china/)
  China has a **separate, independent gap**: Chinese law requires local regulatory approval of
  generative AI models before public release, and Apple has not completed that process (and may
  need a local model partner, as it did for the original Apple Intelligence China launch).
  [TechNode — Apple delays AI-powered Siri in EU and China](https://technode.com/2026/06/10/apple-delays-ai-powered-siri-in-2026/06/10/apple-delays-ai-powered-siri-in-eu-and-china-over-regulatory-hurdles/)
- **Real-world third-party View Annotations examples:** none found beyond Apple's own CometCal
  sample project shown in the code-along session — this is expected, since iOS 27 is still in beta
  and third-party apps haven't shipped View Annotations integrations publicly yet. Treat "does this
  actually work well in a shipped third-party app" as an open question, not yet answerable.

### Lancer opportunity (speculative — kept separate from the facts above)

Question Cards and Work Thread rows are exactly the "multiple meaningful items visible at once"
case View Annotations is built for — each pending approval/question could get an
`.appEntityIdentifier` so "Hey Siri, tell it to use the existing pattern" or "approve the low-risk
one" resolves to a specific card, not a generic app launch. The content-transfer mechanism could
plausibly support a version of "send this diff to Messages" without Lancer building its own share
extension. But given the confirmed EU/China gap is real and currently open-ended, and SiriKit
deprecation/App-Intents-mandatory status is *unconfirmed* rather than a settled fact, this
strengthens rather than weakens the existing "don't gate V1 on iOS 27 Siri features" call already
on record.

---

## 2. Live Activities / Dynamic Island (ActivityKit)

### What's new, precisely

- **Landscape Dynamic Island layout**: new environment value **`isDynamicIslandLimitedInWidth`**.
  When the Dynamic Island is width-constrained (landscape orientation), a Live Activity's
  compact/minimal views are now shown in *both* portrait and landscape (previously landscape hid
  them); apps read this environment value to swap to a narrower layout (e.g. an icon-only view)
  when true.
  [WWDC26 Session 223 — Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/)
- **StandBy rendering control**: new environment value **`showsWidgetContainerBackground`** plus
  `.activityBackgroundTint(_:)` — StandBy renders the Lock Screen Live Activity view scaled to
  ~200%, so apps use these to swap in a StandBy-appropriate background/tint distinct from the Lock
  Screen one.
- **New "small" Activity family for Apple Watch and CarPlay**: new environment value
  `activityFamily` plus `.supplementalActivityFamilies([.small])` on `ActivityConfiguration` — a
  Live Activity can now declare a genuinely different, smaller view for watch/CarPlay display
  rather than reusing (or being excluded from) the phone layout.
- **Interaction model is unchanged and confirmed: button/toggle only, no free-form text.** A Live
  Activity's interactive elements are `LiveActivityIntent`-conforming App Intents with typed
  parameters (e.g. `orderID: String`, `isPositive: Bool`) triggered by `Button(intent:)` —
  **there is still no mechanism for typed/free-form text entry inside a Live Activity.** This
  matches and reconfirms the prior research's finding; it is not new in iOS 27, and iOS 27 does not
  change it.
  [WWDC26 Session 223](https://developer.apple.com/videos/play/wwdc2026/223/)
- Push-to-start / broadcast-channel vs per-device push-token update strategies exist as before
  (broadcast channel for large concurrent audiences, push token for targeted per-device updates) —
  no breaking changes surfaced in this session.

### Lancer opportunity

The landscape Dynamic Island change is a direct, low-effort win for a "propped up on a desk while
away" mission strip — `isDynamicIslandLimitedInWidth` gives a clean signal to show a fuller
phase/risk/elapsed layout when *not* width-constrained (i.e., in the wider landscape state) rather
than guessing from orientation alone. The confirmed button-only interaction model is the load-
bearing constraint behind the already-designed "Question Ladder" (Glance → Lock Screen chips →
Evidence reveal → Typed instruction → Contract update) — this pass found nothing that changes that
design decision; typed replies still require a notification action or an app deep link, not a Live
Activity. The new small Activity family is relevant only if/when Watch support is unfrozen — it
would let `LancerLiveActivityWidget` degrade gracefully to something Watch-appropriate instead of
either omitting Watch or forcing the phone layout onto a small screen.

---

## 3. WidgetKit — correcting the "full-screen widgets" claim

### What's actually new, precisely

**The prior research's claim that "WidgetKit gained full-screen widgets" in iOS 27 does not survive
verification as stated — this is the one significant correction from this pass.**

- The real, confirmed WidgetKit addition in iOS 27 is a **new widget family**,
  **`.systemExtraLargePortrait`**, added via `.supportedFamilies([.systemMedium, .systemExtraLargePortrait])`
  on a `Widget`'s `StaticConfiguration`. It was *not* invented for iOS 27 — it shipped first on
  visionOS 26 and is now brought to **macOS, iOS, and iPadOS 27**. It is a larger widget size (a
  bigger, portrait-oriented widget users can place like any other widget), not a distinct
  "full-screen widget" placement or API surface.
  [WWDC26 Session 277 — WidgetKit foundations](https://developer.apple.com/videos/play/wwdc2026/277/)
- **No dedicated Apple developer-doc/session content differentiates "full-screen widgets" from
  StandBy widgets or Home Screen widgets** — I could not find that distinction anywhere in Apple's
  own material. What tech press is calling "full-screen, transparent widgets" appears to be
  describing **Lock Screen customization changes** (a new compact clock layout that shrinks the
  clock so widgets/date get more room, plus letting the "Now Playing" widget be dismissed from the
  Lock Screen) rather than a new widget *type*. Treat "full-screen widget" as **not a real, distinct
  API** until proven otherwise — it looks like marketing/press shorthand for "the extra-large-portrait
  family now on iPhone" plus unrelated Lock Screen layout tweaks.
  [MacRumors Forums — iOS 27 brings these five new features to your iPhone Lock Screen](https://forums.macrumors.com/threads/ios-27-brings-these-five-new-features-to-your-iphone-lock-screen.2483731/) ·
  [WWDC26 Session 277](https://developer.apple.com/videos/play/wwdc2026/277/)
- **Refresh budget**: unchanged in kind — each widget gets a system-managed update budget, "heavily
  influenced by users' viewing habits," foreground-triggered reloads may be throttled, and Apple's
  standing advice (provide multiple timeline entries, do a final reload on backgrounding) is
  reiterated, not changed. A **WidgetKit developer mode** exists to lift reload-budget constraints
  during development/testing.
- **Interactivity model unchanged**: widget views are archived/rendered by the system (the app's
  code is not running while a widget is on screen); buttons/toggles execute an App Intent on
  interaction — same model as before, no new interaction primitive.
  [WWDC26 Session 277](https://developer.apple.com/videos/play/wwdc2026/277/)

### Lancer opportunity

The real capability — `.systemExtraLargePortrait` — is still useful for the "Decide Now" / "Proof
Ready" glance ideas already on the roadmap: a bigger, richer widget than a standard Home Screen tile
for the single highest-priority Away Digest item, reusing the same underlying data as a smaller
widget (Apple's own example does exactly this: same data source, bigger presentation). It is not,
however, a Lock-Screen-replacing "full-screen" surface, so any spec written against the earlier
"full-screen widget" framing should be corrected to target this specific family and its actual
placement rules (Home Screen / equivalent large-widget surfaces), not an assumed always-on
lock-screen-covering canvas.

---

## 4. Foundation Models framework

### What's new, precisely

**Multimodal input**
- The on-device model gained image input: `Attachment(UIImage(...))` (also `NSImage`, `CGImage`,
  Core Image types, `CVPixelBuffer`, file URLs) can be inserted directly into a prompt alongside
  text, any size/aspect ratio (larger images cost more tokens/latency). Vision-backed tools
  (`OCRTool`, `BarcodeReaderTool`) are available for the model to call directly during generation.
  [WWDC26 Session 241 — What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)

**Context window — exact numbers, with a caveat**
- On-device `SystemLanguageModel`: **`contextSize` prints `8192`** in the Session 241 code
  walkthrough. One WebFetch summary separately characterized this as "4K on iOS 26.0, 8K on newer
  devices with iOS 27.0" — **this is a discrepancy I could not fully resolve from a single
  authoritative source; verify the exact number against the live `SystemLanguageModel.contextSize`
  property at implementation time rather than trusting either number blind.**
  [WWDC26 Session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- `PrivateCloudComputeLanguageModel`: **32,000 tokens (32768)** context window — confirmed
  consistently across two independent session fetches (Sessions 241 and 319).
- New token-counting API: `model.tokenCount(for:)` (async), and a `response.usage` struct exposing
  input/output/cached/reasoning token counts — new in iOS 26.4+ per the Session 241 transcript
  (i.e., predates iOS 27 slightly, still worth knowing as current-state).

**Third-party model provider protocol — this is real and specific, not vague**
- New protocols: **`LanguageModel`** (declares `capabilities` and `executorConfiguration`) and
  **`LanguageModelExecutor`** (`init(configuration:)`, `prewarm(model:transcript:)`,
  `respond(to:model:streamingInto:)`). A provider implements both; app code then does
  `LanguageModelSession(model: AnthropicLanguageModel(...))` instead of the default
  `SystemLanguageModel()` — **the rest of the calling code (session, prompts, structured output,
  tool calling) is unchanged**, per Apple's stated design goal.
  [WWDC26 Session 339 — Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/)
- **Confirmed real providers, not hypothetical**: Anthropic is publishing a Swift package
  implementing this protocol for Claude; Google ships Gemini through the Firebase Apple SDK using
  the same protocol.
  [Firebase Blog — Gemini in Apple's Foundation Models framework](https://firebase.blog/posts/2026/06/apple-foundation-models-gemini/) ·
  [WWDC26 Session 339](https://developer.apple.com/videos/play/wwdc2026/339/)
- **Routing**: cloud model calls from a third-party `LanguageModelExecutor` go **directly to that
  provider's own infrastructure**, not through any Apple relay/proxy — the package author
  implements HTTP calls to their own service inside `respond()`.
- **Auth guidance Apple gives providers**: avoid plain API-key-string initializers; prefer a
  token-provider/sign-in pattern, Keychain-persisted tokens, and **App Attest** to verify the
  calling device/build before sending prompts to a cloud service.
- Error handling is unified across providers via `LanguageModelError` cases:
  `contextSizeExceeded`, `rateLimited`, `refusal`, `guardrailViolation`, `unsupportedCapability`,
  `unsupportedTranscriptContent`, `unsupportedGenerationGuide`, `unsupportedLanguageOrLocale`,
  `timeout` — with room for provider-specific custom errors.

**`PrivateCloudComputeLanguageModel` — the "better fallback tier" claim, verified with specifics**
- **No API keys, no account setup, no per-request auth** — integrated with the OS/iCloud account
  directly; **no cloud token cost to the developer**.
- **Daily per-user usage limit**, higher for iCloud+ subscribers; a `quotaUsage` property exposes
  `belowLimit`/`isApproachingLimit`/`isLimitReached` states plus a `limitIncreaseSuggestion` action.
- **Eligible apps must have under 2M total first-time App Store downloads** to use it free (Apple's
  "Small Business Program"-style benefit) — apps must apply.
- **Reasoning levels** are configurable via `ContextOptions(reasoningLevel:)`. Session 319's own
  code sample used `.light`/`.moderate`/`.deep`; the Session 241 fetch only mentioned `.light` and
  `.deep` explicitly in its example — **treat the existence of a `.moderate` middle tier as
  plausible but not independently confirmed twice; check the live enum.**
- **Runs on watchOS 27** — a genuine differentiator versus the on-device model, which historically
  has not been available on Watch. Separately, the on-device `SystemLanguageModel` class itself
  now *also* lists **watchOS 27.0+ (Beta)** in its own platform-availability table per the live
  Apple doc page — meaning by iOS 27/watchOS 27 GA, Watch may get *both* an on-device path and the
  PCC path, not PCC-only as earlier assumed. **This is newer/more specific than the prior research's
  "PCC works on watchOS 27" framing — worth a second look before committing to a Watch design that
  assumes only the private-cloud tier is available there.**
  [Apple Developer Docs — `SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) ·
  [WWDC26 Session 319 — Build with the new Apple Foundation Model on Private Cloud Compute](https://developer.apple.com/videos/play/wwdc2026/319/)
- **Requires internet connectivity**; the on-device model does not.

**Structured/guided generation & tool calling**
- `ToolCallingMode` has three states: `.allowed` (default), `.disallowed`, `.required` — with
  documented exit-condition patterns (a state flag flipped in `onToolCall`, or a "final answer"
  tool that throws `CancellationError`) needed to avoid infinite tool-call loops in `.required` mode.
- **Dynamic Profiles** (new declarative API, `LanguageModelSession.DynamicProfile`): a single
  session can switch between named "profiles" (different instructions/tools/model/reasoning level)
  based on app state, and profiles can hand off to each other ("baton-pass": shared transcript, a
  tool flips which profile is active) or spawn isolated child sessions ("phone-a-friend": a tool
  opens a short-lived, separate-transcript sub-session and returns its answer as a string) — this
  is Apple's own vocabulary for what is essentially small-scale multi-agent orchestration inside
  one Foundation Models session.
  [WWDC26 Session 242 — Build agentic app experiences with the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/242/)
- **KV-cache-aware history management**: appending to a transcript preserves the executor's
  key-value cache (fast); rewriting/removing history entries invalidates it back to the divergence
  point (slower) — a new Foundation Models Instrument in Xcode surfaces cache invalidations for
  profiling. `historyTransform` and `onResponse` lifecycle modifiers let an app trim/redact/summarize
  history per-turn without permanently mutating the underlying transcript object.
- Built-in system tools: `BarcodeReaderTool`, `OCRTool`, and a **Spotlight-backed local RAG tool**
  — "no embeddings, no vector database, no setup... RAG in two lines of Swift," built on the
  device's existing Spotlight index.
  [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)

**Device/OS requirements**
- On-device `SystemLanguageModel`: **iOS/iPadOS/macOS/Mac Catalyst/visionOS 26.0+, watchOS 27.0+
  (Beta)** per the live platform-compatibility table. Availability additionally gates on
  `.deviceNotEligible` (chip/RAM class — unchanged Apple Intelligence hardware floor, roughly
  A17 Pro/M-series and newer) and `.appleIntelligenceNotEnabled` (a user Settings toggle) — apps
  must branch UI on `SystemLanguageModel.availability`, not assume presence.
  [Apple Developer Docs — `SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)

### Lancer opportunity

This is the single richest area for Lancer specifically. The confirmed, real third-party
`LanguageModel`/`LanguageModelExecutor` protocol — with Anthropic shipping an actual Swift package
— means Lancer's own on-device "draft a mission contract from a screenshot" or "summarize this
proof" features could plausibly run through the *same* `LanguageModelSession` call whether the
backing model is Apple's on-device model, PCC, or (speculatively, if useful) a Claude-backed
executor for higher-quality private summarization when the phone has connectivity — one call site,
swappable backend, matching the multi-vendor philosophy Lancer already applies to `dispatch.go`.
The Dynamic Profiles "phone-a-friend" pattern is a plausible, low-effort implementation shape for
the already-scoped "Cross-Vendor Second-Agent Review" feature, if it's ever done as an on-device
orchestration rather than a second full CLI dispatch. `PrivateCloudComputeLanguageModel`'s
no-API-key, no-per-request-cost, 32K-context tier is a genuinely better "private compression
fallback" than routing through whichever vendor CLI happens to be active — but the 2M-download
eligibility cap and unresolved on-device-vs-PCC watchOS ambiguity both need re-verification before
committing a Watch-specific design to either path.

---

## 5. Vision framework — tap-to-segment

### What's new, precisely

- New iterative segmentation API: **`GenerateIterativeSegmentationRequest`** (via
  `ImageRequestHandler`). It supports multiple selection input modes: a single tap point (seed
  point), multiple points, a drawn bounding box, a freehand lasso, and overlapping scribbles (to
  segment multiple objects in one pass) — plus refinement by adding/subtracting points after an
  initial pass.
- **Output is a pixel-level mask** (`PixelBuffer`), not a bounding box — pixel values indicate
  object membership, enabling precise downstream cropping/compositing.
- **Coordinate system**: normalized 0–1, origin at the lower-left corner. Minimum lasso stroke
  width is documented as ~1% of image width for reliable results.
- **Platform support**: iOS, iPadOS, macOS, tvOS, visionOS, and **watchOS (new in this cycle)**.
- Requires an on-device model asset — check `assetStatus` and call `downloadAssets()` before first
  use (not bundled/pre-resident).
- **Foundation Models integration is a real, demonstrated pattern**, not speculative: a segmented
  region/mask can be passed as an `Attachment` into a Foundation Models prompt for further reasoning
  (e.g., "analyze this segmented object" / auto-caption the masked region).

Sources for this section were reconstructed from a WebFetch pass against
[WWDC26 Session 237 — image understanding](https://developer.apple.com/videos/play/wwdc2026/237/);
because this came back as a synthesized summary rather than a verbatim transcript quote, **treat
the exact stroke-width/coordinate-origin numbers as indicative, not certified — re-check against
the live `GenerateIterativeSegmentationRequest` API reference before writing code against them.**

### Lancer opportunity

Directly supports two already-scoped features: **Tap-to-Segment Bug Capture** in the launch
composer (photograph a bug, isolate the exact broken UI element before dispatching a mission) and
**Tap-to-Isolate Annotation** in Proof/Mobile QA (pause a proof frame, tap the broken element, get a
precise mask instead of a hand-drawn circle). The demonstrated mask-to-Foundation-Models pipeline
means both of these could feed directly into on-device "what changed here" captioning without a
custom cropping/compositing pipeline — worth prototyping once the segmentation asset-download
behavior (size, first-use latency) is checked against a real device.

---

## 6. App Intents — LongRunningIntent, ExecutionTargets, and the agentic security session

### What's new, precisely

**`LongRunningIntent`**
- Lets an App Intent exceed the standard **30-second execution limit**. Builds on
  `ProgressReportingIntent` (a built-in `progress` object with `totalUnitCount`/`completedUnitCount`).
  Work is wrapped in `performBackgroundTask { ... } onCancel: { reason in ... }`; the intent
  additionally conforms to `CancellableIntent` for graceful shutdown (user cancel, system timeout,
  or system resource reclaim).
- **Progress automatically renders as a Live Activity**, including a system-provided stop/cancel
  button — the developer does not build this Live Activity by hand.
- **Background GPU access** is supported on capable devices for tasks like photo processing or
  on-device inference (requires a GPU-access entitlement).
- The framework requires the intent to keep reporting progress — Apple's own framing: this is how
  "the system knows it's still working and hasn't stalled," implying a lack of progress reporting
  risks the system reclaiming the task.
  [WWDC26 Session 345 — Discover new capabilities in the App Intents framework](https://developer.apple.com/videos/play/wwdc2026/345/) ·
  [Matthew Cassinelli — App Intents thirty-second limit / LongRunningIntent](https://matthewcassinelli.com/app-intents-thirty-second-limit-extend-execution-live-activity-longrunningintent/)

**`ExecutionTargets`**
- Solves a real, specific problem: when an intent/entity is defined in a shared Swift package
  linked by both the main app and one or more extensions (widget extension, App Intents extension),
  the system's default heuristic for *which process* actually executes the intent isn't always
  correct — e.g. a widget's "favorite" toggle needs to write through the main app's data model, not
  the widget extension's own sandboxed copy.
- New static property `allowedExecutionTargets: ExecutionTargets` on an intent, values: `.main`,
  `.appIntentsExtension`, `.widgetKitExtension`, or an array combining them (letting the system
  choose among a restricted set) — an explicit override of the default heuristic.
  [WWDC26 Session 345](https://developer.apple.com/videos/play/wwdc2026/345/)

**No new authentication-policy API surfaced in Session 345 itself** — but Session 347 (below)
covers exactly this, in more relevant detail than Session 345 does.

**Session 347 — "Secure your app: Mitigate risks to agentic features"** (new for WWDC26, and
directly relevant to a governance-focused app)
- Apple explicitly frames the risk model using **Simon Willison's "lethal trifecta"**: danger
  emerges when a system combines (1) access to private data, (2) exposure to untrusted content,
  and (3) the ability to take external/side-effecting action. This is presented as the mental model
  developers should threat-model *their own* agentic features against.
- Named attack patterns, with Apple's own terms:
  - **Indirect prompt injection** — instructions hidden in untrusted content (a calendar invite, a
    social feed item, a tool's returned data) redirect the agent's behavior.
  - **Data poisoning** — an attacker alters the *parameters* of an action the user did legitimately
    request (e.g. redirecting who a message is sent to).
  - **Action poisoning** — an attacker changes *which* action executes entirely (e.g. "summarize
    this email" becomes "open this URL with the email contents appended").
  - Also named: data exfiltration (agent leaks sensitive data via an outbound action), unwanted
    financial transactions, and destructive data loss without confirmation.
- **Apple's own stated mitigation hierarchy — deterministic over probabilistic, explicitly:**
  Apple's stated position: *"probabilistic mitigations could be constructed in a way that negates
  them. Only deterministic controls provide security guarantees."*
  - **Deterministic mitigations** (Apple's recommended baseline):
    - `.historyTransform` on a Dynamic Profile — redact PII from tool outputs *before* they reach
      the model's transcript, applied per-inference-iteration (must be reapplied every loop turn
      unless cached via `@SessionProperty`).
    - `.onToolCall` — a lifecycle hook that fires **before** a tool executes; throwing inside it
      blocks execution outright. Apple's own example uses this to gate a financial-impact tool
      ("order tea") behind an explicit user confirmation call.
    - `IntentAuthenticationPolicy = .requiresAuthentication` on an intent (custom or inherited from
      an adopted App Schema) — forces device authentication (e.g. Face ID) before a sensitive
      intent executes, including from the **Lock Screen**, where Apple explicitly warns that a
      fully Siri-integrated app can otherwise expose destructive/financial/exfiltration-class
      intents *without requiring unlock* unless the developer opts into this policy. Schema-based
      intents can only be overridden to a *stricter* policy — weakening below the schema default is
      a build error.
  - **Probabilistic mitigations** (lower assurance, explicitly downgraded by Apple itself):
    "spotlighting" — wrapping untrusted tool output in delimiters like `<<UNTRUSTED>>...<</UNTRUSTED>>`
    so the model is signaled (not guaranteed) to distrust that content.
  - **App Intents' own automatic risk tiers**: schema-adopting intents get a static risk
    classification from their declared side effects (**Destructive = High**, e.g. delete-assets
    schemas; **Exfiltration = High**, e.g. public-posting schemas; **Data Manipulation = Medium**,
    e.g. updating shared content; **Data Injection = Medium**, e.g. attacker-influenceable labels),
    combined with dynamic system state, to decide whether to force a confirmation automatically —
    this is presented as a built-in, not something every app must hand-roll.
  [WWDC26 Session 347 — Secure your app: Mitigate risks to agentic features](https://developer.apple.com/videos/play/wwdc2026/347/) ·
  [NowSecure — iOS 27 security: what WWDC 2026's AI features mean for mobile app risk](https://www.nowsecure.com/blog/2026/06/11/ios-27-security-what-wwdc-2026s-ai-features-mean-for-mobile-app-risk/)
- A caveat NowSecure's independent analysis adds, worth carrying forward: **neither
  `AppIntentsTesting` nor Apple's own attestation mechanisms can *verify* that an authentication
  policy actually blocks a sensitive Lock Screen intent, or that PII redaction actually holds across
  multiple tool-call round-trips in a multi-turn agent loop** — this is manual/adversarial-testing
  territory, not something a build-time check catches for you.

### Lancer opportunity

Session 347 is arguably the most directly applicable single piece of research in this whole
document, because it is Apple's own articulation of almost exactly the problem Lancer's governance
stack already exists to solve — but for *Apple's* agent surface (Siri/App Intents), not a CLI
coding agent. The risk-tier vocabulary (Destructive/Exfiltration = High, Data Manipulation/Injection
= Medium) is worth comparing directly against Lancer's own existing risk-tiered biometric gate
(commit `695d2440`) — if the categories line up, Lancer's policy engine gains an externally-validated
taxonomy to cite, not just an internally-invented one. `LongRunningIntent` + automatic Live Activity
progress is a plausible, much-lower-effort way to implement "Read Me the Status" / Away Status
progress reporting than a hand-rolled Live Activity, if Lancer ever exposes a Siri/Shortcuts-callable
"check mission status" intent. `ExecutionTargets` is directly relevant the moment any Lancer App
Intent is shared between the main app target and a future widget extension (e.g. a favorite-repo
toggle on the "Decide Now" full-size widget) — without it, a write-intent could silently execute
against the wrong process's data.

---

## 7. SpeechAnalyzer / SpeechTranscriber

### What's new, precisely — and a dating correction

**This is not a WWDC 2026 / iOS 27 feature.** `SpeechAnalyzer` and `SpeechTranscriber` shipped at
**WWDC 2025, for iOS 26+**. I found no WWDC 2026 session or iOS 27 release note introducing changes
to this framework — it should be treated as **current-generation baseline capability Lancer can
already target on iOS 26**, not something gated on iOS 27.

- `SpeechAnalyzer` coordinates three modules: **`SpeechTranscriber`** (long-form transcription,
  trained for sustained audio over minutes/hours), **`DictationTranscriber`** (short-utterance),
  and **`SpeechDetector`** (voice-activity detection).
- Fully **on-device**, automatic language management, built on a new proprietary Apple model
  reported (by third-party benchmarking, not an Apple first-party claim) to run roughly 2x faster
  than Whisper Large V3 Turbo on equivalent transcription tasks with comparable quality.
  [Apple Developer Docs — Bringing advanced speech-to-text capabilities to your app](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app) ·
  [MacStories — Hands-on: How Apple's new Speech APIs outpace Whisper](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/)

### Lancer opportunity

Because this is already-available iOS 26 capability, it's a strong candidate for the *now*
implementation of "Voice Everywhere" (launch notes, replies, QA annotation dictation) and
"Searchable Proof Transcripts" (on-device transcript of a narrated Proof Reel) — neither needs to
wait for iOS 27 at all. `SpeechTranscriber`'s long-form design is a specifically good fit for
narrating a multi-minute Proof Reel walkthrough rather than short dictation snippets.

---

## 8. Other iOS 27 / WWDC 2026 findings relevant to a mobile agent-control surface

### Device Hub & `devicectl`
- **Device Hub** is a new standalone app shipping with **Xcode 27** (not an iOS API) for managing
  real devices and simulators — sidebar device/simulator inventory, a live interactive canvas view
  of any device's screen, and an inspector (settings like dark mode/text size/simulated location,
  diagnostics like crash logs/hangs, device info, app/data-container management, profiles). It has
  a compact mode and a full-window mode.
- **`devicectl`** (the CLI) is explicitly unified in this cycle: it now uses **the same interface
  for both physical devices and simulators**, meaning a script written against a real iPhone in a
  local dev loop and a script targeting a simulator in CI no longer need to branch.
  [WWDC26 Session 260 — Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/)

**Lancer opportunity:** this directly firms up the already-planned **Device Matrix Proof** feature
— the unified real-device/simulator `devicectl` interface means a device-matrix proof pipeline (run
the same verification across N simulated device classes, or against a real paired device, through
one command shape) is now a supported, first-party workflow rather than something Lancer would have
had to special-case per device type.

### Visual Intelligence
- Expanded beyond object lookup: **Nutrition** (scan a food label into Health), **Contacts** (scan a
  business card's phone/address into Contacts), and **Wallet** (scan a physical membership
  card/ticket/rewards barcode into a digital Wallet pass) are new dedicated use cases. On iPhone,
  Visual Intelligence gets a dedicated Siri camera mode (tap the shutter, ask about what's in
  frame); on iPad it's integrated into the screenshot flow; on Mac it's new entirely (a keyboard
  shortcut to select anything on screen and ask about it); on Vision Pro, look-and-ask.
  [Digital Trends — Everything Apple announced at WWDC 2026](https://www.digitaltrends.com/computing/wwdc-2026-ios-27-siri-ai-apple-intelligence-upgrades-and-everything-else-apple-announced/)

**Lancer opportunity:** thin, but real — if Lancer ever wants a "point the camera at a physical
whiteboard/sticky-note bug report and start a mission from it," this is the system-level pattern
(Camera → Siri mode → structured understanding) Apple is normalizing app-wide, which lowers the
bar for building something similar inside Lancer's own composer rather than it feeling bespoke.

### Core Spotlight / on-device RAG
- The **Spotlight Search Tool** built into Foundation Models does fully local
  retrieval-augmented generation against the device's existing Spotlight index — "no embeddings,
  no vector database, no setup." Separately, **`IndexedEntity`** (an App Intents protocol) lets an
  app mark which of its entity's properties are semantically searchable/indexable by Spotlight, with
  built-in indexing-key wiring requiring less code than before.
  [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)

**Lancer opportunity:** if Lancer's Flight Recorder / Work Search ever wants semantic ("what did I
ask the agent to do about the checkout flow last month") rather than purely lexical search, indexing
mission/proof entities as `IndexedEntity` and querying the Spotlight RAG tool from an on-device
Foundation Models session is a plausible zero-infrastructure way to get there, instead of building
or hosting a vector database.

### watchOS 27
- New AI-forward Siri tailored for the small screen, cross-device conversation sync via iCloud, a
  new one-handed Smart Stack gesture system (double-tap to navigate widgets, single tap to launch,
  wrist-flick to dismiss), a consolidated Find My app, Workout Buddy AI coaching, and Messages Live
  Translation. No dedicated Live Activity API changes specific to watchOS were found beyond the new
  ActivityKit "small" Activity family already covered in §2.
  [Gadgetbridge — Everything new in watchOS 27](https://www.gadgetbridge.com/news/wwdc-2026-everything-new-in-watchos-27-siri-ai-menopause-tracking-and-next-level-gestures/)
- **Siri AI is also gated out of watchOS in the EU**, per the same DMA-driven restriction covered
  in §1 (explicitly stated as iPhone/iPad/Watch, not just iPhone/iPad).

**Lancer opportunity:** this is squarely relevant only once Watch support is unfrozen (currently
deferred per `docs/product/2026-07-04-away-mode-master-consolidation.md` §8: "reconsider nuance" —
`PhoneWatchConnector`/`WatchApprovalTransfer` already exist in code but are unwired). Nothing found
here changes that calculus, but the new small-widget Smart Stack gestures are a reasonable target
surface for a minimal "one glance, one tap" Watch approval affordance if that work resumes.

### Notification / interruption changes
- Only a modest, cosmetic-leaning set of changes was found: notification cards now slide in from
  the side rather than dropping from the top, same-app notifications coalesce into one updating
  entry instead of stacking, and grouping is reported to lean on on-device AI prioritization by
  type/urgency rather than strictly chronological/per-app. Separately, **Call Context** now
  generates an AI summary of an incoming call before the user decides to answer.
  [TechRadar — 21 new features in iOS 27 Apple didn't mention at the keynote](https://www.techradar.com/phones/ios/here-are-21-new-features-in-ios-27-that-apple-didnt-have-time-to-mention-during-its-wwdc-2026-keynote) ·
  [Digital Trends — WWDC 2026 recap](https://www.digitaltrends.com/computing/wwdc-2026-ios-27-siri-ai-apple-intelligence-upgrades-and-everything-else-apple-announced/)
- **No new formal interruption-level API** (e.g., changes to `UNNotificationInterruptionLevel`)
  was found in any primary source checked in this pass — this section is included mainly to record
  that the search came up materially empty of anything beyond visual/grouping polish, so the team
  doesn't re-run this same search expecting a hidden API.

**Lancer opportunity:** minimal directly, but the AI-driven grouping-by-urgency behavior is worth
keeping in mind for how a burst of Away Digest notifications (multiple missions finishing at once)
will actually be presented to the user by the system — Lancer's own `interruptionLevel` choices per
notification category should be re-tested against the new grouping behavior once on a real iOS 27
device, since grouping-by-type could visually interleave Lancer's own priority ordering with the
system's.

### StandBy mode
No StandBy-specific changes beyond the `showsWidgetContainerBackground`/`activityBackgroundTint`
Live Activity rendering behavior already covered in §2 were found in any source checked. If a design
depends on a *different* StandBy behavior than "Live Activities render at ~200% scale with a
distinct background/tint," that claim needs its own dedicated re-check — this pass did not surface
it.

---

## Summary of corrections to the prior research passes

For quick reference, here's what this pass confirmed as stated, what it corrected, and what it
left genuinely unresolved:

| Prior claim | This pass's finding |
|---|---|
| Foundation Models now multimodal, third-party model protocol, PCC fallback (32K context) | **Confirmed**, with much more precision (exact protocol names, exact code shapes, exact providers) |
| Vision tap-to-segment | **Confirmed**, with exact API name (`GenerateIterativeSegmentationRequest`) and input modes |
| Siri rebuilt, View Annotations API, multi-step commands, EU/China regulatory gap | **Confirmed**, with the exact modifier name, exact use-case split vs. `NSUserActivity`, and confirmation the gap is EU **and** China, for different legal reasons, both open-ended |
| App Intents mandatory / SiriKit deprecated | **Unconfirmed** — no primary source found stating this outright; treat as directional, not settled |
| ActivityKit landscape Dynamic Island support | **Confirmed**, exact API (`isDynamicIslandLimitedInWidth`); button/toggle-only interaction model reconfirmed unchanged |
| WidgetKit gained "full-screen widgets" | **Corrected** — the real feature is the `.systemExtraLargePortrait`-family widget (from visionOS 26, now on iOS/iPadOS/macOS 27), not a distinct full-screen surface; "full-screen widget" appears to be press shorthand, not an Apple API term |
| App Intents added LongRunningIntent and execution-target APIs | **Confirmed**, with full mechanics (`performBackgroundTask`, `ProgressReportingIntent`, `ExecutionTargets` values) |
| (Not previously surfaced) Agentic-feature security session (347), risk-tier taxonomy, deterministic-vs-probabilistic mitigation guidance | **New finding this pass** — likely the most directly applicable material in this whole doc to Lancer's own governance stack |

---

## Full source list (deduplicated)

- [WWDC26 Session 240 — Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/)
- [WWDC26 Session 344 — Code-along: Make your app available to Siri](https://developer.apple.com/videos/play/wwdc2026/344/)
- [WWDC26 Session 339 — Bring an LLM provider to the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/339/)
- [WWDC26 Session 319 — Build with the new Apple Foundation Model on Private Cloud Compute](https://developer.apple.com/videos/play/wwdc2026/319/)
- [WWDC26 Session 241 — What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26 Session 242 — Build agentic app experiences with the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/242/)
- [WWDC26 Session 237 — What's new in image understanding (Vision tap-to-segment)](https://developer.apple.com/videos/play/wwdc2026/237/)
- [WWDC26 Session 223 — Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/)
- [WWDC26 Session 277 — WidgetKit foundations](https://developer.apple.com/videos/play/wwdc2026/277/)
- [WWDC26 Session 345 — Discover new capabilities in the App Intents framework](https://developer.apple.com/videos/play/wwdc2026/345/)
- [WWDC26 Session 347 — Secure your app: Mitigate risks to agentic features](https://developer.apple.com/videos/play/wwdc2026/347/)
- [WWDC26 Session 260 — Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/)
- [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- [WWDC26 iOS guide](https://developer.apple.com/wwdc26/guides/ios/)
- [Apple Developer Docs — `SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Apple Developer Docs — Bringing advanced speech-to-text capabilities to your app](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app)
- [Apple Newsroom — Due to DMA, Siri AI delayed in EU for iOS 27 and iPadOS 27](https://www.apple.com/newsroom/2026/06/due-to-dma-siri-ai-delayed-in-eu-for-ios-27-and-ipados-27/)
- [MacRumors — New Siri AI features won't be available in EU](https://www.macrumors.com/2026/06/08/siri-ai-not-available-eu-china/)
- [TechNode — Apple delays AI-powered Siri in EU and China over regulatory hurdles](https://technode.com/2026/06/10/apple-delays-ai-powered-siri-in-eu-and-china-over-regulatory-hurdles/)
- [MacRumors Forums — iOS 27 brings these five new features to your iPhone Lock Screen](https://forums.macrumors.com/threads/ios-27-brings-these-five-new-features-to-your-iphone-lock-screen.2483731/)
- [NowSecure — iOS 27 security: what WWDC 2026's AI features mean for mobile app risk](https://www.nowsecure.com/blog/2026/06/11/ios-27-security-what-wwdc-2026s-ai-features-mean-for-mobile-app-risk/)
- [Matthew Cassinelli — App Intents thirty-second limit / LongRunningIntent](https://matthewcassinelli.com/app-intents-thirty-second-limit-extend-execution-live-activity-longrunningintent/)
- [Firebase Blog — Gemini in Apple's Foundation Models framework](https://firebase.blog/posts/2026/06/apple-foundation-models-gemini/)
- [Digital Trends — Everything Apple announced at WWDC 2026](https://www.digitaltrends.com/computing/wwdc-2026-ios-27-siri-ai-apple-intelligence-upgrades-and-everything-else-apple-announced/)
- [TechRadar — 21 new features in iOS 27 Apple didn't mention at the keynote](https://www.techradar.com/phones/ios/here-are-21-new-features-in-ios-27-that-apple-didnt-have-time-to-mention-during-its-wwdc-2026-keynote)
- [Gadgetbridge — Everything new in watchOS 27](https://www.gadgetbridge.com/news/wwdc-2026-everything-new-in-watchos-27-siri-ai-menopause-tracking-and-next-level-gestures/)

Internal (baseline docs read before this pass — not independently re-cited per claim, referenced for
provenance only):
- `docs/product/2026-07-04-away-mode-master-consolidation.md`
- `docs/product/2026-07-04-lancer-strategy-feature-source-of-truth.md`
- `docs/design-audit/2026-07-05-final-cursor-wireframe-handoff.md`
