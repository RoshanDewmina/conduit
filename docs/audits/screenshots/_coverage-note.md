# Phase 4 — Screenshot Coverage Note

**Device:** iPhone 17 Pro simulator (`095F8B3A-FEA3-4031-A2A5-561755740730`), iOS 26-class runtime.
**Build:** `Lancer` scheme, Debug, `dev.lancer.mobile`, app-target build SUCCEEDED 2026-06-23 (0 warn / 0 err).
**Appearance:** app is fixed-dark (ignores system appearance) — all shots dark except intentional light variants.
**Method:** `SIMCTL_CHILD_LANCER_GALLERY=<route>` launch → settle → `simctl io screenshot`. 53 gallery routes + 1 live boot = **54 shots**. No secrets/PII (gallery uses mock data).

## Capture caveat (important)
8 routes first captured **blank white** (NewChat, NewChat-real, chat-overlays light/dark, onboarding-redesign, onboarding-redesign-policy, onboarding-caution, onboarding-paired) because those views **fade-in / load async** and 1.6 s wasn't enough. Re-captured at 4.5 s → all rendered with content (verified by file size 140 KB–1.5 MB and visual spot-check). **This fade-in delay is itself a UX note** (Phase 7): several core screens render empty for >1.5 s on entry.

## Coverage vs screen-inventory.md
| Inventory area | Covered by | Notes |
|---|---|---|
| Onboarding (ON-1..L) | onboarding-redesign, -pair, -policy; onboarding (legacy) + 6 legacy phases | Production redesign + legacy both captured. AccountEntry not a gallery route → live-nav only (deferred, owner done w/ live relay). |
| Home (NAV-1) | main-navigation/home + system-states/live-boot | live-boot = real empty "Connect a machine" state |
| Sidebar (NAV-2) | shell-sidebar | |
| New Chat (NAV-3) | newchat, newchat-real, newchat-live | |
| Chat/thread (NAV-4) | chat, chat-overlays, -light, -dark | |
| Inbox (NAV-5) | inbox-typed, shell-inbox, approval | |
| Fleet (NAV-6) | shell-fleet, shell-fleet-relay | relay-host loading-state defect not reproduced in gallery (needs live relay — owner skipped) |
| Settings (NAV-7) | shell-settings, settings-terminal/-secrets/-policy/-shortcuts, trust, billing, paywall, compare | |
| Terminal (TERM) | blocks, session, keyboard, orb-* (5 connection states) | |
| Files/diff (CHAT-3/4) | diff, filepreview | |
| Drift/quota (MCH-5/6) | drift | quota/usage gallery route absent → code-only evidence |
| Agents sprawl (AGT) | hud, statusheader, features, proof | the 8 AGT detail views are not individually gallery-routed |
| Design system | components, states, scaffold-demo, review | full DS catalog |

## Not capturable this run (+ why)
- **Live relay-connected / approval-live / APNs states** — owner skipped live relay E2E; gallery `approval`/`inbox-typed` + `shell-fleet-relay` stand in.
- **AccountEntry, real first-run onboarding sequence** — onboarding already marked seen on this sim; gallery redesign routes cover the screens. (Could `simctl` erase + relaunch to force first-run; deferred as low-value given gallery coverage.)
- **8 agent-detail views, quota/usage, worktrees, hosted-cloud V2 UI** — no gallery routes; evidenced by code (feature matrix) not screenshot. Flagged for the brief as consolidation/defer targets.
- **Permission prompts** (camera for QR, notifications) — system dialogs, not gallery-routable.

## Headline visual finding from captures
Home shows **"2 agents need you / 2 conversations blocked"** while Machines is the empty "Connect a machine" state — seeded/demo counters leak into a zero-state. Inconsistent empty-state handling (Phase 9 Critical/High candidate).
