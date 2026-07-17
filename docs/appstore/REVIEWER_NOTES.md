# App Review notes — Lancer (`dev.lancer.mobile`)

**Purpose:** paste-ready App Store Connect "Notes for Review" + reviewer demo
steps + IAP/push/encryption answers, grounded in the current codebase (not
`docs/legal/APP_REVIEW_NOTES.md`, which describes a QR-pairing / SSH-only
flow that predates the E2E relay and is stale — see the correction in §5).

---

## 1. What Lancer is (paste into "Notes for Review")

```
Lancer is a mobile control plane for AI coding agents (Claude Code, Codex,
OpenCode, Kimi) that run entirely on the developer's own Mac/Linux machine
or server — never in Lancer's cloud. The iOS app does not execute, compile,
or run arbitrary code. It displays agent activity and approval requests
relayed from the user's own host, and sends back governed decisions
(approve / deny / edit).

WHY A COMPANION DAEMON: coding agents need a real filesystem, shell, and
toolchain, which iOS sandboxing does not provide and is not meant to
provide (see Lancer's own product non-goals in ARCHITECTURE.md §1.1: "Local
iOS code editor" and "Local language servers/build tools" are explicit
non-goals — the phone steers, the user's own machine executes). This is the
same "remote host, phone-native client" model as established App Store SSH
clients (e.g. Blink Shell, Termius), not a code-execution app under
Guideline 2.5.2.

ARCHITECTURE:
  [User's own Mac/Linux host]
      - Runs the coding agent CLI (Claude Code / Codex / OpenCode / Kimi)
      - Runs `lancerd`, a small resident daemon: policy engine, approval
        queue, hash-chained audit log
      - Connects out to Lancer's end-to-end-encrypted relay
                              |
                    [Lancer push relay — forwards ciphertext only]
                              |
      [Lancer iOS app] -- pairs to the same relay with a one-time 6-digit
                            code (not a QR scan) -- displays the agent's
                            proposed action and blast radius, and returns
                            the user's approve/deny/edit decision

DATA FLOW: an agent on the user's host proposes a risky action → lancerd's
policy engine evaluates it and, if it needs a human, queues it and (if the
phone is reachable) sends a push notification → the user reviews the exact
command/patch and its computed risk tier in the app or from the lock screen
→ the decision travels back over the same encrypted relay, content-hash
verified against what was actually reviewed → lancerd executes or discards
the action on the user's own host. The relay only ever sees ciphertext
(X25519 ECDH + ChaCha20-Poly1305, ephemeral per-pairing keys) — see
docs/legal/SECURITY_ARCHITECTURE.md §3-4 for the full protocol.

GUIDELINE 2.5.2 (code execution): the app performs no dynamic code
download/execution on-device. All agent execution happens on hardware the
user owns and controls; the app is a remote-approval/monitoring client.

GUIDELINE 5.1.1 (data collection): the app collects only an APNs device
token, forwarded to Lancer's own relay solely to route push notifications.
No account system is required for the core (offline pairing) flow. Full
inventory: docs/appstore/PRIVACY_NUTRITION_LABEL.md.

GUIDELINE 3.1.1 (IAP): "Lancer Pro" (dev.lancer.mobile.pro) is a one-time
Non-Consumable IAP ($14.99), not an auto-renewing subscription — see §3
below.

GUIDELINE 4.2 (minimum functionality): the app ships a durable chat/approval
thread list, a governed approval inbox with policy/blast-radius detail, a
live SSH terminal (daemon-owned PTY streamed over the relay), Trusted
Machines management, and Settings/Policy & Governance — a complete, non-
placeholder feature set for its stated purpose.

Built with Xcode 27 / iOS 26.0 deployment target (ARCHITECTURE.md header).
```

---

## 2. Reviewer demo — be honest about what does and doesn't ship

**Correction vs. the older `docs/legal/APP_REVIEW_NOTES.md`:** that document
describes DEBUG-only seeded review seams (`LANCER_UITEST_RESEED`,
`LANCER_DESTINATION` deep-links, `LANCER_SEED_DEMO`) as if a reviewer could
trigger them on a submitted build. They cannot. Every one of those seams is
wrapped in `#if os(iOS) && DEBUG` (confirmed by reading
`Packages/LancerKit/Sources/AppFeature/DebugSeeder.swift:1` and the
`shouldShowOnboarding` gate in `AppRoot.swift:293-313`, both DEBUG-gated) —
**none of this compiles into a Release/App-Store archive.** Do not tell
Apple a reviewer can set an environment variable on the shipped binary; they
cannot set environment variables on an installed App Store/TestFlight
binary at all, and even if they could, the code path doesn't exist in
Release.

