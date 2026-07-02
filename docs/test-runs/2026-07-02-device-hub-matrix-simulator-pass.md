# Device Hub matrix — simulator pass

Date: 2026-07-02
Runner: Claude Sonnet 5
Scope: as much of `docs/wwdc26-lancer-opportunity-audit/05-device-hub-testing-plan.md`'s matrix as
is testable via simulator, following the same-day live-testing session
(`docs/test-runs/2026-07-02-wwdc26-audit-phase1-implementation.md`). Physical-device-only rows are
explicitly flagged, not faked.

## Method

Simulators used: `iPhone 17 Pro` (095F8B3A-FEA3-4031-A2A5-561755740730, primary), `iPad Pro
11-inch (M5)` (4E1C92AC-EBC8-45C6-8EE1-0B4FED619380). Seeded via the documented DEBUG launch
seams (`LANCER_SEED_DEMO=1`, `LANCER_DESTINATION=<route>`) per `.claude/rules/ios-ui-and-gallery.md`.
Accessibility state set via `xcrun simctl ui <device> <option>` (appearance, increase_contrast,
content_size — all confirmed supported by this Xcode 27 simulator runtime; reset to defaults after
each check).

**Confirmed tooling limitation, consistent with the same-day session's own finding:** raw HID taps
(`ios-simulator` MCP's `ui_tap`) and even a system-level permission alert did not respond to taps
in this headless Xcode-beta/iOS27 environment during this pass — the notification-permission
dialog on the iPad simulator could not be dismissed via tap despite a valid `snapshot_ui`
`elementRef` resolving correctly. Worked around by using simulators already past that dialog, or
avoiding routes that trigger it.

## Results by matrix row

| Row | Result | Evidence |
|---|---|---|
| **iPad split view / resizing** | ✅ **PASS — newly verified, was previously untested** | iPad Pro 11" screenshot shows the sidebar (Lancer branding, New chat, search, Home/Machines nav, Recent/Archived) + detail pane ("Good evening / All clear tonight.") rendering correctly side-by-side. This closes the "no iPad-specific UI assertions found" gap noted in the plan. |
| **Light / dark appearance** | ✅ **PASS — regression confirmed** | `simctl ui appearance light` produced a byte-identical screenshot to the prior dark-mode one — confirms the app is still intentionally fixed-dark (ignores system appearance), matching the 2026-06-22 design QA finding. Not a bug; documented, unchanged behavior. |
| **Increased Contrast** | ✅ **PASS — no crash/rendering issue** | `simctl ui increase_contrast enabled` applied cleanly, app continued rendering normally. Did not separately re-verify the `DSStatusDot` color-only-status WCAG gap noted in `KNOWN_ISSUES.md` §4b — that's a design-system-level finding, not something this pass's screenshots newly confirm or refute. |
| **Dynamic Type (max accessibility size)** | ✅ **PASS — the safety-critical row** | Set `content_size accessibility-extra-extra-extra-large`, seeded a real pending "Claude Code / HIGH RISK" approval, landed on Inbox. The "WAITING ON YOU / 4 conversations blocked" banner and the approval card's agent/risk labels all render legibly at max size — no clipping, no truncation, text wraps correctly. This directly addresses the `KNOWN_ISSUES.md` §4b flag on `DSApprovalBanner.swift:26`/`InboxApprovalCard.swift:121` hardcoded font sizes: **at this specific screen/state, the hardcoded sizes did not visibly break at max Dynamic Type** — screenshot evidence, not a code fix (the hardcoded literals are presumably still in the source; this only confirms they don't currently produce a visibly broken result on this screen). |
| **Reduce Motion** | ✅ **Regression-only, not independently re-verified this pass** | Already fixed and verified (commit `53bac151`, all 7 design-system animations gate on `accessibilityReduceMotion`) — not re-tested live this pass since nothing in today's changes touches animation code. |
| **Multi-machine name collision** | 🔶 **Observed, not newly tested** | The iPhone 17 Pro simulator's persisted Keychain-backed pairing state (from repeated same-day testing) shows exactly the historical bug pattern — 3 machines all displayed as "Relay host," indistinguishable. This is leftover test-session state, not a fresh repro, so it doesn't confirm or refute whether the fix from `docs/KNOWN_ISSUES.md` §6 (last entry, the "No machines reachable" vs "No machines paired" distinction) still holds — it's just visible evidence the underlying default-name collision itself is easy to reproduce by accident, reinforcing that row's existing recommendation to add a standing regression scenario for it. |
| **Empty / first-run state** | ⚠️ **Could not test on this simulator** | The same persisted Keychain pairing state that produced the above also means this simulator can't show a genuine zero-machines-ever-paired first run without an erase, which would destroy other useful accumulated state. Not tested this pass — would need a freshly-erased simulator or a new one never used for pairing. |
| **Live Activity states (7 content states)** | ✅ **Regression-only, not re-run this pass** | Already visually confirmed via Xcode `RenderPreview` in the earlier same-day session (`docs/test-runs/2026-07-02-relay-siri-liveactivity-session-report.md` §12). Not re-run this pass — Xcode.app wasn't open (RenderPreview requires it) and today's Live Activity changes were to lifecycle/trigger logic, not the content-state view rendering RenderPreview exercises, so this row is unaffected by anything changed today. |
| **Small iPhone (no Dynamic Island)** | ⚠️ **Not tested this pass** | `iPhone 17e` simulator is available but wasn't booted this pass due to time — still an open gap from the original plan. |
| **Portrait vs. landscape** | ✅ **Regression-only, prior evidence stands** | Landscape Dynamic Island fix already visually confirmed via `RenderPreview` in the earlier session (§13). Not re-run this pass for the same reason as the Live Activity states row. |
| **Backgrounding / relaunching** | ✅ **Confirmed indirectly** | This is the row the whole day's Live Activity lifecycle work (background-`.endAll()` removal, grace-period fix, `sendMessage` race fix) was built and live-verified against — see `docs/test-runs/2026-07-02-wwdc26-audit-phase1-implementation.md` Findings 4-5, confirmed live on the physical device, not simulator. |
| **Offline / degraded network** | ⚠️ **Not tested this pass** | No `devicectl`/`simctl` network-condition-simulation subcommand found (consistent with the plan's own note). Would need physical Wi-Fi toggle or daemon-kill on a real device. |
| **Apple Watch companion** | ⚠️ **Owner-gated, not tested** | No physical Watch available. watchOS simulators exist locally (confirmed via `list_sims`) but were not exercised this pass. |
| **Permission-denied states** | ⚠️ **Blocked by the tooling limitation above** | Intended to test "notifications denied" but couldn't reliably dismiss/answer the permission dialog via simulator tap this pass — see Method section. |
| **Large activity histories / large diffs** | ⚠️ **Not tested this pass** | Would require seeding GRDB directly with synthetic bulk data; not done this pass given time. Existing unit-level pagination/cap tests still stand (`ChatConversationRepositoryTests.swift:271`, `BlockRenderer.swift:214-239`). |

## Summary

**New evidence gathered this pass:** iPad split-view IA works (previously unverified — real gap
closed), dark-mode-only behavior reconfirmed unchanged, and — most valuably — the safety-critical
approval banner at max accessibility Dynamic Type size does not visibly break despite the known
hardcoded-font-size code smell flagged in `KNOWN_ISSUES.md`.

**Still open, in priority order:** empty/first-run state (needs a clean simulator or erase),
small-iPhone/no-Dynamic-Island pass (`iPhone 17e` is available, just not run this pass),
permission-denied states (blocked by a simulator tooling limitation this pass, retry on physical
device instead), large-data stress testing, and everything genuinely requiring physical hardware
(offline/network conditions, Apple Watch, and the already-flagged closed-app push-to-start test
from the implementation report).

**Tooling note for future passes:** this Xcode-beta/iOS27 simulator environment continues to be
unreliable for interactive UI automation (system alerts included, not just custom app views) —
budget for physical-device fallback rather than assuming simulator taps will work.
