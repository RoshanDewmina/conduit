# Live Activities & glanceable surfaces — v1 decision

_Date: 2026-06-16 · Prerequisite reading: `apple-ecosystem-research-2026-06.md`, competitive-landscape audit._

## v1 recommendation: Hybrid A+B — relay tier gets Live Activities, self-host gets local-notification fallback

The existing doc's call is correct and stands. Here's the sharper v1 framing:

| Tier | Live Activity behavior | Mechanism |
|---|---|---|
| **Hosted relay (paid)** | Full: push-to-start, push-update, inline Approve/Deny | Relay holds APNs `.p8` key, sends liveactivity pushes |
| **Self-host (free)** | App-foreground only + standard UNNotification fallback | `Activity.update()` from in-app; BGTask for partial background coverage |

### Why the self-host tier cannot do remote push Live Activities (correcting a nuance)

Local notifications (`UNNotificationRequest`) **cannot** update Live Activities. `BGTaskScheduler` *can* but fires unreliably (iOS decides when). So the self-host tier's Live Activity is strictly: app-foregrounded updates only. The fallback is a standard lock-screen notification (`UNNotification` with `defaultAction` deep-link) — not a Live Activity. This is a real product line: paid relay = glanceable agent loop; free = tap-notification-to-open-app. Clean, honest, defensible.

## Push-to-start: required for the flagship flow, iOS 17.2+ is fine

The killer scenario is: user locks phone, agent starts working 20 min later, phone buzzes with a Live Activity already showing the tool stream. **This requires push-to-start (iOS 17.2+).** The app registers a `pushToStartToken` at launch and ships it to the relay; when the daemon reports agent activity, the relay sends an APNs liveactivity start push with the required `alert` key. The system starts the Live Activity and wakes the app in the background. By Fall 2026, iOS 17.2+ is a safe floor (iOS 18 will be current). The relay's APNs push also handles ongoing updates (priority `5` for routine tool steps, `10` for approval-needed flips).

## Lock Screen Approve/Deny: viable and aligned with governance

Buttons run via `LiveActivityIntent` (iOS 17+) and wake the app process — exactly what Conduit needs, because the actual approval still flows through the relay inbox to the daemon's firewall. **Critical finding from docs:** Apple does **not** require biometric unlock for Live Activity buttons. The Lock Screen is accessible while the phone is locked. Conduit must implement `UserAuthenticationRequired` (or equivalent) on the Approve intent. This is trivially correct: the on-device Face-ID/passcode gate confirms the user's personhood before the intent sends the approval over the relay. Documentation says the intent runs in the app's process — so the governance chain (audit log, blast-radius checks, relay verification) is intact. The Live Activity is just a remote trigger; no bypass.

## Security: relay holds APNs key — acceptable risk

Incremental over today's relay threat model:
- The relay already holds the pairing secret and is the E2E relay for all approval traffic.
- An APNs key can be scoped by Apple to `push-type: liveactivity` only (no background notifications, no alert pushes) and to Conduit's bundle ID.
- Worst case if key leaks: attacker can spoof the Live Activity UI (show "approval needed" with a fake command). They **cannot** approve without the user unlocking and the intent validating through the relay inbox, which requires the relay's own auth.
- Key lives in the relay's secret store (`.env`, 0600) — never on a self-host box.

Recommendation: one APNs key per environment (staging / prod), rotated quarterly. Add to the existing security checklist.

## Competitive landscape: Moshi is the only player in market

| Product | Live Activity / Dynamic Island | Apple Watch |
|---|---|---|
| **Moshi** | Yes (shipped v2.x) | Yes (native, approve/deny) |
| **Omnara** | No | Yes (view + quick reply) |
| **Happy Coder** | No | No |
| **Warp / Cline / Roo** | N/A (desktop only) | N/A |
| **opencode** | No (3rd-party apps only, none have live activities) | No |

Moshi is the benchmark. Everything else is noise. Conduit's chance: ship Live Activities with inline Approve/Deny (Moshi also has this), plus quota rings (Moshi has). Parity is table stakes; the differentiation is **governance depth** (blast-radius enforcement, audit chain), not glanceable surfaces. But you cannot compete without parity.

## Live Activities: v1.x, not v1-blocker

**Ship v1 with:**
- Quota rings (`SwiftUI Gauge`, `.circular`/`.accessoryCircular` over existing `QuotaGuard` data). Immediate Moshi parity, zero backend work.
- Standard UNNotification push fallback (approval requests deep-link into app). Works for both tiers.
- Widget extension target *skeleton* — the target that will later host Live Activity and widget views. Avoids a re-org later.

**Ship v1.x (target 2–4 weeks after v1) with:**
- Relay pushes Live Activities (push-to-start + push-update) — requires the relay APNs sender to be built and audited.
- Inline Approve/Deny buttons on Lock Screen + Dynamic Island.
- Live Activity cards showing agent loop state: tool name, elapsed time, pending approval flag.

Rationale: Live Activities are the flagship glanceable surface and a competitive necessity (Moshi gap), but they depend on the relay APNs sender which is a new component with real security requirements. The quota rings + push notifications in v1 give a "Conduit is a modern app" baseline; the Live Activity follow-up in 1.x closes the Moshi gap decisively without delaying v1's core (governance + relay).

## Recommended sequencing

1. **Now:** Mock the Live Activity layout (Dynamic Island pill + lock-screen card) in the JS prototype. Lock the design before Swift.
2. **v1:** Quota rings + UNNotification fallback + widget extension target skeleton.
3. **v1.x:** Relay APNs sender → push-to-start Live Activities → inline Approve/Deny.
4. **Post-v1.x:** Apple Watch complication (reuses Live Activity views via Smart Stack; standalone watch app deferred).