### What a reviewer sees standalone, with zero setup (first launch, no pairing)

1. Launch the app. The 2-screen onboarding gate appears
   (`OnboardingGateView`, `AppRoot.swift:296-303`) — no login wall, no
   account required.
2. Reviewer can inspect the Settings surfaces (Policy & Governance, Trusted
   Machines, Connection settings) and the empty-state Workspaces UI without
   a paired host.
3. The IAP paywall / Lancer Pro purchase button is reachable and testable
   against Apple's own StoreKit sandbox (Apple's IAP sandbox environment
   works against the live TestFlight/App-Store binary — no special build
   flag required, this is the standard StoreKit 2 sandbox path).

**Honest limitation:** without a paired host running `lancerd`, the
reviewer cannot see a live approval card, a real chat thread, or the SSH
terminal populated with real content — those require the companion daemon
by design (this is the entire product; there is no cloud-hosted fallback
in V1, per `ARCHITECTURE.md` §0.1 "the phone never holds an SSH session in
V1... the resident daemon holds session/approval state").

### Recommended path: provide a reviewer-accessible host (owner action)

Because no demo/mock mode ships in Release, the most reliable way to avoid
a Guideline 2.1 (App Completeness / reviewer cannot test) rejection is one
of:

- **(a) Screen recording.** Attach a short video (App Store Connect supports
  video attachments in review notes) showing: pair with 6-digit code →
  agent proposes an action → phone approval card with blast radius → tap
  Approve → host executes → SSH terminal opened inline. This is the
  standard mitigation used by comparable "approval cockpit for your own
  infra" apps when the core value requires infrastructure the reviewer
  doesn't have.
- **(b) A reviewer-reachable demo host.** Stand up a disposable Linux VM the
  owner controls, running `lancerd`, with SSH/relay reachable, and give the
  reviewer a pairing code + basic instructions in the notes. This lets the
  reviewer drive the real flow rather than trust a video. **Requires the
  owner to provision and keep this host alive for the review window** — not
  something an agent can stand up unsupervised (it is a live credentialed
  service).
- **(c) Cite precedent.** Reference established SSH/remote-ops apps (Blink
  Shell, Termius) that ship the same "requires your own reachable host"
  model and have passed review for years, in the notes text above.

**Owner decision needed before submission:** which of (a)/(b) to use. This
doc does not pick for you — building a real demo host is infra + judgment
the owner should make, not an agent.

### Pairing steps if a live host is provided (owner-supplied demo host)

1. On the demo host, run `lancerd pair` (or the equivalent install-flow
   pairing entry point) — it prints a one-time 6-digit code.
2. In the app, open Settings → Connection → "Pair a machine" → enter the
   6-digit code in `RelayPairingSheet`
   (`Packages/LancerKit/Sources/AppFeature/Settings/RelayPairingSheet.swift`).
   **No camera / QR scan step** — this is a plain 6-digit text field.
3. Once paired, dispatch or resume a chat with an installed agent CLI on
   that host; a policy rule marked `ask` will produce an approval card with
   blast-radius detail in the phone's Workspaces/Inbox surface.
4. Trusted Machines → the paired host → "Open Terminal" opens a live,
   daemon-owned PTY session over the relay.

---

## 3. In-app purchase description

- **Product ID:** `dev.lancer.mobile.pro`
- **Type:** Non-Consumable (one-time purchase) — confirmed by
  `Lancer/Lancer.storekit`: `"type" : "NonConsumable"`, no subscription
  group present.
- **Price:** $14.99 (local StoreKit test config value —
  **owner must verify this matches the intended live ASC price tier**; the
  `.storekit` file is a local Xcode testing config, not the ASC source of
  truth).
- **Display name:** Lancer Pro
- **Description (from `Lancer/Lancer.storekit`):** "Full access to Lancer
  Pro features: AI agent approval inbox, SFTP file browser,
  port-forwarding preview, CloudKit sync, and unlimited SSH hosts."
  **VERIFY before submission** that SFTP browser and port-forwarding
  preview are actually shipped/reachable in the build being archived —
  `ARCHITECTURE.md` §0.1 does not list either as ✅ Implemented for V1 (SFTP
  and port-forwarding preview are listed in the feature matrix §3.4 as
  gaps/roadmap items, not shipped V1 surfaces); shipping this exact
  description with unimplemented features risks a 2.3.1 (inaccurate
  metadata) rejection. Cut any bullet not true of the archived build.
- **Restore purchases:** confirm a visible "Restore Purchases" control
  exists in Settings before submission (standard StoreKit 2 requirement,
  Guideline 3.1.1).

## 4. Push notification usage description

Push is used exclusively to deliver governed-approval and Live Activity
updates for agent runs the user's own host is executing — never marketing,
never third-party ad content. The user opts in via the standard iOS
notification permission prompt; the app is fully functional (pairing,
Settings, IAP) without granting it — an unattended run with no reachable
push/attach channel auto-approves only low/medium-risk events after an
8-second grace, and high/critical-risk events always wait for an explicit
decision (`docs/legal/SECURITY_ARCHITECTURE.md` §4.5).

## 5. Encryption / export compliance

**Current build setting:** `ITSAppUsesNonExemptEncryption: false`
(`project.yml:96`).

**Recommendation: keep it `false`.** Lancer uses only encryption that
qualifies for the standard mass-market/publicly-available-algorithm
exemption:

| Use | Mechanism | Exemption basis |
|---|---|---|
| Transport (relay, push-backend, SSH) | TLS 1.2/1.3, negotiated SSH ciphers | Standard protocol — exempt |
| Relay E2E payload encryption | X25519 ECDH + ChaCha20-Poly1305, HKDF-SHA256 (`docs/legal/SECURITY_ARCHITECTURE.md` §3-4) | Publicly available algorithms (RFC 7748 / RFC 8439 / RFC 5869); not the app's primary feature; no custom cryptosystem |
| Local key storage | Apple Keychain (`whenUnlockedThisDeviceOnly`) | Platform feature, Apple's own exemption |
| SSH transport | SwiftNIO + Citadel | Standard protocol library |

None of this is a proprietary encryption algorithm, none is offered as a
general-purpose security product to third parties, and the app's primary
function is agent approval/monitoring, not encryption itself — this matches
Apple's documented criteria for `false` (self-classifying export
compliance, see Apple's guidance linked in
`docs/legal/ENCRYPTION_COMPLIANCE.md`). No code change is needed; just
confirm the `Info.plist`-derived value still reads `false` at archive time
and that no new crypto primitive was added since this doc was written.

