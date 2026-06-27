# Onboarding Redesign — Swift port spec (FLOW 01)

Source design: `~/Downloads/Lancer GitHub repo/Lancer Onboarding.dc.html`
Rendered reference: `.design-shots/onboarding-design-wide.png` (6 frames, left→right)
Branch: `opencode/onboarding-redesign`

## Goal

Replace the current 5-screen `OnboardingView` flow (per-OS SSH commands + cloud-compute
escape hatch) with the design's **4-step** flow:

1. **Welcome**  (hero)
2. **Pair the bridge**  → sub: **Scan QR** → sub: **Bridge paired**
3. **How cautious?**  (policy presets)
4. **You're set**  (first-run / demo approval)

## Architecture (file decomposition — DO NOT let two agents write the same file)

Each *screen* is its own file producing a self-contained `View` struct that renders ONLY the
**scrollable body content** for that screen — NO top bar, NO footer CTA. The shell
(`OnboardingView.swift`, owned by the lead, not the swarm) provides the consistent chrome and
footer and composes the screens.

| File (in `Packages/LancerKit/Sources/OnboardingFeature/`) | Struct | Owner |
|---|---|---|
| `OnboardingChrome.swift` | shared top bar + footer + step dots | LEAD (not swarm) |
| `OnboardingPairing.swift` | pairing helpers (QR, labels) | LEAD (not swarm) |
| `OnboardingView.swift` | shell / coordinator / state machine | LEAD (not swarm) |
| `OnboardingWelcomeScreen.swift` | `OnboardingWelcomeScreen` | agent 1 |
| `OnboardingPairScreen.swift` | `OnboardingPairScreen` | agent 2 |
| `OnboardingScanScreen.swift` | `OnboardingScanScreen` | agent 2 |
| `OnboardingPairedScreen.swift` | `OnboardingPairedScreen` | agent 3 |
| `OnboardingCautionScreen.swift` | `OnboardingCautionScreen` | agent 3 |
| `OnboardingFirstRunScreen.swift` | `OnboardingFirstRunScreen` | agent 4 |

## Consistency rules (the owner cares about this most)

