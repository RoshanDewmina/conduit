# 02 — Architecture

## Layers

```
iOS app (Lancer/ + Packages/LancerKit)         ── phone steers & approves
   AppFeature (root router: AppRoot, sidebar shell, AppEnvironment DI)
   Feature modules: Session/Inbox/Settings/Workspaces/Onboarding/Diff/Files
   Engines (no UI): LancerCore, SecurityKit, SSHTransport, TerminalEngine,
                    AgentKit, AccountKit, PersistenceKit (GRDB), SyncKit (CloudKit),
                    NotificationsKit, DiffKit, HostControlKit, DesignSystem
        │ SSH (Citadel) + E2E relay (WebSocket)
        ▼
lancerd (Go, resident on dev host)  ── policy engine, approval queue, audit chain
        │
push-backend (Go, Cloud Run)        ── APNs, E2E relay spine, Stripe/quotas
agent-runner (Go)                   ── V2 hosted execution (retained, unwired)
```

Navigation is a **sidebar / Command Home shell** (`SidebarDestination`: home, newChat, thread,
needsAttention, machines, governance, settings, observedSession) — *not* a tab bar (`enum Tab` is
vestigial). Entry: `LancerApp` (`Lancer/LancerApp.swift`) → `AppRoot` (`AppFeature/AppRoot.swift`).

## Module DAG
Clean engine/feature split; `AppFeature` is the DAG root importing the feature + engine modules.
Engines carry no UIKit/SwiftUI. This boundary is healthy and should be preserved.

## State & data flow
- `AppEnvironment` is the composition root (17 repositories/stores, GRDB-backed) created in `init()`.
- Cross-cutting singletons (`ApprovalRelay.shared`, `Notifications.shared`, `BiometricGate.shared`,
  `LancerLiveActivityManager.shared`, purchase/buffer singletons) are reached directly from AppRoot.
- Relay/dispatch events fan in through NotificationCenter (mix of typed `.lancerX` and string names).

## Architectural findings (challenged — kept only the defensible ones)
- **ARCH-1 (OPEN, Low):** `AppRoot.mainBody` is a 165-line modifier chain → the one build warning
  (380ms type-check). Real, low-risk extraction. *This is the only architecture item worth doing
  now.*
- **Notification fan-in / singletons / `AppEnvironment` size:** the subagent recommended a typed
  event-stream bridge, an `@Environment` `ServiceRegistry`, and splitting `AppEnvironment` into
  feature-scoped containers. **Rejected as speculative for now** (ponytail / `agent-contract.md` §3
  "no speculative abstractions"): the current wiring works, is tested, and ships. These are
  *legitimate* future refactors but carry real regression risk against a live approval loop and buy
  no measured benefit today. Note them; don't do them under an audit banner.
- **Approval decision routing** has 4 entry points all funnelling through the single
  `forwardDecisionOnly` chokepoint (`ApprovalRelay.swift:157`) — this is already the right shape;
  the "duplication" is thin. No action.

## Areas to explicitly leave unchanged
- Engine/feature module boundaries; the unified-PTY → BlockRenderer pipeline (see
  `.claude/rules/terminal-blocks.md`); the TOFU/BiometricGate/Keychain security paths; the live
  relay infra (`conduit-push` Cloud Run name is intentional); V2 hosted-cloud code (retained).
