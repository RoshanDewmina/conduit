# Siri / iOS 27 All-In Roadmap

**Date:** 2026-07-09  
**Last updated: 2026-07-15.**  
**Decision:** Owner chose **C — raise deployment target to iOS 27** and go all-in on seamless Siri / App Intents / system integration.  
**Inventory:** [`2026-07-09-wwdc-ios-capability-inventory.md`](2026-07-09-wwdc-ios-capability-inventory.md)  
**Prior plan (superseded for target strategy):** [`2026-07-03-siri-primary-ios27-fast-follow-plan.md`](2026-07-03-siri-primary-ios27-fast-follow-plan.md) — Phase 1 entity work largely landed; this roadmap starts from **live code**, not the July 3 “zero entities” premise.

## Gate 0 — Fable cleanup (plan-only, before implement)

**Do not start coding the milestones below until a short Fable plan-only pass completes.**

Purpose: decide what to delete/archive vs keep among overlapping Siri/WWDC docs so the implement session has one source of truth. This session does **not** delete docs.

Suggested Fable brief inputs:

- Inventory + this roadmap (canonical going forward)
- `docs/wwdc26-lancer-opportunity-audit/` (valuable research; `02` status matrix **stale** on IntentsKit)
- `docs/plans/2026-07-03-siri-primary-ios27-fast-follow-plan.md` (partially executed)
- Any parked Siri Phase 2 branches / duplicate Status.md files

**Done-when for Gate 0:** written plan listing keep / supersede / archive — no file deletes required in that plan-only session unless owner explicitly expands scope.

---

## Milestone 0 — Raise deployment target to 27.0

### Changes
1. `project.yml` — set `IPHONEOS_DEPLOYMENT_TARGET: "27.0"` for app + all iOS extension targets (today `26.0` at lines ~13, 233, 271 and any other target overrides).
2. `Packages/LancerKit/Package.swift` — `.iOS(.v27)` (today `.v26` at line 19).
3. Regenerate Xcode project: `xcodegen generate` (or project’s documented regenerate path).
4. Confirm watch/mac companion targets stay intentional (watchOS / macOS mins are separate — do not silently bump unless owner asks).
5. Optionally simplify `#if swift(>=6.4)` / `@available(iOS 27.0, *)` where the whole module now requires 27 — keep gates only if shared code must still type-check on older SDKs in CI.

### Verify
```bash
# Targets
rg 'IPHONEOS_DEPLOYMENT_TARGET|\\.iOS\\(\\.v' project.yml Packages/LancerKit/Package.swift

cd Packages/LancerKit && swift build && swift test

# App-target build (required — IntentsKit / widget / #if os(iOS))
# Prefer XcodeBuildMCP: session_show_defaults → build_sim
```

**Done-when:** app + LancerKit build green at 27.0; no accidental watch/mac bumps.

---

## Seamless Siri done-bar (concrete utterances)

Security invariants (non-negotiable):

- **No** Siri/voice **Approve** phrase or intent registration.
- Deny / Stop remain confirmation-aware and entity-resolved.
- High-risk / ambiguous → open Lancer (or visual Live Activity), never silent execute.

| # | Utterance (examples) | Expected behavior |
|---|---|---|
| 1 | “How many agents are running in Lancer?” | Spoken/status dialog from live registry; freshness if host offline |
| 2 | “Are any approvals waiting in Lancer?” | Count + top pending titles (redacted if secret-like) |
| 3 | “Pause the Codex run in Lancer” / “Pause this run” | Resolves `RunEntity` (disambiguate if >1); pauses; fails clearly if offline |
| 4 | “Stop my Lancer session” | Confirmation-gated stop on resolved run |
| 5 | “Deny the latest approval in Lancer” / “Deny that approval” | Resolves `ApprovalEntity` (not silent wrong host); audit has real hostId |
| 6 | “Search Lancer for auth middleware” | Opens in-app FTS **and** Spotlight can surface indexed conversations |
| 7 | “Open the pairing conversation in Lancer” | Opens `ConversationEntity` thread in Cursor shell |
| 8 | “Start Claude Code in Lancer” | Confirms machine/agent/workspace/prompt; `LongRunningIntent` progress → Live Activity; cancellable |
| 9 | “Answer the agent’s question in Lancer” | Routes to pending question flow (iOS 18+ shortcut already registered) |
| 10 | On-screen: looking at run list — “Pause this one” | View annotation resolves visible `RunEntity` |

**Negative done-bar:** Siri must **refuse** or never offer “Approve the pending command in Lancer.”

---

## Milestone 1 — Wire what already exists (high leverage, low new API)

Live code already has entities, IndexedEntity, IndexedEntityQuery, SyncableEntity (Conversation/Run), RelevantEntities donate path, LongRunningIntent conformance, App Shortcuts. Gaps are **cadence and product polish**.

### Work
1. Wire `SiriSurfaceBootstrap` refresh to real state changes (relay connect, pending approval, run start/end, conversation open) — today launch + optional notification only (`SiriSurfaceBootstrap.swift:14-16`).
2. Ensure `SiriEntityIndexer.refreshAll()` + `SiriRelevanceCoordinator.refresh` run on those signals.
3. Confirm secret-screen gate still skips credential-like titles (`SiriSpotlightSupport`).
4. Dialog polish: machine name, online/offline, risk, ambiguity disambiguation.

### Verify
```bash
cd Packages/LancerKit && swift test --filter IntentsKit
# Manual: Siri phrases 1–7 on device/sim with Workspaces + LANCER_DESTINATION if needed
# (LANCER_CURSOR_SHELL_LIVE was removed 2026-07-11 — historical only)
```