- **Top bar on EVERY step** (provided by the shell — screens must NOT draw their own):
  - **Leading control top-LEFT**, **page-indicator dots top-RIGHT** — slot always reserved so
    layout never shifts horizontally between screens.
  - **Page-indicator dots** — one dot per step (4), active dot is wider + `t.accent`, others
    `t.border`. Shown on ALL steps. Reuse the `stepDots` pattern from current `OnboardingView.swift`.
  - **NO "STEP 2 / 4" text labels anywhere.** Delete them from the design.
  - **Per-step leading control (owner feedback):**
    | Step | Leading control |
    |---|---|
    | Welcome (0) | none (reserved empty slot) |
    | Pair the bridge | back ‹ → Welcome |
    | Scan QR | **✕ close** → return to Pair (NOT a back chevron) |
    | Bridge paired | **none** (can't undo a pairing) |
    | How cautious? | back ‹ → previous |
    | You're set | back ‹ → previous |
- All screens use `@Environment(\.lancerTokens) var t` for colors/radii. Never hardcode colors.
- All screens wrap content in `ScrollView(.vertical, showsIndicators: false)` and
  `.frame(maxWidth: 520).frame(maxWidth: .infinity, alignment: .leading)` and
  `.dynamicTypeSize(...DynamicTypeSize.accessibility3)` — match existing OnboardingView screens.
- Horizontal padding 18 throughout (match existing).

## Reference code (READ THESE — every component you need already has a working example)

- `Packages/LancerKit/Sources/OnboardingFeature/OnboardingView.swift`
  - `screen1Welcome` → exact hero you are porting (SpectrumBar, LANCER label, big hero text, description)
  - `screen3Preset` + `presetRow(_:)` → exact policy-row visual you are porting
  - `screen5Success` → exact green-check + "bridge paired" + E2E card you are porting
- `Packages/LancerKit/Sources/OnboardingFeature/BridgePairingView.swift`
  - `qrSection`, `pairingStatusCard`, the curl `DSQuoteBlock(title:"INSTALL", …)`, copy button — the pair screen reuses these
- Components: `DSButton`, `DSChip`, `DSQuoteBlock`, `DSIconView(.copy/.check/.key/.chevronRight)`,
  `SpectrumBar`. Tokens in `DesignSystem/Tokens.swift`.

---

## Screen specs (exact copy + layout)

### 1. `OnboardingWelcomeScreen` (frame 01)
Port `screen1Welcome` from current OnboardingView **with ONE change: the hero block is moved
UP** so the first line of the hero ("agents ask.") sits at roughly the same vertical height as
the "Pair the bridge" heading on screen 2 (i.e. near the top, NOT vertically centered).
Practically: remove the large `Spacer`/top padding that centers it; use a modest top padding
(~24–32) so content starts high.

Contents top→bottom:
- `SpectrumBar(mode: .working, height: 8)` (full width, hpad 18)
- `LANCER` mono label (uppercase, kerning, `t.text3`)
- Hero (monospaced, size 47, weight bold, lineSpacing 0, tracking -0.025):
  - `agents ask.` → `t.text`
  - `you approve.` → `t.text3`
  - `work resumes.` → `t.accent`
- Description (`dsSansPt(14.5)`, `t.text3`):
  `Your coding agents run on your own machine. Lancer taps you only when one needs a decision — and resumes the moment you choose.`

Footer CTA (shell renders): primary `Get started`.

`struct OnboardingWelcomeScreen: View { var body: some View }`  — no params needed.

### 2. `OnboardingPairScreen` (frame 02 "Pair the bridge")
Inputs:
```swift
struct OnboardingPairScreen: View {
    @ObservedObject var client: E2ERelayClient   // from SSHTransport
    let qrImage: Image?                            // pre-rendered by shell via OnboardingPairing
    let pairingCode: String
    let onScanTapped: () -> Void
    @Environment(\.lancerTokens) private var t
    var body: some View { ... }
}
```
Contents:
- Heading `Pair the bridge` (monospaced 24 bold, `t.text`).
- Description (`dsSansPt(14.5)`, `t.text3`):
  `Run this where your agents live. It dials out and prints a QR — no SSH, no port-forwarding.`
- Install command box — reuse the `DSQuoteBlock(title:"INSTALL", tags:[], message:"curl -fsSL conduit.dev/install | sh", tone:.ok)` look from BridgePairingView, OR a sunken code row with a copy button (`UIPasteboard.general.string = …`, copy/check icon feedback). Command string: `curl -fsSL conduit.dev/install | sh`.
- Pairing-code block:
  - tiny label `OR ENTER PAIRING CODE` (mono, uppercase, `t.text3`)
  - `pairingCode` big (mono 26 bold, kerning 4, `t.text`) centered in a bordered/sunken card
  - sublabel `auto-pairs once the install finishes` (mono 11, `t.text3`)
- (No advanced-SSH row — that path is dropped from onboarding.)

Footer CTA (shell): primary `Scan QR code` (calls `onScanTapped`).

### `OnboardingScanScreen` (frame 02 "Scan QR · camera")
Inputs:
```swift
struct OnboardingScanScreen: View {
    let onScan: (String) -> Void          // forward to QRScannerView
    let onUnavailable: (String) -> Void
    let onEnterCodeInstead: () -> Void
    @Environment(\.lancerTokens) private var t
}
```
Contents:
- Tiny label `SCAN TO PAIR` (mono uppercase, `t.text3`).
- Embed `QRScannerView(onScan: onScan, onUnavailable: onUnavailable)` inside a viewfinder frame:
  a square (~220pt) with **corner brackets** drawn in `t.accent` (L-shaped lines at the 4 corners).
  **Position it HIGH** (owner feedback) — top-aligned, modest gap below the `SCAN TO PAIR` label,
  NOT vertically centered. On Simulator the camera is unavailable → QRScannerView calls `onUnavailable`.
- Caption `Point at the QR code printed in your terminal` (`dsSansPt(13.5)`, `t.text3`, centered).
- Status row `searching…` with a small pulsing accent dot.
- Footer CTA (shell): secondary/ghost `Enter 6-digit code instead` (calls `onEnterCodeInstead`).

### `OnboardingPairedScreen` (frame 02 "Bridge paired")
Port `screen5Success` from current OnboardingView. Inputs:
```swift
struct OnboardingPairedScreen: View {
    let hostName: String      // e.g. "Dev VPS"
    let agents: String        // e.g. "claude-code · codex"
    @Environment(\.lancerTokens) private var t
}
```
Contents:
- Green check circle (74pt, `t.ok` fill, white checkmark, soft glow) — exactly as `screen5Success`.
- Heading `Bridge paired` (`t.text`).
- Description `Your phone and the bridge are connected. Approvals now route straight here.`
- Info card (`t.surface`, bordered, r4): row with `hostName` + `agents`, and a trailing `E2E`
  badge (`t.ok` on `t.okSoft`) with label `End-to-end encrypted relay`. Match the E2E card in screen5Success.

Footer CTA (shell): primary `Continue`.

### 3. `OnboardingCautionScreen` (frame 03 "How cautious?")
Port `screen3Preset` visual but with the design's **3 levels**. Inputs:
```swift
struct OnboardingCautionScreen: View {
    @Binding var level: OnboardingCautionLevel   // enum defined in OnboardingChrome.swift by LEAD
    @Environment(\.lancerTokens) private var t
}
```
`OnboardingCautionLevel` (the LEAD defines this; agent 3 just uses `.cautious/.balanced/.bypass`,
`.title`, `.detail`, `.recommended`, `.tone`):
- `.cautious`  — title `Cautious`,  detail `Auto-allow read-only · ask on every write · deny secrets & network`, tone warn
- `.balanced`  — title `Balanced`,  detail `Auto-allow safe writes · ask on deletes, network & secrets`, tone accent, **recommended (default selected)**
- `.bypass`    — title `Bypass`,    detail `Auto-allow everything except critical · for trusted repos`, tone danger

Contents:
- Heading `How cautious?` (monospaced 24 bold).
- Description `Set the default policy. You can change any rule later — unmatched actions always ask.`
- Three rows (reuse `presetRow` visual: a left color bar 3pt wide × ~52 tall that is `t.accent`
  when selected else `t.border`, title mono bold, detail sans). The `Balanced` row shows a small
  `recommended` chip/label. Tapping a row sets `level` with a short animation.

Footer CTA (shell): primary `Connect & finish`.

### 4. `OnboardingFirstRunScreen` (frame 04 "You're set") — NEW screen
Inputs:
```swift
struct OnboardingFirstRunScreen: View {
    let cautionTitle: String          // e.g. "balanced" (lowercased level title)
    let onRunDemo: () -> Void
    @Environment(\.lancerTokens) private var t
}
```
Contents:
- Green check circle (smaller is fine) + heading `You're set`.
- Description: `Bridge paired and policy \(cautionTitle). Run a safe demo to watch an approval land on your phone.`
- Checklist card (3 rows):
  - `✓ Install & pair the bridge`  (done — accent/ok check)
  - `✓ Set how cautious it should be`  (done)
  - `3  Approve the first action it escalates`  (pending — number in a circle, muted)
- Demo card (`t.surface`, bordered): header `Claude Code · demo`, body `nothing will actually run`,
  trailing `SAMPLE` badge (neutral/accent). This is a static mock — no real agent.

Footer CTA (shell): primary `Run the demo approval` (calls `onRunDemo`).
**NO "Skip to inbox" button** (owner feedback — removed).

---

## Pairing wiring (LEAD owns the shell; agents just consume the contracts above)

The shell owns one `E2ERelayClient` (passed from `AppRoot` as `relayClient`, fallback to a new
one). On entering step 2 it calls `beginPairingSession()`, renders the QR via
`OnboardingPairing.renderQR(client:code:)`, and `connect()`s. It observes `client.pairingState`;
when it becomes `.paired` it auto-advances to the Bridge-paired sub-screen. The Scan screen's
`onScan` payload and manual 6-digit code are applied via the same logic as BridgePairingView
(`applyScannedPayload` / `applyCode`). Demo approval (step 4) stays mocked this phase.

## Build / acceptance (LEAD verifies — agents need NOT get a green build)

- Agents: produce the file matching the struct signature + copy + visual spec above. Use only
  existing DS components & tokens. Do NOT add the top bar/footer (shell provides them).
- LEAD: `cd Packages/LancerKit && swift build`, then app-target build via XcodeBuildMCP,
  launch gallery route `onboarding-redesign`, screenshot light+dark, diff against
  `.design-shots/onboarding-design-wide.png`, confirm chrome consistency across all 4 steps.
