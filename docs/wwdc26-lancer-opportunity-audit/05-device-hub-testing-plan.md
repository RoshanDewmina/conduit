# 05 — Device Hub testing plan

> **Staleness banner (2026-07-08):** predates Cursor-shell reconciliation; navigation claims
> below (sidebar/split-view IA) are **stale**. Production UI is the Cursor shell — see
> `ARCHITECTURE.md` §4.1.

> Grounded in a local, read-only Device Hub/`devicectl` audit run against this machine on
> 2026-07-02 (Xcode 27.0 build `27A5194q`, `devicectl` 629.3 from `Xcode-beta.app`), plus the
> July 2 test-run report (`docs/test-runs/2026-07-02-relay-siri-liveactivity-session-report.md`)
> and `docs/KNOWN_ISSUES.md`/`docs/PUBLISH_READINESS_CHECKLIST.md`. All `devicectl` command forms
> below were verified locally against `devicectl help` output — none are invented.

## What Device Hub actually is here

Apple documents Device Hub as an Xcode **UI surface** (window that unifies device/simulator
management) — the automation-relevant layer underneath it is `devicectl`/CoreDevice, which is
what this plan actually drives. Local device inventory as of this audit:

- Physical iPhone: visible, paired, booted, iOS 27.0, Developer Mode enabled.
- Physical Apple Watch: listed but **unavailable** locally.
- Simulators: iPhone/iPad/Watch simulators exist for iOS/watchOS/iPadOS 27.0; `iPhone 17 Pro` was
  booted at audit time.
- The `Lancer` scheme's destinations include the physical iPhone and iPhone/iPad simulators —
  **watch simulators are not compatible with the iOS app scheme**; `LancerWatch` has its own,
  separate watchOS simulator destinations (the Watch app is not embedded in the iOS bundle per
  `project.yml:138`, so this split is expected, not a bug).

## Verified `devicectl` command forms

Use exactly these — do not invent flags not present in local `devicectl help` output:

```bash
xcrun devicectl list devices --json-output <path>
xcrun devicectl list devices --filter "Name CONTAINS 'iPhone' AND State = 'available'"
xcrun devicectl device install app --device <device> <path-to-Lancer.app>
xcrun devicectl device process launch --device <device> --terminate-existing dev.lancer.mobile
xcrun devicectl device process launch --device <device> --environment-variables '{"LANCER_DESTINATION":"inbox"}' --terminate-existing dev.lancer.mobile
xcrun devicectl device capture screenshot --device <device> --destination <path>.png
xcrun devicectl device settings appearance --device <device> --mode dark --text-size extra-extra-extra-large --increase-contrast on --reduce-motion on --reduce-transparency on
xcrun devicectl device settings biometrics --device <device> --enable
xcrun devicectl device simulate biometrics --device <device> --success
```

`--json-output` on `list devices` and structured JSON from `process launch`/`install app` make
this usable as CI-adjacent automation, not just interactive debugging. **Not found in local
`devicectl help`:** any network/offline-condition simulation subcommand — do not assume one exists;
use the alternative offline-testing methods in the matrix below instead.

## Test matrix

