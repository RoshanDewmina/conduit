# Beta shell reachability repair — 2026-07-14 (correction pass)

**Branch:** `fix/beta-shell-reachability` @ `c90bed67` (+ uncommitted correction pass)  
**Worktree:** `.worktrees/chat-error-convergence` (sole writer)  
**Binding design:** Workspaces-only root; Profile → Settings on **one** `NavigationStack` with real existing content (Trusted Machines); Policy & Governance honest deferred; **no** shipping Emergency Stop until daemon `agent.emergencyStop` is wired safely on the phone path.

## Corrected write set

| File | Action |
|------|--------|
| `docs/plans/2026-07-14-beta-shell-reachability-plan.md` | update — this file (no false completion) |
| `Packages/LancerKit/Sources/AppFeature/Settings/AppSettingsView.swift` | rewrite — Trusted Machines + deferred Policy; no Emergency Stop |
| `Packages/LancerKit/Sources/AppFeature/Settings/PolicyGovernanceViews.swift` | **deleted** — speculative no-op Apply UX |
| `Packages/LancerKit/Sources/AppFeature/Settings/EmergencyStopAction.swift` | **deleted** — must not label per-run cancel as fleet/atomic stop |
| `Packages/LancerKit/Sources/AppFeature/Settings/TrustedMachinesView.swift` | edit — `embedsInParentNavigation` avoids nested stacks |
| `Packages/LancerKit/Sources/AppFeature/Profile/ProfileView.swift` | edit — Settings via `NavigationLink` on Profile's stack |
| `Packages/LancerKit/Sources/AppFeature/Workspaces/WorkspacesView.swift` | keep DEBUG destination seams (`settings`/`governance`→Settings, `approval`, composer/screenshot routes) |
| `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` | edit — gate DEBUG UITest root presentation until deterministic reseed completes |
| `Packages/LancerKit/Sources/AppFeature/Bridge/RelayApprovalIngest.swift` | keep — DEBUG UITest hydrate |
| `Packages/LancerKit/Sources/AppFeature/Bridge/ShellLiveBridge.swift` | keep — DEBUG UITest machine context |
| `Packages/LancerKit/Sources/AppFeature/Chat/LiveThreadView.swift` | keep — `cursor.approval.approve` a11y id |
| `Packages/LancerKit/Package.resolved` | **reverted** exactly to `c90bed67` |
| `LancerUITests/*` (all 6 files) | modernize for Workspaces/Profile/in-thread UI |

## Explicitly out of scope / open beta blockers

1. **B11b — Atomic Emergency Stop:** daemon `agent.emergencyStop` is **not** wired on the phone Settings path in this pass. Approved scope: stop and report blocked rather than ship weaker per-run `ActiveRunRegistry` cancel labeled as fleet stop. **Product blocker remains open.**
2. **Policy / Governance UI:** no functional, module-safe phone editor found (SettingsFeature is ViewModel/billing only; LancerCore has presets/matrix models without an Apply pipeline into hosts). Settings shows honest deferred copy. **Open beta gap.**

## Test integrity

1. No hard-coded production feature flags exist solely to make tests pass.
2. Composer tests add a real absolute repo through the UI, enter a draft, and verify the actual disabled/enabled Send button.
3. Seeded approval coverage is named as local card-state coverage; host forwarding remains the live relay harness's responsibility.
4. The permanently skipped stale SSH UI method was removed. The full suite has only live relay and live dispatch prerequisite skips.

## Acceptance commands

```bash
cd /Users/roshansilva/Documents/command-center/.worktrees/chat-error-convergence

cd Packages/LancerKit && swift build

# App-target + UITests (simulator)
xcodebuild -project Lancer.xcodeproj -scheme Lancer \
  -destination 'platform=iOS Simulator,id=095F8B3A-FEA3-4031-A2A5-561755740730' \
  -derivedDataPath /tmp/lancer-beta-shell-reachability/DerivedData build

xcodebuild test -project Lancer.xcodeproj -scheme Lancer \
  -destination 'platform=iOS Simulator,id=095F8B3A-FEA3-4031-A2A5-561755740730' \
  -derivedDataPath /tmp/lancer-beta-shell-reachability/DerivedData \
  -only-testing:LancerUITests

git diff --check
git diff --stat
# Package.resolved must match c90bed67 (no sentry-cocoa drift)
```

## Done when (honest)

- [x] Profile → Settings → Trusted Machines on one navigation stack; Policy deferred (no no-op Apply).
- [x] No shipping Emergency Stop control; B11b reported blocked.
- [x] UITests target Workspaces / Profile / in-thread approval — not mock 3-tab / inbox / Face ID.
- [x] Verification gates (2026-07-14 correction pass):
  - `swift build` → OK
  - focused approval reseed checks → **2 executed, 0 failed**
  - focused approval/composer checks → **3 executed, 1 skipped, 0 failed**
  - app-target simulator build → compiled as part of the UI test run
  - `LancerUITests` full target → **22 executed, 2 skipped, 0 failed** (`TEST SUCCEEDED`, 247.102s)
  - skips: live relay E2E and live dispatch E2E (owner-gated; accurate reasons)
  - `git diff --check` clean; `Package.resolved` matches `c90bed67`
- [x] `Package.resolved` restored to `c90bed67`.
- [ ] **Not claimed done:** atomic emergency stop; real policy governance Apply.
