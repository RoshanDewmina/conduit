# 04 — Live Activities and Dynamic Island

> Research method: apple-docs MCP (WWDC index tops out at 2025 — confirmed), live WebFetch of the
> actual WWDC26 session pages (`wwdc2026/223` "Live Activities essentials", `wwdc2026/277`
> "WidgetKit foundations"), WebSearch for APNs payload/HIG specifics, and direct grep of the
> shipped iOS 27.0 SDK's `ActivityKit`/`WidgetKit`/`AppIntents` swiftinterface files. SDK grep is
> ground truth for "does this symbol exist"; WWDC transcript quotes are ground truth for
> guidance/intent; forum/blog sources are explicitly marked lower confidence throughout.

## Current implementation (from `02-current-codebase-state.md`)

Local Live Activity start/update/end, stale dates, and push tokens are all real, working code
(`LiveActivityManager.swift:153,198,319`). Dynamic Island expanded/compact/minimal regions and
approve/reject buttons are real `LiveActivityIntent` plumbing (`LancerLiveActivityWidget.swift:23,194`),
including a landscape-aware layout fixed 2026-07-02 using `EnvironmentValues.isDynamicIslandLimitedInWidth`.
Three real gaps remain, addressed below.

## API / capability table

| API / capability | min OS + Xcode | beta | entitlements | restrictions | background limits | privacy/App Review | applicability | source | confidence |
|---|---|---|---|---|---|---|---|---|---|
| `Activity.request(attributes:content:pushType:style:alertConfiguration:start:)` | iOS 26.0+ | N | Push Notifications capability only if `pushType: .token` | superseded the deprecated `startDate:` overload | foreground call | — | Main app | SDK `ActivityKit.swiftinterface:68-75` | High |
| `Activity.end(_:dismissalPolicy:)` | iOS 16.2+ | N | — | `ActivityUIDismissalPolicy`: `.default`/`.immediate`/`.after(Date)` — **one-way, terminal, no "pause" state**; ending is not resumable | can only be called within the app's existing background execution window (BGTask/push-received runtime) — cannot end after full suspension without a fresh wake | — | Main app / any process holding the `Activity` handle | SDK `ActivityKit.swiftinterface:174-191,455-459` | High |
| Push-to-start (`pushToStartTokenUpdates`, `event: "start"`) | iOS 17.2+, unchanged in 27 | N | Push Notifications + `NSSupportsLiveActivities`/`NSSupportsLiveActivitiesFrequentUpdates` Info.plist keys | requires `ActivityAuthorizationInfo().frequentPushesEnabled` for high-frequency updates | receiving a push-to-start payload **wakes the app and grants background runtime to start the Activity** — the load-bearing mechanism for a fully-closed app | resulting content must match what triggered the push — no bait-and-switch | Push server → device, no running app process required | SDK `ActivityKit.swiftinterface:132,539` | High (SDK) / Medium (payload shape, web-sourced) |
| ActivityKit push payload shape (`event`, `content-state`, `attributes-type`, `attributes`, `stale-date`, `relevance-score`) | n/a (server-side JSON) | N | `apns-topic: <bundleID>.push-type.liveactivity`, `apns-push-type: liveactivity` | **4KB max payload**; `attributes-type`/`attributes` only required on `start` | each push counts against the update budget | content-state delivered to widget-extension process — treat like any push payload | Push server ↔ widget extension | Two independent third-party writeups + SDK field names — Apple's own doc page returned only a title via WebFetch (JS-rendered) | Medium — not read directly from Apple's primary text; verify before hard-coding server-side |
| `ActivityContent.staleDate`/`.relevanceScore` | iOS 16.1+, unchanged in 27 | N | — | `relevanceScore: Double`, 0–100 range used by the system to rank concurrent activities for Island/Watch surfacing | staleness affects presentation only (`ActivityState.stale`), not execution budget | — | Main app content authoring | SDK `ActivityKit.swiftinterface:410-412` | High (fields) / Medium (0–100 scale, doc-sourced) |
| `EnvironmentValues.isDynamicIslandLimitedInWidth` | **iOS 27.0+ new** | N | — | read-only Bool for compact/minimal Island views; confirmed lives in **WidgetKit**, not ActivityKit | — | — | Widget extension (already in use in Lancer's landscape fix) | SDK `WidgetKit.swiftinterface:605-611` | High — SDK-verified independently twice |
| `WidgetFamily.systemExtraLargePortrait` | **iOS 27.0+/macOS 27.0+ new** (was visionOS-only before) | N | — | new portrait-oriented extra-large widget family | — | — | Home Screen widgets generally (not Live-Activity-specific) — the other genuinely-new width/orientation API this cycle | SDK `WidgetKit.swiftinterface:951-955` | High |
| `supplementalActivityFamilies([.small])`/`ActivityFamily` | iOS 18.0+, unchanged in 27 | N | — | opt-in per-`ActivityConfiguration`; app must supply a `.small`-family view | — | — | **Apple Watch Smart Stack + CarPlay Dashboard** both use the Small Activity Family per the WWDC26 transcript (exact Watch-vs-CarPlay family mapping not fully disambiguated) | SDK `WidgetKit.swiftinterface:750-817`; WWDC26 §223 | High (SDK) / Medium (Watch vs CarPlay disambiguation) |
| macOS menu bar presentation | macOS 14+, unchanged in 27 | N | none extra — automatic via Continuity if signed into same Apple ID | reuses the default (non-`.small`) family view scaled for menu bar — **no dedicated `.macOSMenuBar` family exists** | — | — | Automatic, not opt-in; app has limited control over what renders there | WWDC26 §223 transcript | Medium |
| Lock Screen / StandBy presentation | Lock Screen iOS 16.1+, StandBy iOS 17+, unchanged in 27 | N | — | **StandBy reuses the Lock Screen view scaled to 200%** — no separate StandBy view builder exists | — | Lock Screen is the highest-exposure surface; HIG calls out redacting sensitive content here | One view serves both surfaces | WWDC26 §223 direct quote | High |
| `containerBackground(for: .widget)`/`widgetAccentedRenderingMode` | iOS 17.0+, unchanged in 27 | N | — | omitting `containerBackground` is a documented App Review rejection reason since iOS 17 | — | — | Widget extension + Live Activity views | SDK `WidgetKit.swiftinterface:189` | High |
| `LiveActivityIntent` protocol | iOS 16.1+, unchanged in 27 | N | — | conforms to `AppIntents.SystemIntent`; **executes inside the widget-extension process**, not the main app | runs under the extension's own background allowance on tap | **no direct access to the host app's biometric/Keychain session** — see risk-gating section below | Widget extension (Live Activity buttons) | SDK `AppIntents.swiftinterface:257`; WWDC26 §223 | High |

## Gap #1: `.end()` on background contradicts documented push-driven lifecycle

`AppRoot.swift:338` calls `.end()` on every Live Activity when the app is backgrounded. This is
architecturally wrong for exactly the scenario `ARCHITECTURE.md:76` claims to support (push-driven
Live Activity while closed): `.end()` is a **one-way, terminal call** — there is no "pause" state
in ActivityKit. The moment it's called, the activity is gone; any subsequent push update has
nothing left to update.

**Correct pattern per WWDC26 §223:** keep the `Activity` reference alive, obtain its push token
(`activity.pushTokenUpdates` or the static `pushToStartTokenUpdates` sequence), ship the token to
the server, and drive all further state changes via APNs `event: "update"` while the app is
suspended or killed. This is literally the session's own framing: *"Great for all other use
cases... You'll obtain a push token for the Live Activity and use that to send each update."*

**Conditions that force-end an activity regardless of app code** (forum-sourced, pre-27 behavior,
medium/low confidence — not independently re-confirmed in WWDC26 material this pass):
- A hard **8-hour maximum lifetime** from start.
- Reaching `staleDate` does **not** end the activity — only flips it to `.stale` presentation.
- User long-press-dismiss on Lock Screen; app deletion; user disabling Live Activities in Settings
  (blocks new activities, doesn't retroactively kill a running one).

**Recommendation:** remove the `.end()`-on-background call. Only call `.end()` from app code when
the underlying agent session is *known* to have terminated at that exact moment — not merely
because the UI went off-screen. This is the single highest-priority fix in this report's Live
Activity section, and it directly falsifies or confirms the current biggest doc/code mismatch —
see `05-device-hub-testing-plan.md`'s backgrounding test row.

## Gap #2: no risk-level field — HIG-relevant, not just a data-model gap

Content state currently has no risk-level field, so high/critical approvals render identically to
routine ones in the Dynamic Island. Apple's Live Activities HIG guidance (WebSearch snippet —
**medium confidence, the page itself returned only a title via WebFetch due to client-side
rendering; verify with a direct browser fetch before citing verbatim**) recommends *not*
displaying sensitive content directly in a Live Activity — either show an innocuous summary and
require tap-through for detail, or redact and let the user opt in. A high-risk approval showing a
full diff/command on the Lock Screen is exactly the anti-pattern this guidance warns against.

**Can a destructive `LiveActivityIntent` require Face ID before executing?** Constrained, and
worth stating plainly:
- `LiveActivityIntent` executes **inside the widget-extension process** on tap — the system calls
  `perform()` directly, with no host-app round-trip first (confirmed: `AppIntents.SystemIntent`
  conformance, SDK `AppIntents.swiftinterface:257`).
- Widget extensions have no documented, supported pattern for blocking on a synchronous Face ID
  prompt from inside `perform()` the way a foreground app can. No new symbols matching
  "biometric"/"LAContext"/"authentication" appeared anywhere in the ActivityKit/WidgetKit/AppIntents
  SDK diff for iOS 27 — Apple did not add new API for this.
- **Practical recommendation:** don't attempt Face ID inside the widget extension. Instead, make
  any button above the risk threshold an "open app to confirm" action (deep link or an intent that
  only stages the decision) — full approve/deny with Face ID happens only once control hands to
  the main app, which already has `BiometricGate` in this codebase (though note: `BiometricGate`
  is currently **not wired into any approval path** per the 2026-07-01 owner decision to remove
  biometric gating from V1 — see `07-security-and-trust.md` for the tension this creates). Routine,
  low-risk approvals can keep the direct in-Activity button.
- This requires a `riskLevel` field in the content-state schema to pick which button set renders —
  a data-model change, not just a UI tweak.

Confidence: **High** on the technical process-boundary constraint (SDK-verified); **Medium** on
whether Apple has explicit WWDC26 guidance specifically about gating destructive Live Activity
actions — no session transcript directly addresses this; the recommendation is inference from
confirmed facts plus general HIG privacy guidance, not a direct Apple quote.

## Gap #3: relay-only push-to-start architecture

Token forwarding currently only happens when `daemonChannel` exists (`AppRoot.swift:1745`); the
relay-only path registers **APNs device tokens**, not **Live Activity tokens**
(`E2ERelayBridge.swift:123`). No backend `event: "start"` sender was found
(`daemon/push-backend/main.go:451` has `/register-activity-token` and update payloads only).

Best-available payload synthesis (medium confidence — Apple's primary doc page didn't render via
WebFetch; corroborated by two independent technical writeups plus SDK field names — **verify
against a live browser render before hard-coding into `daemon/push-backend`**):

```text
Headers:
  apns-topic: <bundle ID>.push-type.liveactivity   (same suffix for start/update/end)
  apns-push-type: liveactivity
  apns-priority: 10 (high)

Body (aps):
  timestamp: <unix epoch seconds>
  event: "start"
  content-state: <JSON matching ActivityAttributes.ContentState's Codable shape>
  attributes-type: <string name of your ActivityAttributes-conforming struct>
  attributes: <JSON matching that struct — only required/meaningful on "start">
  alert: {title, body, sound}   (optional)
  stale-date / relevance-score: sibling aps-level keys, not nested in content-state

Constraints:
  4KB max payload
  requires the device to have previously registered via pushToStartTokenUpdates
  frequentPushesEnabled gates high-frequency update rate
```

**This is the only way to originate a Live Activity when the app is fully closed and no local
daemon connection exists** in Lancer's relay-only V1 architecture — it should be treated as the
primary mechanism to build and test for the "relay-only, phone-closed" scenario, not a fallback
behind the SSH/`daemonChannel` path.

## Recommended states for the content model

Building on the existing 7 preview states (connected, streaming, needs-approval ×1, needs-approval
×3, just-approved, reconnecting, over-budget) confirmed working via `RenderPreview`:

- Add `riskLevel: RiskTier` (`.low`/`.medium`/`.high`/`.critical`) to gate button visibility per
  Gap #2 above.
- Keep genuinely glanceable fields only: current stage (not fake percentage progress), elapsed
  time, agent + project, machine, tests passed/failed count, files-changed count, pending-approval
  count, blocked/disconnected/completed state, emergency-stop affordance. **Do not** put terminal
  output, full diffs, secrets, or rapidly-changing data in the content state — this is both a
  privacy requirement (Lock Screen exposure) and a payload-size constraint (4KB cap).

## Device Hub test cases

See `05-device-hub-testing-plan.md`'s "Live Activity states" and "Backgrounding / relaunching"
rows — the backgrounding test is the single most important one to run once Gap #1 is fixed, since
it directly exercises the documented-vs-actual lifecycle mismatch.

## Sourcing caveats to carry into the final report

- Apple's own ActivityKit push-notification doc page and the Live Activities HIG page both
  returned only a title via WebFetch (client-side rendered) — payload-shape and redaction-guidance
  claims above are corroborated by multiple independent secondary sources plus SDK field names,
  not read directly from Apple's primary text. A follow-up direct-browser fetch (e.g. via
  claude-in-chrome) is worth doing before this report is treated as final on those two points.
- The 8-hour lifetime / Lock-Screen-persistence-after-end figures are forum-sourced, pre-27
  behavior, not re-confirmed in WWDC26 material pulled this session.
