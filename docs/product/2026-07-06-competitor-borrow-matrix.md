# Competitor study — borrow list for Lancer (2026-07-06)

Studied shallow clones in `.study/competitors/`:
- [pingdotgg/t3code](https://github.com/pingdotgg/t3code) — `apps/mobile` (Expo/RN)
- [stablyai/orca](https://github.com/stablyai/orca) — `mobile/` companion
- [happier-dev/happier](https://github.com/happier-dev/happier) — `apps/ui` (Expo, shared web/mobile)

## What to borrow

| Priority | Pattern | Source | Lancer fit |
|----------|---------|--------|------------|
| P0 | Thread attention pills on list rows | T3 `threadPresentation.ts`, Happier `deriveSessionAttentionState` | Mission-control at a glance |
| P0 | Connection health banner (offline/reconnect/pair) | Orca `connection-health.ts`, T3 empty states | Relay/SSH drop UX |
| P0 | Approval UI above composer, live-gated | T3 `PendingApprovalCard.tsx` | Governed loop wedge |
| P0 | Real Settings handoff, not mock-only | Lancer existing | Policy/audit trust |
| P1 | Composer draft survives navigation | Happier continuity tests | Phone↔desk handoff |
| P1 | Pairing confirm + timeout + log | Orca `pair-confirm.tsx` | First-run polish |
| P1 | Dispatch outbox (offline enqueue) | T3 `thread-outbox-model.ts` | Relay flake resilience |
| P2 | Notification deep-link dedup | T3 `notificationNavigation.ts` | APNs cold-start |
| P2 | Resume last active thread | Orca `resume-worktree.ts` | Return-to-work UX |

## What NOT to borrow

| Anti-pattern | Source | Why |
|--------------|--------|-----|
| Phone xterm / full terminal mirror | Orca 5K-line session screen | Conflicts with "not a phone IDE" |
| Stateful encrypted relay server | Happier `apps/server` | Lancer blind relay + daemon truth |
| Clerk-gated push registration | T3 `remoteRegistration.ts` | Extra account friction |
| LAN-only WS pairing | Orca default | Lancer needs relay/tailnet story |
| 4-tab + deep session cockpit | Happier IA | Lancer 3-root Cursor shell |

## Implemented this pass (cursor/user-ready-tier0-9aec)

- `CursorThreadAttention` + thread row pills
- `CursorConnectionBanner` + `ConnectionPhase`
- Live-gated approval banner
- `CursorComposerDraftStore`
- `CursorRelayPairingSheet` + `SettingsDestination` handoff
- Bridge wiring for attention, connection phase, relay machine count