| Area | Configuration | Method | Current coverage | Gap to close |
|---|---|---|---|---|
| Small iPhone (no Dynamic Island) | iPhone SE-class simulator/device if available | `devicectl`/simulator boot + manual pass | Not separately covered — `LancerUITests` has 9 methods total, none device-size-parameterized | Add at least one non-Dynamic-Island device to the regression pass; Live Activity Lock Screen presentation must degrade gracefully with no Island |
| Large iPhone / Dynamic Island | Physical iPhone (confirmed available, iOS 27.0) | Physical-device install/launch/screenshot | ✅ C2 physical-device loop passed 2026-06-23; Live Activity relay-dispatch wiring not yet visually confirmed live (2026-07-02 report) | Confirm Live Activity on Lock Screen/Dynamic Island for the relay-dispatch path specifically |
| Portrait vs. landscape | Both orientations | `devicectl` rotate (or manual) + screenshot | ✅ Landscape Dynamic Island fixed and visually re-confirmed via Xcode `RenderPreview` (2026-07-02, §13) | RenderPreview is fast but is not a real device; do one physical-device landscape pass before shipping |
| iPad split view / resizing | iPad simulator, multiple window sizes | `devicectl` install + resize | `Lancer` scheme supports iPad simulator destinations; no iPad-specific UI assertions found | Add iPad split-view smoke pass — sidebar/split-view IA (`SidebarShellState.swift`) is the primary navigation model and has not been iPad-verified per this audit |
| Light / dark appearance | Both | `devicectl device settings appearance --mode light/dark` | Visual consistency confirmed in a prior polish pass (2026-06-22 design QA); app is fixed-dark per that report's note "app is fixed-dark (ignores system appearance)" | **Verify this is still true and intentional** — if the app ignores system appearance entirely, `--mode light` testing is moot; confirm before spending cycles on it |
| Increased Contrast | On | `devicectl device settings appearance --increase-contrast on` | Not separately covered | Add to regression pass, especially for `DSStatusDot` color-only status (flagged WCAG 1.4.1 gap in `docs/KNOWN_ISSUES.md` §4b) |
| Reduce Motion | On | `devicectl device settings appearance --reduce-motion on` | ✅ Fixed and verified (commit `53bac151`) — all 7 design-system animations gate on `accessibilityReduceMotion` | Regression-only pass needed, not new work |
| Dynamic Type (through accessibility sizes) | `extra-extra-extra-large` and above | `devicectl device settings appearance --text-size extra-extra-extra-large` | Partial — VoiceOver labels fixed 2026-07-02 session for icon-only controls; hardcoded `.font(.system(size: N))` literals remain on `DSApprovalBanner.swift:26` (safety-critical approval copy), `InboxApprovalCard.swift:121`, `DSOfflineState.swift:26/52`, `ChatInputBar.swift:115` | Fix the hardcoded sizes (P3 in `docs/KNOWN_ISSUES.md` §4b), then re-run this pass — the approval banner is the highest-priority one since it's safety-critical |
| Long project/machine/file/command names | Synthetic long strings | Manual seed data + screenshot | Watch activity output truncates to 200 chars (`PhoneWatchConnector.swift:152`); conversation pagination has test coverage (`ChatConversationRepositoryTests.swift:271`) | No device UI stress test for very long machine/host names specifically — relevant given the recent "two machines both named 'Relay host' collapsed into one Home card" bug class (§5 of the 2026-07-02 report); add a long/duplicate-name device pass |
| Offline / degraded network | Wi-Fi off, cellular-only, flaky relay | No `devicectl` network-simulation subcommand found; use physical Wi-Fi toggle, daemon kill, or relay-server-side latency injection instead | Unit-level offline/reconnect coverage exists (`AttentionItemTests.swift:136`); the 2026-07-02 session's own simulator testing was repeatedly destabilized by rapid re-pairing churn (self-inflicted test-environment issue, explicitly disclosed) | Needs an actual physical-device offline/reconnect pass, not just unit tests — the stale-socket reconnect race (§10 of the 2026-07-02 report) was found exactly this way |
| Backgrounding / relaunching | Background → wait → foreground; force-quit → relaunch | `devicectl device process launch --terminate-existing` | **Confirmed gap:** `AppRoot.swift:338` ends all Live Activities on background — this test will currently fail against the documented "push-driven while closed" claim | This is the #1 test to run once `04-live-activities-and-dynamic-island.md`'s lifecycle fix lands — it directly falsifies or confirms the current biggest doc/code mismatch |
| Multiple active agents / multi-machine | ≥2 relay machines, ≥2 concurrent runs | Physical pairing + relay dispatch | Multi-machine fold-in bugs found and fixed live (§5 of 2026-07-02 report, two rounds); Siri run-control has **no** multi-run disambiguation (`ActiveRunRegistry.swift:4` stores IDs only) | Add a standing 2-machine, 2-concurrent-run regression scenario — this exact configuration has produced 3 confirmed bugs in one week |
| Large activity histories | Hundreds+ of conversations/turns | Seed GRDB directly + device UI pass | Pagination unit-tested (`ChatConversationRepositoryTests.swift:271`); no device-level stress test found | Add a seeded-large-history device pass, watching scroll performance and FTS search latency |
| Large diffs / terminal output | Multi-thousand-line diff or output blob | Seed + device pass | `TerminalEngine/BlockRenderer.swift:214-239` caps per-block lines and total block count (`docs/KNOWN_ISSUES.md` §4) | Regression-only; the cap logic is already verified sound |
| Apple Watch companion | Physical Watch (unavailable locally) or watchOS simulator | `devicectl`/Watch pairing flow, separate `LancerWatch` scheme | WCSession sync + transfer tests exist (`WatchApprovalTransferTests.swift:5`, `PhoneWatchConnector.swift:80`); Watch is not embedded, ships separately | **Owner-gated:** no physical Watch was available this audit; needs a dedicated device pass when hardware is available |
| Live Activity states (7 content states) | connected, streaming, needs-approval (1), multiple approvals (3), just-approved, reconnecting, over-budget | Xcode `RenderPreview` (fast) + physical-device pass (authoritative) | ✅ All 7 previewed and visually confirmed correct via `RenderPreview` (2026-07-02, §12); physical-device relay-dispatch wiring not yet visually confirmed | Do one physical-device pass covering at least the needs-approval and over-budget states, since those are the safety-relevant ones |
| Permission-denied states (notifications, biometrics if reintroduced) | Deny each permission | Manual + `devicectl device settings biometrics` | Not explicitly audited this session | Add explicit "notifications denied" pass — approvals currently rely heavily on push; a denied-notifications user has a materially worse experience that should be tested, not assumed |
| Empty / loading / stale / failure / disconnected states | Fresh install, network kill mid-load, relay down | Manual + relay-server toggling | Empty states exist on core surfaces (`InboxView.swift:102-103`, `FleetView.swift:140-141`, `ActivityView.swift:66`); "No machines reachable" vs "No machines paired" distinction fixed 2026-07-02 (`docs/KNOWN_ISSUES.md` §6, last entry) | Regression-only for the fixed cases; add a first-run (truly empty, zero machines ever paired) pass since that's a distinct state from "paired-but-offline" |