**Done-when:** after a pending approval arrives, RelevantEntities/Spotlight refresh without relaunch; phrases 1–7 work with ≥2 machines/runs.

---

## Milestone 2 — AppIntentsTesting regression suite (P0)

### Work
1. Add XCUITest / AppIntentsTesting bundle (iOS 27).
2. Assert compiled App Shortcuts metadata contains exactly the intended set (**no** `ApprovalActionIntent`).
3. Execute: status, pending, pause, stop, deny, search, open conversation, start run (confirm path).
4. Spotlight query smoke for a seeded `ConversationEntity`.
5. (After M3) view-annotation assertions.

### Verify
```bash
# XcodeBuildMCP test_sim or xcodebuild test on AppIntentsTesting target
```

**Done-when:** CI fails if `AppShortcutsProvider` moves back to SPM or approve appears in shortcuts.

---

## Milestone 3 — View annotations + IntentExecutionTargets (P0/P1)

### Work
1. Annotate Cursor-shell run rows, approval cards, conversation rows with `.appEntityIdentifier` / `AppEntityAnnotatable` (verify exact SwiftUI API against Xcode 27).
2. Set `allowedExecutionTargets` on shared intents:
   - Siri-only intents → `.main`
   - `ApprovalActionIntent` (widget) → `.widgetKitExtension` (and/or `.main` as required)
3. Do **not** move `AppShortcutsProvider` out of the app target.

### Verify
- Live: “pause this run” with two visible runs.
- AppIntentsTesting `viewAnnotations` if available.
- No “Unable to run App Shortcut” / ambiguous-target regressions.

---

## Milestone 4 — LongRunningIntent productization (P0)

### Work
1. Implement `performBackgroundTask` for `StartAgentRunIntent` (not just protocol conformance).
2. Report progress → system Live Activity (framework-managed) **and** keep Lancer’s existing `LancerLiveActivityManager` coherent (avoid duplicate/conflicting activities — pick one owner story).
3. `CancellableIntent.onCancel` → stop/cancel dispatch cleanly.
4. Offline / no-machine failure dialogs.

### Verify
- Utterance 8 on physical device; activity survives background; cancel works.
- `swift test` for start-run preparer / intent routing.

---

## Milestone 5 — Away-mode Live Activity harden (P1)

### Work
1. Device dogfood: push update + push-to-start with app killed.
2. Risk styling on Island/Lock Screen for high/critical.
3. Relay-path widget snapshot freshness.
4. Confirm frequent-updates Info.plist keys if chatty streams needed.

### Verify
- Physical device checklist from `docs/wwdc26-lancer-opportunity-audit/05-device-hub-testing-plan.md` (backgrounding / relaunching rows).
- Screenshots under `docs/test-runs/`.

---

## Milestone 6 — SyncableEntity + Continuity polish (P1)

### Work
1. Keep Conversation + Run as SyncableEntity; document why Machine/Approval/Workspace stay out (`SiriSyncableEntities.swift` comments).
2. Cross-device: start Siri open-conversation on iPhone → continue on iPad/Mac if CloudKit IDs match.
3. Optional: `IntentModes` / `TargetContentProvidingIntent` for open flows.

### Verify
- Two-device manual; unit tests for syncable ID stability already in `SiriSyncableEntityTests`.

---

## Milestone 7 — Approval Copilot prototype (P2, after Siri done-bar)

### Work
1. On-device `SystemLanguageModel` + `@Generable RiskVerdict` + read-only `Tool`s over GRDB/audit.
2. UI card **beside** approval — zero path to set approval outcome.
3. Later: PCC `.deep` + `Attachment` screenshots + `DynamicProfile`; Evaluations for “never says approve.”
4. **Never** wire Copilot to auto-approve.

### Verify
- Model unavailable → graceful empty state.
- Eval corpus from audit log (advisory vs human decision).

---

## Explicit non-goals

- Siri/voice Approve (any phrase).
- Face ID / biometric gate on approvals (`IntentAuthenticationPolicy` rejected for V1).
- App Schemas domain adoption without an Apple domain that matches agent runs.
- SwiftData migration.
- Watch Smart Stack / CarPlay supplemental families before M5 risk + lifecycle are solid.
- Third-party cloud `LanguageModel` packages.
- Fine-tuned on-device adapters (`SystemLanguageModel(adapter:)` **obsoleted** in iOS 27).
- Deleting/cleaning docs in the implement session (Gate 0 / separate Fable track).
- Raising watchOS/macOS targets unless separately decided.

---

## Suggested implement-session order

```text
Gate 0 (Fable plan-only cleanup)
  → M0 raise target 27
  → M1 wire existing Siri surfaces
  → M2 AppIntentsTesting
  → M3 view annotations + ExecutionTargets
  → M4 LongRunningIntent productization
  → M5 Live Activity device harden
  → M6 SyncableEntity continuity
  → M7 Copilot prototype
```

## Paste-ready implement brief (after Gate 0)

```text
Repo: /Users/roshansilva/Documents/command-center
Read: AGENTS.md, docs/plans/2026-07-09-wwdc-ios-capability-inventory.md,
      docs/plans/2026-07-09-siri-ios27-all-in-roadmap.md,
      docs/plans/2026-07-09-wwdc-research-Status.md

Owner decision: iOS 27 deployment target all-in. No Siri Approve. No biometric approval gate.

Execute Milestone 0 then Milestone 1 from the roadmap. Do not delete docs.
Verify with LancerKit swift test + XcodeBuildMCP app-target build.
```
