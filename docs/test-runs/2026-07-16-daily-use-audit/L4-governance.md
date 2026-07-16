# L4 — Governance UI (policy / audit / Emergency Stop)

**Date:** 2026-07-16  
**Tip:** `b17b6172`  
**Transport:** relay pairing (sim code `583514`)  
**Evidence-only.**

---

## Summary

| Check | Result |
|---|---|
| Settings reachable | **PARTIAL** — Profile sheet / Workspaces reachable; `LANCER_DESTINATION=settings` screenshot blank (`L4-01`) |
| Policy editor (#135) | **FAIL vs night claim** — **deferred stub** on tip ("Not available in this build") |
| Audit feed (#135) | **FAIL / absent** — no audit feed surface in `AppSettingsView` |
| Emergency Stop (§4 / #135) | **FAIL / absent** on iOS Settings — Watch-only / UITest asserts absence |
| Relay-only clear error vs hang | **N-A** for editor (no editor); deferred copy is clear (not a hang) |

---

## Tip source (authoritative)

`AppSettingsView.swift` ends with Connections + deferred Policy section only:

```swift
// AppSettingsView.swift:63-74
private var policyGovernanceSection: some View {
    Section(AppSettingsCopy.policyGovernanceTitle) {
        ...
        .accessibilityIdentifier("cursor.settings.policy-deferred")
    }
}
```

`AppSettingsCopy.swift`:

```text
policyGovernanceDetail =
  "Not available in this build. Host policy editing and governance apply are deferred until a real surface is wired."
```

UITest on tip (`CursorAppShellExhaustiveTests.testSettingsDestination_DeferredPolicyNoEmergencyStop` / `TapInjectionProofTests`): expects **no** `cursor.settings.emergency-stop`, policy deferred.

Emergency Stop symbols on tip are Watch / connector only (`PhoneWatchConnector.onEmergencyStop`, `WatchApprovalTransfer.emergencyStop`) — **not** an iOS Settings kill-switch UI.

**Contradiction resolved:** night plan Part A claimed #135 wired Emergency Stop + policy editor + audit feed into Settings. **On `b17b6172` those Settings surfaces are deferred/absent.** Treat night claim as **not true of this tip** (merge not in this SHA, or rolled back / never landed here).

---

## Screenshots

| Path | Notes |
|---|---|
| `screenshots/L4-01-settings-deeplink.png` | Blank white — deeplink capture failed |
| `screenshots/L4-02-profile-sheet.png` | Workspaces + Agents "Machine unreachable" (not Settings) |
| `screenshots/L4-02-profile-open.png` | Large capture; same session |

Did **not** trigger Emergency Stop (no affordance). Daemon left running (`launchctl` pid 81742 earlier; not latched by L4).

---

## Daily-use impact (MVP piece 6)

Owner cannot Emergency-Stop from iOS Settings on this tip. Kill-switch for daily driving remains **unproven / unavailable** in-app on sim build under test.

---

## Verification

```text
Verification:
- SwiftPM: skipped
- Xcode: BUILD SUCCEEDED
- Go: go test PASS
- Governance UI: FAIL (deferred) per AppSettingsView + UITest + AppSettingsCopy
- Emergency Stop: not present in iOS Settings on tip — not exercised
- Warnings: night #135 claims do not match tip Settings; L4 Task stalled
```
