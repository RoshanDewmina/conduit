# 03 — Current UI Audit

> Source: Wave-1 repo audit + running-app capture. Severity: **P0** = harms comprehension, safety, trust, or core usability · **P1** = materially reduces quality/consistency · **P2** = polish.

## Diagnosis in one line

Lancer's *structure* is right (governance-first, attention-first Command Home, sidebar shell) but its *surface integrity* leaks: several headline numbers are stubbed or hard-coded, two pairing mental models coexist, trust/billing copy contradicts the real stack, and styling is half-tokenized. The result reads as a competent app with trust-eroding seams — exactly the wrong failure mode for a governance product whose whole pitch is "trust us with your machines."

## P0 — comprehension / safety / trust

No repo-confirmed open **code** P0 in `KNOWN_ISSUES`. Release evidence is gated (app-target archive/build, remote-host E2E, StoreKit TestFlight purchase, App Review metadata, APNs/DNS, owner-operated production setup) — see [PUBLISH_READINESS_CHECKLIST.md:40](/Users/roshansilva/Documents/command-center/docs/PUBLISH_READINESS_CHECKLIST.md).

However, two **UX-level P0s** surface from capture because they break the product's core promise of trustworthy state:

| ID | Finding | Cause | User impact | Local/systemic | Principle |
|---|---|---|---|---|---|
| P0-1 | **Stubbed governance headline numbers.** Governance Home shows audit count / chain-verification / preset values that `AppRoot` passes as stubs ([AppRoot.swift:1390](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/AppRoot.swift)); sampled `0 hosts` even with an active fake relay. | View takes literals instead of live stores. | For a *governance* product, a fake "audit verified" number is worse than no number — it actively misleads about safety state. | Local (wiring), systemic (trust pattern). | **Never display a safety/trust statistic the app cannot back with live state.** Show "—" or an empty state instead. |
| P0-2 | **Contradictory machine state.** Machines sampled with header `Dev VPS / online·healthy`, relay card `hermes-box`, and stat card `Connection: Offline` simultaneously. | Multiple state sources not reconciled; comment drift claims `ApprovalRelay` doesn't exist ([FleetStore.swift:9](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/FleetStore.swift)). | The user cannot tell whether their machine is reachable — the single most load-bearing fact in an ops app. | Local. | **One machine, one reconciled status.** Status = icon + label + severity + timestamp from one source. |

## P1 — quality / consistency

| ID | Finding | Cause | Impact | Principle |
|---|---|---|---|---|
| P1-1 | **Pairing mental-model conflict.** Active onboarding says the desktop generates the code; `BridgePairingView` says the phone generates the QR/code ([OnboardingRedesignGalleryView.swift:297](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/OnboardingFeature/OnboardingRedesignGalleryView.swift), [BridgePairingView.swift:10](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/OnboardingFeature/BridgePairingView.swift)). | Two pairing implementations coexist. | First-run pairing is the activation moment; a contradictory model is the highest-leverage drop-off. | Pick one direction-of-trust and use it everywhere. |
| P1-2 | **Hard-coded sidebar footer** "Relay connected · 3 hosts" ([LancerSidebarView.swift:310](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/LancerSidebarView.swift)). | Literal string. | Same trust-erosion as P0-1, lower visibility. | Bind to live relay state or remove. |
| P1-3 | **Trust/billing copy names the wrong stack.** Trust Center copy references SwiftData/RevenueCat; repo uses GRDB/StoreKit/Stripe ([SettingsView.swift:203](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/SettingsFeature/SettingsView.swift), [SettingsView.swift:220](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/SettingsFeature/SettingsView.swift)). | Copy drift. | A privacy/trust screen that misdescribes its own data handling is an App-Review and credibility risk. | Trust copy must be generated from / checked against the real stack. |
| P1-4 | **DEBUG billing contradiction:** profile + Billing show "Pro unlocked" while Billing also shows "Product not found. Check that Lancer.storekit is selected." StoreKit config declared but not loaded in the sampled run. | StoreKit config not loaded under XcodeBuildMCP launch. | Confusing entitlement state; blocks purchase verification. | Entitlement and product-load state must be consistent; surface a single source of truth. |
| P1-5 | Relay approval no-op diagnostic still listed; relay budget controls return false; old tab-based UI tests remain skipped; hosted entitlement persistence is owner/backend-gated ([docs/KNOWN_ISSUES.md:249](/Users/roshansilva/Documents/command-center/docs/KNOWN_ISSUES.md), [docs/KNOWN_ISSUES.md:83](/Users/roshansilva/Documents/command-center/docs/KNOWN_ISSUES.md)). | Partial features. | Mixed. | Either finish or hide partial controls; don't ship inert affordances. |

## P2 — polish

| ID | Finding | Principle |
|---|---|---|
| P2-1 | Dynamic Type / VoiceOver sweep incomplete ([docs/KNOWN_ISSUES.md:3](/Users/roshansilva/Documents/command-center/docs/KNOWN_ISSUES.md)). | Approval and machine rows must reflow + carry VoiceOver labels. |
| P2-2 | Hard-coded style cleanup (152 fonts / 155 colors / 142 radii / 197 widths). | Migrate to tokens; see [12 — Design System](12-design-system-recommendations.md). |
| P2-3 | Color-only status indicators ([docs/KNOWN_ISSUES.md:203](/Users/roshansilva/Documents/command-center/docs/KNOWN_ISSUES.md)). | Never color alone: icon + label + shape. |
| P2-4 | Coachmark auto-start disabled; AppRoot/SessionViewModel complexity ([AppRoot.swift:707](/Users/roshansilva/Documents/command-center/Packages/LancerKit/Sources/AppFeature/AppRoot.swift)). | Decompose during shell refactor. |
| P2-5 | Heavy mono/all-caps styling beyond code/proof affordances. | Constrain mono to code/terminal/proof; body uses system type (see [04](04-apple-platform-guidance.md)). |
| P2-6 | V2 hosted-cloud surfaces can confuse V1 scope if exposed early. | Keep out of V1 nav. |

## Audit across the dimensions the plan requires

- **Information hierarchy / density:** Command Home's "machines → projects → sessions" model is sound; the failure is trust integrity, not layout.
- **Status communication:** weakest axis — stubbed numbers, hard-coded footer, contradictory machine state, color-only dots.
- **Component consistency:** primitives are strong; adoption is uneven (half-tokenized).
- **Risk communication:** approval cards carry risk + biometric gate (good base) but rely partly on color; needs the severity model in [08](08-approval-and-security-experience.md).
- **Differentiation / Claude resemblance:** chat grammar is borrowed but the frame is governance-first; resemblance risk is real and addressed in [07](07-chat-and-agent-experience.md).
- **Accessibility / platform conventions:** Dynamic Type + VoiceOver + contrast incomplete; mono overuse fights Apple's 17pt-body default.
