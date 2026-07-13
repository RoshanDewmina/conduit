# Codex + OpenCode phone support — vertical slice (2026-07-12)

## Root cause (Claude-only on phone)

**Not** missing daemon adapters. Codex/OpenCode launch/continue/resume argv, stream
readers, session index, and `agent.agents.installed` already live in `daemon/lancerd/`.

Phone New Chat was Claude-only because:

| Layer | Reality | Evidence |
|---|---|---|
| Daemon adapters | Shipped | `dispatch.go` `agentArgv`/`continueArgv`/`resumeArgv` cases for `codex` + `opencode` |
| Installed-agents RPC | Shipped | `doctor.go` `installedAgents`; relay `agentAgentsInstalled` |
| Siri / App Intents | Multi-vendor | `Lancer/AgentVendorAppEnum.swift` |
| New Chat send path | Hardcoded Claude | `ShellLiveBridge` previously `private static let vendor = "claudeCode"` |
| Model picker | Claude aliases only | `DispatchModelSelection` = haiku/sonnet/opus |
| Installed-agents cache | Stub never filled | `RelayFleetStore.installedAgentVendors` + `relayInstalledAgents()` unused until this slice |
| Identity badges / hot-swap | Designed, not shipped | `docs/plans/2026-07-12-account-hotswap-and-identity-design.md` (queued) |

## Vertical slice started (this change)

1. `DispatchVendorSelection` + `VendorPickerView` (composer Agent chip)
2. `ShellLiveBridge.send` uses selected vendor wire id; Claude-only model slug
3. Hydration + composer fetch `relayInstalledAgents` into `RelayFleetStore`
4. Unit tests for vendor selection + `dispatchSlug`

## Unblocks (owner / next)

- **Codex headless:** `LANCER_CODEX_UNSAFE=1` not set on this host. Without it, `codex exec`
  may hang on TTY approvals after launch. Launch still escalates (no per-action hook —
  `hookWiredForAgent` fail-closed for `codex`). Prefer safer `--ask-for-approval never
  --sandbox workspace-write` argv after a local smoke test (vendor-cli-adapter-audit).
- **OpenCode models:** CLI wants `provider/model`; v1 passes nil (CLI default). Add picker later.
- **OpenCode gate:** plugin install exists; launch relaxes only when `opencodeGateWired`.
- **Identity badges:** still the separate ui lane — not required to dispatch.

## Verify

```bash
cd Packages/LancerKit && swift test --filter 'DispatchVendorSelection|DispatchModelSelection'
# Device: New Chat → Agent → Codex/OpenCode → send; approve launch if escalated.
```
