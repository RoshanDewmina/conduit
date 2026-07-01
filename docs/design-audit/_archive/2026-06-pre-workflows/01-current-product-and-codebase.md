# 01 — Current Product and Codebase

> Source: Wave-1 repo/product audit (read-only). All file/line anchors verified against the working tree on 2026-06-29.

## Product truth

Lancer is iOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode, Kimi) running on the developer's **own** machines/servers. The phone **steers, approves, audits, and stops** work — it is explicitly **not** a phone IDE ([AGENTS.md:10](/Users/roshansilva/Documents/command-center/AGENTS.md), [README.md:3](/Users/roshansilva/Documents/command-center/README.md)).

The current product direction is **governance-led**: policy, audit, emergency stop, relay, APNs, and fleet status outrank terminal depth ([ARCHITECTURE.md:31](/Users/roshansilva/Documents/command-center/ARCHITECTURE.md)). The top-level IA is explicitly a **sidebar / Command Home** shell, not a tab bar ([ARCHITECTURE.md:251](/Users/roshansilva/Documents/command-center/ARCHITECTURE.md), [README.md:68](/Users/roshansilva/Documents/command-center/README.md)). `enum Tab` in `AppRoot.swift` is vestigial.

Three layers:
- **iOS app** — `Packages/LancerKit/`
- **`lancerd`** resident daemon — `daemon/lancerd/`
- **`push-backend` + `agent-runner`** hosted-cloud control plane — `daemon/push-backend/`, `daemon/agent-runner/`

## State / data architecture relevant to UI

App composition is centralized in `AppEnvironment`: GRDB database, host/snippet/block/session/chat/approval/audit repositories, Keychain stores, `SyncEngine`, `LoopStore`, quota/health stores, relay client, and account session ([AppRoot.swift:21](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/AppRoot.swift)).

GRDB migrations cover hosts, command blocks/FTS, snippets, approvals, patches, session snapshots, sync tombstones, audit events, loops, durable chat conversations/turns/artifacts, and chat FTS ([AppDatabase.swift:56](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/PersistenceKit/AppDatabase.swift), [AppDatabase.swift:245](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/PersistenceKit/AppDatabase.swift)).

`RunOutputStore` is a **live cache** keyed by run id, not durable storage ([RunOutputStore.swift:6](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/RunOutputStore.swift)). Durable chat history (conversation/turn/artifact) is separate and persisted.

The chat data model is **run/work oriented already**: conversations carry `agentID`, `vendor`, `hostName`, `cwd`, `model`, `budgetUSD`, status; artifacts are typed as tool/diff/file/test/preview/approval ([ChatConversation.swift:3](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/LancerCore/ChatConversation.swift), [ChatConversation.swift:102](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/LancerCore/ChatConversation.swift)).

## Existing design system

The core design system is substantial: semantic tokens, accent themes, typography, radii/spacing, glass chrome, buttons, chips, cards, status dots/icons, drawers, proof/privacy components, inbox cards, chat components, pixel/agent widgets, and error states ([Tokens.swift:84](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/DesignSystem/Tokens.swift), [Typography.swift:7](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/DesignSystem/Typography.swift), [DSButton.swift:3](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/DesignSystem/Components/DSButton.swift), [Primitives.swift:3](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/DesignSystem/Components/Primitives.swift), [LancerGlassChrome.swift:3](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/DesignSystem/Components/LancerGlassChrome.swift)).

**Design debt is mixed token adoption, not missing primitives.** Repo search found 152 `.font(.system...)`, 155 `Color(.sRGB...)`, 142 literal `cornerRadius: N`, and 197 literal width frames in Swift sources. Known issues already flag remaining hard-coded fonts in `DSApprovalBanner`, `InboxApprovalCard`, `DSOfflineState`, and `ChatInputBar`, plus color-only status dots ([docs/KNOWN_ISSUES.md:190](/Users/roshansilva/Documents/command-center/docs/KNOWN_ISSUES.md)).

> Durable gotcha for any redesign work: `DSButton.primary` renders **white**; `.accent` renders **orange**. Brand CTAs must use `.accent`. The app is **fixed-dark** (ignores system appearance).

## Platform targets

Real targets exist for Watch, widgets, and Live Activities ([project.yml:134](/Users/roshansilva/Documents/command-center/project.yml), [PhoneWatchConnector.swift:80](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/PhoneWatchConnector.swift), [LiveActivityManager.swift:12](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift)). The Watch app is intentionally **not embedded** in the iOS app for simulator install stability ([project.yml:138](/Users/roshansilva/Documents/command-center/project.yml)).

A hosted/cloud provisioning path (`ProvisioningWizard`, push backend, Stripe, GCP/Fly/AWS) is retained as **V2**, not V1 primary; several cloud paths are gated/stubbed ([ProvisioningWizard.swift:10](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/OnboardingFeature/ProvisioningWizard.swift), [ARCHITECTURE.md:87](/Users/roshansilva/Documents/command-center/ARCHITECTURE.md)).

## Redesign constraints (must not regress)

1. Preserve the sidebar / Command Home IA; do **not** reintroduce a tab bar ([ARCHITECTURE.md:269](/Users/roshansilva/Documents/command-center/ARCHITECTURE.md)).
2. Preserve the V1 **blind E2E relay** posture: the phone does **not** hold SSH in V1; SSH remains legacy/power-user for terminal/files/diff/preview ([ARCHITECTURE.md:49](/Users/roshansilva/Documents/command-center/ARCHITECTURE.md)).
3. Keep security **fail-closed**: TOFU prompt, Keychain, biometric gate, no secret logging ([docs/agent-contract.md:73](/Users/roshansilva/Documents/command-center/docs/agent-contract.md)).
4. Swift/iOS UI changes require the **Xcode app-target build**, not only SwiftPM, because app-shell code is `#if os(iOS)` ([AGENTS.md:30](/Users/roshansilva/Documents/command-center/AGENTS.md)).

## Technical constraints affecting redesign

- Many surfaces are coupled to backend state (observed sessions fan out only to the currently live host; Governance stats are stubbed; sidebar relay footer is hard-coded). See [02 — Screen and Component Inventory](02-screen-and-component-inventory.md) and [03 — Current UI Audit](03-current-ui-audit.md).
- Full workspace tooling (terminal/files/diff/preview) requires an SSH session; the relay cannot offer all workspace tools ([SessionWorkspaceContainer.swift:166](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/SessionWorkspaceContainer.swift)).
