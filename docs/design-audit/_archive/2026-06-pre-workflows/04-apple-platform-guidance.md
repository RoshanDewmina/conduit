# 04 — Apple Platform Guidance

> Source: Wave-2 Apple-platform research. Toolchain: Xcode 27 / iOS 27 beta, June 2026. Apple official docs are the authority.

## Source boundary

- **Stable guidance** (rely on): HIG fundamentals/components, accessibility, notifications, onboarding/privacy, App Review, StoreKit/IAP docs.
- **Beta-specific** (treat as moving until GM): iOS 27 / Xcode 27-era SwiftUI, Liquid Glass refinements, Device Hub.

## Recommendations (each: evidence → interpretation → Lancer fit → confidence)

1. **Keep the sidebar / Command Home IA.** [Sidebars HIG](https://developer.apple.com/design/human-interface-guidelines/sidebars) says sidebars are for top-level collections, need space, and should adapt to width. iPad → persistent `NavigationSplitView`; iPhone → drawer-first. Matches current shell, avoids a tab-bar regression. Caveat: sidebar bottom actions cannot carry critical state. **Confidence: High.**

2. **Use native toolbar/search conventions over custom chrome.** [Toolbars HIG](https://developer.apple.com/design/human-interface-guidelines/toolbars) frames toolbars as navigation/orientation/search/view actions with deliberate item count. Put New Chat, Search, Settings, approval filters, and run actions in predictable toolbar/menu slots. Terminal/chat composer may stay custom. **Confidence: High.**

3. **Make search a first-class cross-surface primitive.** HIG highlights [Navigation and Search](https://developer.apple.com/design/human-interface-guidelines/navigation-and-search); WWDC26 "Design intuitive search experiences." One search model across threads, hosts, approvals, audit, snippets. Search must not collide with chat compose. **Confidence: High.**

4. **Use lists/tables for scan-heavy operational surfaces.** [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) for grouped/hierarchical/selectable/editable data. Approvals, machines, audit, subscriptions, settings should lean on system list behavior; terminal transcript/code blocks stay custom. Dense audit rows need hierarchy, not tiny text. **Confidence: High.**

5. **Reserve alerts for blocking/destructive moments; use sheets for review/setup.** Approval detail, host pairing, policy scope, billing recovery → sheets/drill-ins; alerts only for irreversible revoke/deny/emergency-stop confirmation. Errors belong in alerts, not notifications. **Confidence: High.**

6. **Adopt Liquid Glass only in the functional/navigation layer.** [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials) says Liquid Glass is for controls/navigation, explicitly **not** the content layer; [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) says system frameworks should carry most adoption. Use on sidebar, toolbar buttons, floating composer, action rail. **Avoid glass on logs, code, diffs, approval text, transcript cards.** Beta APIs/appearance may change. **Confidence: Medium-high.**

7. **Prefer system typography; mono only for code/terminal/proof.** [Accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility): iOS 17pt default text, 11pt minimum for custom type; explicit contrast guidance. Constrain Lancer's heavy mono/all-caps to agent/proof affordances, not body/billing/onboarding. **Confidence: High.**

8. **Strengthen accessibility for high-risk decisions.** Adequate contrast, system colors, never color alone. Approval cards need VoiceOver labels including agent, host, command risk, blast radius, and result; approve/deny must differ by text/icon/shape, not just green/red. Dynamic Type must reflow cards through accessibility sizes. **Confidence: High.**

9. **Notifications and Live Activities stay privacy-preserving.** [Notifications HIG](https://developer.apple.com/design/human-interface-guidelines/notifications): concise, high-value, no confidential information; [Live Activities HIG](https://developer.apple.com/design/human-interface-guidelines/live-activities): glanceable task state. Keep redacted lock-screen copy and deep-link to unlocked detail. Simulator can't prove APNs/lock-screen. **Confidence: High.**

10. **Ask permissions only when the payoff is understood.** [Onboarding HIG](https://developer.apple.com/design/human-interface-guidelines/onboarding): postpone nonessential setup, ask contextually; [Privacy HIG](https://developer.apple.com/design/human-interface-guidelines/privacy) restricts pre-permission screens. Request notifications **after** pairing or first approval explanation, not on first launch. Pairing flow stays value → pair → policy. **Confidence: High.**

11. **Reconcile "no subscriptions" copy with StoreKit / App Review reality.** [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [In-App Purchase](https://developer.apple.com/in-app-purchase/), [Subscriptions](https://developer.apple.com/app-store/subscriptions/): digital features/subscriptions use StoreKit with clear management + restore. One-time Pro via StoreKit is strong. If "Lancer Cloud" unlocks digital app functionality, do **not** route iOS users to Stripe unless a specific entitlement/exception applies; phrase as "no subscription for your own hardware," not "no subscriptions ever." **Confidence: Medium-high.** (See [11](11-monetization-and-upgrade-strategy.md).)

12. **Use StoreKit-native surfaces where they reduce review risk.** [StoreKit](https://developer.apple.com/documentation/storekit) promotes StoreKit views + StoreKit 2 entitlement/status APIs. Keep `Transaction.currentEntitlements`, restore, StoreKit testing, and a clear in-app manage/restore path. The visible purchase path stays Apple-compliant even if RevenueCat assists entitlement ops. **Confidence: High.**

13. **Device Hub is audit evidence, not a replacement for physical-device proof.** WWDC26 [Get the most out of Device Hub](https://developer.apple.com/videos/play/wwdc2026/260/) positions it as one workspace for devices/simulators + repro. Use for simulator-matrix capture + reproducible bug notes. APNs, killed-app approval, Live Activity push, Watch handoff, lock-screen actions still need physical-device proof. **Confidence: High.**

## Highest-priority platform implications for Lancer

- Keep the sidebar / Command Home direction.
- Reduce custom chrome around navigation/search/settings.
- Treat Liquid Glass as restrained system chrome, **not** a brand texture.
- Make approvals accessible and privacy-safe **before** making them prettier.
- Fix billing language before App Review: "pay once for Pro on your own hardware; optional cloud subscription separately" beats "no subscriptions ever."
