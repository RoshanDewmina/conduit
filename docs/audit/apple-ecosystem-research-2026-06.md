# Apple-ecosystem surfaces for Conduit — research & recommendation

_Date: 2026-06-16 · Author: Claude (planning/verify role) · Source: Apple Developer docs via apple-docs MCP (ActivityKit, WidgetKit, SwiftUI Gauge), current as of fetch._

## Why this matters

The competitive-landscape audit (`competitive-landscape-2026-06.md`) flags **Apple-ecosystem presence** as a gap: Moshi (the 4.8★ incumbent) ships Apple Watch, Live Activities, Dynamic Island, and usage rings. For an app whose whole value is _glanceable, long-running agent oversight_, the lock screen / Dynamic Island / wrist are the natural home for "agent is working / agent needs you." This is not a cosmetic gap — it's where the product's core loop (notice → approve) wants to live.

This doc is the docs-first research the owner asked for before any opencode dispatch.

---

## 1. The four surfaces, mapped to Conduit

| Surface | Framework | Min OS | What Conduit puts there |
|---|---|---|---|
| **Live Activity** (Lock Screen + Dynamic Island + Home Screen; Watch Smart Stack; Mac menu bar; CarPlay) | ActivityKit + WidgetKit UI | iOS 16.1 (start-via-push iOS 17.2+) | Live agent-loop status: "claude · running · 3 tools" → flips to "⚠ approval needed" with **Approve/Deny buttons inline** |
| **Home/Lock-screen Widget** & **Watch complication** | WidgetKit (timeline) | iOS 14 / watchOS 9 | Fleet glance: # agents working / # waiting; quota ring; tap → app |
| **Control** (Control Center / Lock Screen / Action Button) | WidgetKit controls | iOS 18 | "New agent" / "Mute approvals" quick toggle |
| **Quota rings** | SwiftUI `Gauge` (`.circular` / `accessoryCircular`) | iOS 16 | Per-provider usage vs cap, in-app + widget + watch |

All four share SwiftUI view code via a single **widget extension** (`Creating-views-for-widgets-Live-Activities-and-watch-complications`). Build once, surface many — Apple explicitly designs for this.

---

## 2. The load-bearing finding: push updates need a server-side push sender

**This is the architectural decision the owner must make, and it ties straight into the SSH→resident-daemon→hosted-cloud pivot (`project_state_dossier`).**

Live Activities do **not** update on a timeline. They update two ways:

1. **From the app process** — only while the app has foreground/background runtime. Not viable for "agent needed you 40 min after you locked the phone."
2. **From a server via APNs** — the real mechanism. The app obtains a `pushToken` (and `pushToStartTokenUpdates` for push-to-_start_ on iOS 17.2+) and ships it to **a server that holds APNs credentials and sends the JSON payload** to `https://api.push.apple.com`.

Conduit's agent lives on the **host**, behind the **resident daemon `conduitd`** and reached over **SSH or the E2E relay**. A host daemon cannot itself talk APNs with the app's push cert — and you would not want every self-hosted box holding the App Store team's APNs key. So driving Live Activities / widget refresh requires **one of**:

- **(A) Relay-as-push-sender (recommended).** The existing hosted relay (Tailscale-funnel pairing layer) is the natural, _already-trusted_ home for the APNs token + sender. Daemon → relay (already wired for approvals) → APNs → Live Activity. Adds an APNs sender to a component we already run. Keeps self-host boxes out of the push business.
- **(B) Pure self-host, no remote push.** Live Activity updates only while the app runs; lock-screen freshness via standard local notifications (`UNNotificationRequest`) that deep-link into the app. Weaker glance, but zero hosted dependency — the right default for the privacy-purist self-host tier.
- **(C) iOS 18 broadcast channels.** APNs channel + broadcast push (`apns-channel-id`) for one-to-many. Overkill for 1 user ↔ N hosts; ignore for v1.

**Recommendation:** gate rich Live Activities behind the **hosted-relay tier** (A); ship **local-notification deep-links** as the self-host fallback (B). This is consistent with the moat being governance + the hosted relay being where cross-device fan-out already lives. It also means **Live Activities are a relay-tier feature, not a day-one self-host feature** — a clean product line, not a compromise.

---

## 3. Interactive Approve/Deny from the Lock Screen — and why the lock is a _feature_

