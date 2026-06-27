# Editorial redesign verification manifest

Visual source: `/Users/roshansilva/Downloads/Claude design conversation continuation/Lancer App.dc.html`.
The reference board is a 376×796 compact canvas. The implementation was reviewed
at the closest available iPhone simulator viewport (368×800) and on the iPad
split-view shell (iPad Pro 11-inch M5, 551×800 capture).

| Surface | Simulator state | Result |
|---|---|---|
| First-run onboarding | `LANCER_GALLERY=onboarding-redesign` | Sand canvas, terracotta editorial hero, three-step copy, policy controls, and 44-point actions reviewed. The XCUITest navigation and policy-selection flow passes. |
| Command Home | `LANCER_GALLERY=home` | Default Command Home layout reviewed with attention band, New Chat action, machine entry point, and populated recent work. |
| Sidebar | `LANCER_GALLERY=shell-sidebar` | Home, Inbox, Machines, Settings, search, and recent-thread hierarchy reviewed. |
| Inbox | `LANCER_GALLERY=shell-inbox` | Populated high/medium/low-risk approval cards, non-color risk labels, and approve/deny affordances reviewed. |
| Machines | `LANCER_GALLERY=shell-fleet` | Saved-machine detail surface and reconnect affordances reviewed; this replaces Fleet as a root destination. |
| Settings | `LANCER_GALLERY=shell-settings` | Nested settings groups, relay pairing, security, and reset state reviewed. |
| Live session error state | `LANCER_GALLERY=session` | The dark terminal context and authentication error surface reviewed without a live host credential. |
| iPad shell | `LANCER_UITEST_RESEED=1`, `LANCER_DESTINATION=home` | `NavigationSplitView` renders a persistent sidebar and Command Home detail; no tab bar is present. |

## Interaction and accessibility checks

- The first-run redesign’s forward, back, and policy-choice XCUITests pass on the iOS 27 iPad simulator.
- `SidebarShellStateTests` cover Home as the default, Home → Machines presentation, and return routing from Settings.
- Text uses Dynamic Type-scaled custom fonts. Cards and action rows retain semantic labels, text labels for status, and at least 44-point primary controls.
- Motion uses `LancerMotion`; shell and onboarding transitions resolve to no animation under Reduce Motion. Repeating DesignSystem indicators already short-circuit under Reduce Motion.
- Haptics are limited to explicit selections, successful pairing/approval, and actionable failures. Streamed terminal output remains silent.

## Performance review

The Home and Inbox scroll paths use `LazyVStack` and stable `ForEach` identities; terminal presentation remains isolated in `SessionWorkspaceContainer`, preventing streamed output from invalidating the Home or Inbox hierarchies.

Focused 25-second ETTrace 1.1.0 simulator captures were collected on iPhone 17 Pro/iOS 27 after temporarily linking the profiler (the target wiring was removed before handoff). Processed flamegraphs are retained locally at `/tmp/codex-ios-ettrace-lancer/run-{home,inbox,session}/output_259.json`.

| Flow | Active main-thread time | Finding |
|---|---:|---|
| Populated Command Home first render + settled state | 0.293 s / 25.012 s | No app-owned hot frame; activity is standard SwiftUI layout and Core Animation commit work. |
| Populated Inbox first render + settled state | 0.173 s / 25.011 s | No app-owned hot frame; the recorded metadata/layout work is first-render cost. |
| Session harness first render + error state | 3.455 s / 25.012 s | Dominated by simulator launch/dyld and render work. No live SSH credential was available, so this is not a terminal-streaming throughput measurement. |

The profiler found 0% application samples without a loaded binary. ETTrace's own simulator framework and Apple system frameworks remain unsymbolicated under the current Xcode 27 beta toolchain; this does not mask an app-owned stack. A real-host terminal-stream trace remains a manual follow-up.