---

## 6. Common rejection risks and mitigations (re-derived, current build)

| Risk | Mitigation |
|---|---|
| 2.1 App Completeness (reviewer can't exercise core functionality without external hardware) | Provide a screen recording and/or a reviewer-reachable demo host (§2) — do not claim a DEBUG demo mode ships in Release. |
| 2.5.2 (remote code execution) | App only relays approval decisions; all execution is on user-owned hardware. Cite SSH-client precedent (Blink Shell, Termius). |
| 5.1.1 (privacy/data collection) | `docs/appstore/PRIVACY_NUTRITION_LABEL.md` — only an APNs token is collected, not linked to identity, not used for tracking. |
| 3.1.1 (IAP) | One-time Non-Consumable, no subscription language; Restore Purchases control present; description matches the build's actual feature set (verify SFTP/port-forwarding claims, §3). |
| 4.2 (minimum functionality) | Governed approval loop, chat threads, live SSH terminal, Trusted Machines, Policy & Governance settings are all real, non-placeholder surfaces per `ARCHITECTURE.md` §0.1 Implemented list. |
| Stale/dead permission strings | `NSCameraUsageDescription` describes a QR-scan flow that no longer exists in code (see `PRIVACY_NUTRITION_LABEL.md` note 2) — either wire a real camera use or remove the string before submission; an unused permission string with no corresponding UI is itself a review flag. |

---

## Sources read this session

- `ARCHITECTURE.md` §0.1, §1.1, §11.2, §3.4
- `docs/legal/SECURITY_ARCHITECTURE.md` §2.1, §3, §4, §4.5
- `docs/legal/APP_REVIEW_NOTES.md` (superseded — QR-pairing/SSH-only description is stale)
- `docs/legal/ENCRYPTION_COMPLIANCE.md`
- `project.yml` lines 60-96 (Info.plist properties, `ITSAppUsesNonExemptEncryption`)
- `Packages/LancerKit/Sources/AppFeature/DebugSeeder.swift` (DEBUG-only gate)
- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` lines 293-313
- `Packages/LancerKit/Sources/AppFeature/Settings/RelayPairingSheet.swift` (current pairing UI is a 6-digit field, not a scanner)
- `Lancer/Lancer.storekit`
