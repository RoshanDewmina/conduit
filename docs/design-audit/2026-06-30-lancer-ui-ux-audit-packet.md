# Lancer UI/UX Audit Packet

Updated: 2026-06-30  
Audience: product design, iOS engineering, launch review

## Purpose

This packet is the working handoff for the Lancer UI/UX polish pass. It turns the existing simulator captures, code inventory, V1 product constraints, and Mobbin pattern research into workflow-level recommendations a designer can review and approve before implementation.

The packet is intentionally practical: each workflow maps recommendations back to current SwiftUI files and locked V1 behavior. It should not be used to invent parallel UI or revive deferred V2 surfaces.

**Redesign latitude:** Recommendations may propose a **full screen or whole-app redesign** when Mobbin research and current-state evidence show a materially better UX. Prefer the strongest outcome over preserving the current layout. Call out redesign scope (targeted fix vs full overhaul) in each workflow doc.

## Source Hierarchy

Use this order when sources disagree:

1. Current app code and verified simulator captures.
2. `docs/V1_PRODUCT_SPEC.md` and `docs/V1_STATE_AND_ACTION_MATRIX.md`.
3. `ARCHITECTURE.md` current-state snapshot and navigation notes.
4. Active workflow docs in `docs/design-audit/workflows/` (this packet).
5. Mobbin references, Apple HIG, and comparable app patterns.

Older numbered audit files (`00`–`16`) are archived at [`_archive/2026-06-pre-workflows/`](_archive/2026-06-pre-workflows/) for background only — do not treat them as the active handoff.

## Workflow Files

- [Mobbin Research Log](mobbin-research-log.md)
- [Onboarding / Pairing](workflows/01-onboarding-pairing.md)
- [Home / Attention Overview](workflows/02-home-attention-overview.md)
- [Work Thread](workflows/03-work-thread.md)
- [Review / Approvals / Diff Review](workflows/04-review-approvals-diff.md)
- [Machines](workflows/05-machines.md)
- [Settings](workflows/06-settings.md)

## Current Evidence

The current screenshot set lives in `docs/design-audit/screenshots/current/`. It includes first-run onboarding, unified value/pairing chrome, account choice, offline-name capture, notification prompt, Home attention states, sidebar drawer, seeded approval inbox, machines/fleet, governance, settings, and iPad split view.

The latest live simulator check for onboarding used the Lancer app target on an iPhone 17 Pro simulator. It confirmed that the unified onboarding chrome from PR #13 is present, code-only pairing is visible, and `OnboardingValueRows` remains the weakest part of the first-run impression.

Mobbin screenshots are referenced by canonical links in this packet rather than copied into the repo. Current Lancer screenshots are stored locally; third-party reference images remain on Mobbin.

## Product Guardrails

- Keep V1 navigation to Home, Work, Machines, and Settings. Do not reintroduce a tab bar or a separate Control/Activity root.
- Pairing is code-only for V1. QR scanner, phone-origin pairing, and camera-based setup are deferred unless the locked V1 docs change.
- Work Thread is a read-only activity log in V1. Do not expose an interactive terminal or phone IDE behavior.
- Safety and approval controls cannot be paywalled. Upgrade prompts can explain capacity or hosted features, but not block safety basics.
- Do not show fake governance numbers, fake trust scores, fake billing claims, or contradicted machine states.
- Risk must not be communicated by color alone.

## Workflow Checklist

