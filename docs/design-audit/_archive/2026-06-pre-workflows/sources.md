# Sources

> Full citation index for the Lancer design audit (docs 01–16, audit date 2026-06-29). Organized by source type. **Note on WWDC session numbers:** numbers cited in docs 04 and 12 are unverified — see [16-open-questions.md §Q8](16-open-questions.md). Treat as title references until confirmed against the Apple video catalog.

---

## Apple official — HIG, WWDC, App Store Connect

### Human Interface Guidelines
- [HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) — sidebar shell, NavigationSplitView; cited in [04](04-apple-platform-guidance.md), [06](06-information-architecture.md)
- [HIG: Materials / Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials) — glass-in-nav-only rule; cited in [04](04-apple-platform-guidance.md), [12](12-design-system-recommendations.md)
- [HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography) — Dynamic Type, font roles; cited in [12](12-design-system-recommendations.md)
- [HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color) — color-alone prohibition, dark/light, contrast; cited in [12](12-design-system-recommendations.md)
- [HIG: Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts) — `confirmationDialog` for destructive actions; cited in [08](08-approval-and-security-experience.md), [12](12-design-system-recommendations.md)
- [HIG: Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications) — `.authenticationRequired` action option; cited in [08](08-approval-and-security-experience.md)
- [HIG: In-App Purchase](https://developer.apple.com/design/human-interface-guidelines/in-app-purchase) — IAP display rules, billing language; cited in [11](11-monetization-and-upgrade-strategy.md)
- [HIG: Offering, completing, and restoring purchases](https://developer.apple.com/design/human-interface-guidelines/offering-completing-and-restoring-in-app-purchases) — Restore Purchases requirement; cited in [11](11-monetization-and-upgrade-strategy.md)
- [HIG: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities) — content budget, no-interaction constraint; cited in [09](09-fleet-activity-and-terminal.md)
- [HIG: Watch](https://developer.apple.com/design/human-interface-guidelines/apple-watch) — Watch complication / notification limits; cited in [08](08-approval-and-security-experience.md)
- [HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) — Dynamic Type, VoiceOver, contrast, Reduce Motion; cited across [08](08-approval-and-security-experience.md), [12](12-design-system-recommendations.md)
- [HIG: SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) — symbol weight matching, accessibility names; cited in [12](12-design-system-recommendations.md)

### WWDC sessions (⚠️ session numbers unverified — see Q8 in [16](16-open-questions.md))
- WWDC25 "Meet Liquid Glass" (session ~219) — Liquid Glass introduction, navigation-layer-only guidance
- WWDC25 "Design with the new design system" (session ~356) — updated Apple design language 2025
- WWDC26 "Get the most out of Device Hub" (session ~260) — Device Hub, multi-device testing
- WWDC26 "Design intuitive search experiences" (title unconfirmed) — cross-surface search

### App Store Connect / App Review
- [App Store Connect: Dark Interface evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/dark-interface-evaluation-criteria/) — Dark Interface claim; cited in [12](12-design-system-recommendations.md)
- [App Store Review Guidelines §3.1.1](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase) — IAP requirement for digital goods; cited in [11](11-monetization-and-upgrade-strategy.md)
- [App Store Review Guidelines §3.1.1(a)](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase) — US external-link allowance (post-Epic ruling); cited in [11](11-monetization-and-upgrade-strategy.md)
- [App Store Review Guidelines §3.1.3](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase) — Reader app exception (SaaS/web services); cited in [11](11-monetization-and-upgrade-strategy.md)

---

## StoreKit / Apple developer docs

- [StoreKit 2: `Transaction.currentEntitlements`](https://developer.apple.com/documentation/storekit/transaction/currententitlements) — entitlement check; cited in [11](11-monetization-and-upgrade-strategy.md)
- [StoreKit 2: `AppStore.sync()`](https://developer.apple.com/documentation/storekit/appstore/sync()) — Restore Purchases implementation; cited in [11](11-monetization-and-upgrade-strategy.md)
- [StoreKit 2: `Transaction.isFamilyShared`](https://developer.apple.com/documentation/storekit/transaction/isfamilyshared) — Family Sharing entitlement; cited in [11](11-monetization-and-upgrade-strategy.md), [16](16-open-questions.md)
- [StoreKit 2: `Product.SubscriptionOffer`](https://developer.apple.com/documentation/storekit/product/subscriptionoffer) — free-trial limitation (subscriptions only, not non-consumables); cited in [11](11-monetization-and-upgrade-strategy.md)
- [Local StoreKit configuration](https://developer.apple.com/documentation/storekit/testing-in-xcode-using-storekit-configuration-files) — sandbox testing; cited in [11](11-monetization-and-upgrade-strategy.md)
- [`UNNotificationActionOptions.authenticationRequired`](https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/authenticationrequired) — lock-screen approval gating; cited in [08](08-approval-and-security-experience.md)
- [`LocalAuthentication / LAContext`](https://developer.apple.com/documentation/localauthentication/lacontext) — BiometricGate; cited in [08](08-approval-and-security-experience.md)

---

## Repo files consulted (Wave 1 — source of truth over any doc)

All paths relative to repo root (`/Users/roshansilva/Documents/command-center/`).

| File | Used for |
|---|---|
| `Packages/LancerKit/Sources/DesignSystem/Tokens.swift` | Token audit, raw-literal debt counts |
| `Packages/LancerKit/Sources/DesignSystem/Typography.swift` | Type scale, Dynamic Type pattern |
| `Packages/LancerKit/Sources/DesignSystem/Components/DSButton.swift` | Glass-on-buttons finding |
| `Packages/LancerKit/Sources/DesignSystem/LancerGlassChrome.swift` | Legitimate glass use sites |
| `Packages/LancerKit/Sources/DesignSystem/Primitives.swift` | Raw-literal debt |
| `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` | Stubbed Governance numbers (line 1390), paywall state (lines 191, 356), Tab enum, IA |
| `Packages/LancerKit/Sources/InboxFeature/InboxView.swift` | Approval flow, InboxApprovalDetail |
| `Packages/LancerKit/Sources/InboxFeature/InboxApprovalDetail.swift` | P0 single-tap Approve finding |
| `Packages/LancerKit/Sources/SettingsFeature/SettingsView.swift` | Trust copy (SwiftData/RevenueCat stale), Pro gate, billing |
| `Packages/LancerKit/Sources/StoreKit/PurchaseManager.swift` | StoreKit 2 entitlement implementation |
| `Packages/LancerKit/Sources/SecurityKit/BiometricGate.swift` | Biometric gate implementation |
| `Packages/LancerKit/Sources/MachinesFeature/` | Machine state source-of-truth conflict |
| `Packages/LancerKit/Sources/LancerCore/ApprovalSummary.swift` | `ApprovalSummary.derive(from:)` |
| `Packages/LancerKit/Sources/LancerCore/Approval.swift` | Risk enum (low/medium/high/critical) |
| `daemon/lancerd/` (Go) | Daemon architecture, dispatch.go |
| `ARCHITECTURE.md §0.1` | Current-state snapshot (implemented/partial/planned/deprecated) |
| `ARCHITECTURE.md §4.1` | Navigation ground truth (sidebar, not tab bar) |
| `project.yml` | XcodeGen config, bundle IDs, target structure |
| `docs/agent-contract.md` | Architecture invariants |
| `docs/KNOWN_ISSUES.md` | Active issue tracker |

---

## Competitive patterns — Mobbin evidence

Evidence organized by workflow; each research lane (docs 06–11) records the full Mobbin query, observed pattern, weakness, and Lancer fit.

| Workflow | Primary apps studied |
|---|---|
| Navigation / product shell | GitHub Mobile, Slack, Linear, Tailscale, Raycast, Notion, Vercel |
| Chat / agent interaction | ChatGPT, Claude, Gemini, Copilot, Perplexity, Codex mobile, Cursor, Linear agents |
| Approvals / high-risk actions | Revolut Business, Manus, Codex, YNAB, Clubhouse, Visible, Discord |
| Onboarding / pairing / trust | Copilot, WhatsApp linked-devices, Telegram device management, Brave VPN, Marcus, adidas |
| Fleet / terminal / activity | Telegram, Starlink, Apple Home, Google Home, Tailscale, Termius, Mimo, GitHub Mobile checks |
| Monetization / upgrade | QUITTR, Sunlitt, Hevy, Fabulous, Raycast Pro, Manus, mymind, Vivino, Grok (anti-pattern) |
| Design system / identity | GitHub iOS (mono discipline), Claude, Linear, Raycast |

---

## Legal / App Store policy (external)

- Epic Games, Inc. v. Apple Inc. — US district court injunction (2021) + Ninth Circuit + subsequent compliance orders governing external-link allowance on the US storefront. **⚠️ Commission rate for US external links is TBD / litigation-dependent as of audit date.** Verify at `developer.apple.com/news/` before modeling Cloud V2. See [16 §Q10](16-open-questions.md).
- Apple developer news on alternative payment link entitlement — monitor for rate updates.

---

## What is NOT cited here

- `~/Documents/Obsidian/files` — retired vault, not consulted.
- `docs/LANCER_PROJECT_DOSSIER.md` — archived, not cited.
- Any `developers.openai.com` URL — domain does not exist; see [16 §Q9](16-open-questions.md) for the dead Codex citation in doc 08.