Buttons/toggles in a Live Activity run via **App Intents** (`init(_:intent:)` / `Toggle(isOn:intent:)`), iOS 17+. Key facts:

- An intent conforming to **`LiveActivityIntent`** runs **in the app's process** (the app wakes) — exactly what we need, because approving means the app must transmit the decision to the daemon over the relay, not just mutate a local toggle.
- **On a locked device, buttons are inert until the person authenticates/unlocks.** For a generic app that's friction. **For Conduit it's a governance gift:** a destructive-command approval that _cannot_ be actioned without unlocking the device is a free Face-ID/passcode gate on the approval, aligned 1:1 with the blast-radius/Face-ID risk model. We should lean into it, not fight it.
- `Toggle` updates **optimistically**; wrap async-updating views in `invalidatableContent(_:)` so a pending relay round-trip reads as "updating," not "done."

So the Lock-screen approval flow is: Live Activity shows the pending command + diff chips → user taps **Approve** → device requires unlock → `LiveActivityIntent` fires in-app → app sends the decision over the existing relay inbox → daemon releases the firewall. The approval firewall + audit chain stay authoritative; the Live Activity is just a remote trigger. No governance is bypassed.

---

## 4. Quota rings — cheap, high-signal, no architecture cost

`Gauge` with `.gaugeStyle(.circular)` (or `.accessoryCircular` in widget/watch contexts) + a `Gradient` tint = the usage-ring look, native, iOS 16+. Data is **already in the app** — `QuotaGuard` (wired per `project_competitor_features_wiring`). No backend work; it's a visualization over data we hold.

- **In-app:** a row of circular gauges per provider (Claude / Codex / …) on Fleet or a Usage view; green→amber→red gradient as the cap approaches.
- **Widget / complication:** `accessoryCircular` gauge = one provider's headroom at a glance.
- **This is the lowest-effort, highest-polish item of the three gaps** — ship it first; it needs no relay/push decision and lands the "feels like Moshi" parity immediately.

---

## 5. Apple Watch

WidgetKit complications + the Smart Stack already give a wrist glance for free once the widget extension exists. A **full watch app** (approve from the wrist without the phone) is a bigger lift: it needs `WatchConnectivity` (or its own relay client) to carry the decision, and it inherits the same push-sender requirement from §2. **Defer the standalone watch app to post-v1;** get the complication + Smart Stack Live Activity for near-free first.

---

## 6. Recommended sequencing

1. **Quota rings (now).** Pure SwiftUI `Gauge` over existing `QuotaGuard` data. No architecture decision. Immediate parity polish. Also mock it in the JS prototype (circular SVG rings) so the design is locked before Swift.
2. **Decide the push tier (owner call).** Relay-as-push-sender (A) vs self-host local-notifications (B). Everything glanceable hangs off this. My pick: do both, A as the relay-tier upsell, B as the self-host floor.
3. **Live Activity (loop status + inline Approve/Deny).** The flagship surface. Lock-screen approval = remote trigger into the existing firewall; the unlock requirement _is_ the Face-ID gate. Relay-tier.
4. **Widgets + complications.** Fleet glance + quota ring; mostly reuses the Live Activity / Gauge views.
5. **Standalone Watch app + Controls.** Post-v1.

## 7. What to hand opencode (and what not to)

- **Prototype-first (JS):** mock the Live Activity (lock-screen card + Dynamic Island pill) and the quota rings in the phone prototype so the _design_ is approved before any Swift. Safe to dispatch now, one file per surface.
- **Swift (gated):** the widget-extension target, ActivityKit integration, and relay push-sender are real app-target work — they must wait on (a) the §2 push-tier decision and (b) the v1 view-cut confirmation the owner reserved (`spec §8`). Do **not** dispatch Swift for these until both are locked; verify via the XcodeBuildMCP app-target build, never `swift build` (the extension + `#if os(iOS)` paths are exactly what SPM skips).

## 8. Caveats

- Min-OS / behavior facts are from current Apple docs (fetched this session). Exact iOS-18 broadcast-channel payload shapes need a spot-check against `setting-up-broadcast-push-notifications` if we ever pursue (C).
- The relay push-sender (A) means the hosted relay gains custody of an APNs auth key — a real secret-management surface (Keychain/`.env` rules apply; never in a self-host box). Flag for the security pass.