| Workflow | Current issues | Research complete | Approved | Implemented | Verified |
| --- | --- | --- | --- | --- | --- |
| Onboarding / pairing | Unified chrome works, but value rows are abstract; pairing errors are easy to miss; notification-denied recovery missing; QR paths must stay deferred. | Yes | **Awaiting** | Partial: unified chrome and code-only pair screen exist. | Partial: primary path captured; pairing edge states documented, not yet screenshotted. |
| Home / attention overview | Split-brain headline vs NEEDS ATTENTION cards; hardcoded sidebar “3 hosts”; Inbox competes with Home; all-clear captured; NEEDS ATTENTION on Home + loading/offline not capturable without fleet slot. | Yes | Skipped (proceeded to WF03) | No | Partial: all-clear, pending headline, seeded machine, sidebar refreshed 2026-06-30; iPad Jun 29. |
| Work thread | Chat-bubble transcript vs V1 activity-log spec; terminal cards prominent; no phase module; running/approval states not capturable without live dispatch. | Yes | **Awaiting** | Partial: NewChatTabView + ChatHistoryView exist. | Partial: composer, completed, failed, empty captured 2026-06-30; live run + approval-blocked gaps. |
| Review / approvals / diff review | Dual approval designs (Inbox card vs detail vs Home sheet); inline approve may skip evidence; Inbox competes with Home; detail/diff captures missing. | Yes | **Awaiting** | Partial: `InboxApprovalDetail`, `InboxView`, biometric on critical. | Partial: inbox list captured 2026-06-30; detail sheet + diff gaps. |
| Machines | Relay vs slot split; contradictory sidebar footer; terminal drill-in risk; one canonical status row needed. | Yes | **Awaiting** | Partial: `FleetView` + relay card exist. | Partial: seeded relay fleet captured 2026-06-30; detail/diagnostics gaps. |
| Settings | Governance dual root; plan/Pro copy launch risk; safety must not be paywalled; terminal prefs scope creep. | Yes | **Awaiting** | Partial: `SettingsView` + `GovernanceHomeView`. | Partial: settings + governance captured 2026-06-30; paywall/light mode gaps. |

## Recommended Direction

Use the "warm control room" direction from the existing design audit: a quiet, high-trust command console with strong information density, explicit machine state, proportional risk controls, and restrained native iOS surfaces. The product should feel like mobile mission control for AI coding agents, not a chat clone, developer toy, or crypto/security dashboard.

The strongest cross-workflow pattern is:

1. Home starts with what needs attention now.
2. Work Thread explains what the agent is doing and what changed.
3. Review turns risk into an evidence-led decision.
4. Machines explains connection health and setup state.
5. Settings handles identity, safety defaults, notifications, and diagnostics without competing with daily work.

## Design System Targets

- Typography: prefer a small set of semantic roles: large title, section title, body, secondary, caption, monospaced evidence. Avoid one-off `.font(.system(...))` sizing in screens.
- Colors: use semantic tokens for background, grouped surface, card surface, divider, label, secondary label, accent, risk, success, warning, danger, offline. Avoid raw sRGB colors in feature files.
- Spacing: standardize at 4, 8, 12, 16, 20, 24, and 32. Use denser spacing for lists, more breathing room only for first-run and empty states.
- Cards and surfaces: content cards should be 8 pt radius or less. Use grouped lists and native sheets where possible. Avoid glass or tinted panels on dense content.
- Buttons: use primary, secondary, destructive, and text actions. Approval decisions need persistent action placement and clear disabled/loading states.
- Icons: use SF Symbols consistently; icons should label state or action, not decorate generic claims.
- Lists: rows should have leading semantic icon/status, primary text, secondary evidence, trailing state/action. Avoid mixed row heights in the same list.
- Sheets/dialogs: use native sheet detents for review/detail; reserve alerts for destructive or permission-blocked decisions.
- Loading/empty/error/offline: every workflow needs specific copy and a recovery action. Do not leave blank skeletons or generic "Something went wrong" states.
- Accessibility: dynamic type must preserve action hierarchy; risk decisions need VoiceOver labels that include risk level and consequence.

## Approval Gate

Onboarding is the first workflow for design approval. The recommended change is to replace the three abstract value rows with one real Lancer product visual, preferably a static screenshot first, with an optional looping simulator recording later and a Reduce Motion fallback.

No implementation should start for a workflow until that workflow's recommendation is approved.
