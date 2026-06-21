# Per-conversation permission mode — design

Date: 2026-06-21
Status: approved (design); implementation foundation landed, live per-action path pending device verification

## Problem

When Conduit governs a run, dangerous actions pause for phone approval. That's correct
for "steer from afar", but wrong when the owner is *driving* the machine themselves and
just wants the agent to run uninterrupted — they get blocked waiting on a phone reply
(exactly what happened to this session's own driving loop). There's no fast, deliberate
"let it run" control.

An autonomy system already exists (`AutonomyPreset`: autoReads / autoSafeWrites / alwaysAsk /
agentDecides, surfaced in Settings → `AutonomyLevelView`) but: (a) it tops out at "critical
only" — there is no true full bypass; (b) it's a buried global setting, not a per-conversation
control you can flip the way Claude Code flips permission modes.

## Decision (from brainstorm)

- **Per-conversation permission mode**, over a **global default**. The conversation control
  overrides the global for that thread only — the Claude Code mental model.
- **Global default = Always ask** (fail-closed baseline; opt into looser modes per chat).
- **Tiers** (reuse `AutonomyPreset`, add one case):
  - **Default** — inherit the global default.
  - **Auto-run safe** — `autoSafeWrites` (low/medium auto; high/critical ask).
  - **Critical only** — `agentDecides` (only critical asks).
  - **Full bypass** — NEW `.bypass`: nothing pauses (true "I'm driving, don't stop me").
- **Toggle lives on the conversation** and is settable from the phone.

## Approach A (chosen): the mode rides on dispatch

The conversation's mode is sent as a parameter on each dispatch/continue. The daemon applies
it to **that run's** gating only. No global policy mutation (rejected Approach B — global state
masquerading as per-conversation; leaks across threads; fights the fail-closed contract).

This composes with the existing `relaxLaunchEscalation` (and its security hardening): the
launch gate and the per-action policy evaluation both consult the run's mode.

## Architecture

1. **`AutonomyPreset.bypass`** (`ConduitCore/AutonomySettings.swift`): new most-permissive case.
   `isAutoApproved` returns `true` for all kinds/risks. Label "Full bypass", an unambiguous
   description ("Nothing pauses — the agent runs every action without asking").

2. **Dispatch carries the mode**: add `permissionMode: String?` to the dispatch + continue
   params (iOS `onDispatch`/`continueRun` → `E2ERelayBridge`/`DaemonChannel` → Go
   `dispatchParams` / continue). Empty/absent ⇒ daemon's global default.

3. **Daemon gating keyed per-run** (`dispatch.go`):
   - Launch gate: a run whose mode is `bypass` (and only via an explicit, owner-set mode —
     never inferred) skips launch escalation regardless of agent, since the owner has
     deliberately opted that conversation out. Default/other modes keep the hardened
     `relaxLaunchEscalation` behavior (default-ask + verifiably-wired hook only).
   - Per-action: store the run's mode on `dispatchRun`. The PreToolUse-hook path that
     evaluates an action for a given runId consults the run's mode: `bypass` ⇒ allow;
     otherwise the existing `AutonomyPreset`/policy evaluation. (This is the piece that
     needs the live hook→conduitd→run mapping; see "Open / device-verified".)

4. **Conversation UI** (`NewChatTabView` + active-run header): a permission-mode button (the
   Claude Code pattern) showing the current mode; tapping opens a small picker (Default /
   Auto-run safe / Critical only / Full bypass). Default mode is read from the global setting.
   When a conversation is in **Full bypass**, show a persistent, unmistakable banner/indicator
   (this is the visible-state guardrail the security posture requires) — Emergency Stop remains
   the escape hatch.

5. **Global default** (`AutonomyLevelView` / `AutonomySettings`): the existing Settings control
   sets the baseline a new conversation inherits. Wire `.bypass` in as a selectable global too,
   but it is NOT the default.

## Security guardrails (fail-closed posture preserved)

- Full bypass is **never inferred** — only an explicit, owner-set per-conversation (or global)
  choice produces it. The hardened launch-gate heuristic (default-ask + wired hook) is unchanged
  for non-bypass runs.
- Full bypass is a **visible state** (banner + mode indicator), not a silent setting.
- Emergency Stop (existing) instantly halts a bypassed run.
- The daemon still **audits** every action under bypass (audit log is not suppressed) — bypass
  changes the gate, not the record.
- Per-machine trust is out of scope for V1 (the brainstorm's #2); per-conversation + global
  covers the stated pain. Revisit per-machine later if needed.

## Testing

- Daemon unit tests: a `bypass`-mode dispatch/continue starts without escalation for ANY agent
  (incl. codex/kimi); a non-bypass run still escalates per the hardened rules; bypass still
  audits. (Extends `dispatch_launchgate_test.go`.)
- Client: `AutonomyPreset.bypass.isAutoApproved` returns true for all kinds/risks (add to
  `ConduitAppearanceTests`-style unit coverage if a preset test exists).
- App-target build green; mode button + bypass banner eyeballed in the gallery.

## Open / device-verified (not blind-shipped)

- The **per-action bypass over the live relay** (hook → conduitd → run-mode lookup → allow)
  needs a reachable daemon + paired host to prove, and re-touches the gating a security review
  just hardened. Build-verify the foundation; confirm live behavior on device before claiming
  the loop closed.

## Build order

1. `AutonomyPreset.bypass` + client preset test. (verifiable now)
2. `permissionMode` on dispatch/continue params end-to-end (iOS + relay + Go). (build-verify)
3. Daemon launch-gate honors explicit bypass per-run + tests. (verifiable now)
4. Conversation mode button + Full-bypass banner. (build-verify + gallery screenshot)
5. Per-action hook integration. (device-verified)