## Screenshots and diagnostics to capture per regression pass

- `devicectl device capture screenshot` for each of: Home (empty), Home (active run), Inbox (0/1/3+
  pending), Live Activity Lock Screen, Dynamic Island expanded/compact/minimal (portrait +
  landscape), Machines list (2+ machines, mixed online/offline), Settings → Paired Machines.
- Crash/spin/hang capture via Device Hub's diagnostic-report path when any test above produces
  unexpected behavior — attach the `.ips`/sysdiagnose alongside the screenshot, not just a verbal
  description.
- App-data container snapshot (`devicectl device app-data`-family commands, if present in a given
  Xcode 27 point release — verify with `devicectl help` at test time, since this class of command
  is the most likely to have changed between betas) before/after a destructive test (e.g. large
  history seeding), so a regression can be diffed against a known-good container.

## Regression process

1. Run the full matrix above after any change touching: Live Activity lifecycle, relay
   pairing/machine identity, Siri intents, or accessibility-affecting design-system primitives.
2. Physical-device passes are authoritative for anything push/APNs/Face-ID/Watch-related —
   simulator-only verification for these has already produced false confidence at least once
   (Live Activity relay-dispatch wiring is "code-verified" but not "visually confirmed," per the
   2026-07-02 report's own explicit distinction between the two).
3. Any new `devicectl` command used in automation must first be confirmed against a fresh
   `devicectl help` run on the CI/dev machine's actual installed Xcode version — command surface
   has already shifted across this project's own Xcode-beta point releases.
