# Phone-primary developer readiness — 2026-07-06

Tier-0 exit bar: pair → dispatch → approval → follow-up on simulator **and** physical device proof path documented.  
Evidence hub: [`docs/test-runs/2026-07-06-phone-ready-pass.md`](../test-runs/2026-07-06-phone-ready-pass.md)

| Area | Status | Proof / notes |
|------|--------|----------------|
| **Pairing** | Shipped | `E2ERelayPairingView`, `LANCER_RELAY_CODE` seam; relay E2E PASS |
| **Agents / dispatch** | Shipped | `NewChatTabView`, `CursorComposerSheet` → `performDispatch` |
| **Terminal** | Partial (read-only) | Work Thread mock transcript; ARCHITECTURE defers interactive PTY on phone |
| **Files / diffs** | Partial | `CursorReviewDiffView`, `DiffFeature`; no full phone IDE |
| **Approvals** | Shipped | `InboxView`, `ApprovalRelay`, biometric gate + UITest bypass |
| **Git** | Not started (phone) | ADR: daemon RPCs only — see terminal ADR |
| **Worktrees** | Not started (phone) | ADR: list/status RPC deferred |
| **Notifications** | Shipped (code) | Categories hardened; **5c APNs** owner re-proof required |
| **Recovery / reconnect** | Partial | Relay fleet hydration; orange-dot / re-pair UX residual (KNOWN_ISSUES) |
| **Machine management** | Shipped | `RelayMachinesListView`, multi-machine `RelayFleetStore` |
| **Security** | Shipped (core) | TOFU, Keychain, fail-closed policy; P0 biometric-no-passcode gap open |
| **Deployment / TestFlight** | Partial | Device build PASS; App Store gates in `PUBLISH_READINESS_CHECKLIST.md` |

## Shell sign-off matrix

| Shell | Sim automated | Device build | Manual checklist |
|-------|---------------|--------------|------------------|
| Cursor live (`LANCER_CURSOR_SHELL_LIVE=1`) | `CursorShellLiveApprovalTests` + relay E2E | Install PASS | Unlock phone → LIVE_LOOP 5a/5b + composer dispatch smoke |

## Owner-gated before TestFlight

1. CHECKPOINT **5c** — lock-screen APNs approve + screen recording (`LIVE_LOOP_RUNBOOK.md`)
2. Biometric on real device (Face ID / passcode device matrix)
3. Production Supabase + push backend env for external testers

## P0 correctness (not blocking sim Tier-0)

From master plan §7 — track in gap matrix: biometric degrade-open, emergency stop atomicity.
