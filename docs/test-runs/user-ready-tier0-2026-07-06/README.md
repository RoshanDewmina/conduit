# User-ready Tier 0 proof — 2026-07-06

Branch: `cursor/user-ready-tier0-9aec`  
Simulator: iPhone 17 Pro  
Test suite: `LancerUITests/CursorAppShellExhaustiveTests` — **21/21 PASS** (~353s)

## Competitor patterns borrowed

| Pattern | Source | Lancer implementation |
|---------|--------|----------------------|
| Thread attention pills | T3 + Happier | `CursorThreadAttention`, thread row pills |
| Connection health banner | Orca | `CursorConnectionBanner`, `ConnectionPhase` on bridge |
| Approval above composer (live-gated) | T3 | `CursorWorkThreadView.showsApprovalBanner` |
| Composer draft persistence | Happier | `CursorComposerDraftStore` |
| Pairing sheet with timeout/log | Orca | `CursorRelayPairingSheet` |
| Settings destination handoff | Lancer | `SettingsDestination` enum → real Settings |

## Screenshots

Exported from xcresult to `docs/test-runs/user-ready-tier0-2026-07-06/` (21 attachments + manifest.json).

## Remaining for full user-ready on device

- Owner proof: pair → dispatch → approval → continue on physical iPhone + `lancerd`
- Relay E2E harness update for Cursor-shell navigation
- APNs lock-screen checkpoint 5c per LIVE_LOOP_RUNBOOK
