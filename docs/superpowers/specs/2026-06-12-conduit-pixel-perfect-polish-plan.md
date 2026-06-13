# Conduit pixel-perfect polish plan

## Status — 2026-06-13 (batch 1: the 4 main tabs)
**DONE** (built + visually verified light+dark): **P1-7** header gutter 18→16 app-wide · **P0-1** Settings header flush (system toolbar/circular button → square `DSIconButton` in `DSScreenHeader` trailing + nav bar hidden + Library via `navigationDestination`) · **P0-3** Activity/`BridgeAuditFeedView` system fonts → `.dsMonoPt` · **P0-4** Activity double-empty-state → single `DSEmptyState(.server, "not connected")` · **P1-8/P1-9** Settings `sectionHead` 20→16 + mono typography matching `DSListSectionHead` · **P1-19** Fleet stat labels 10→11pt / `t.text2`.
Result: Inbox/Fleet/Activity/Settings now share identical header geometry + DS empty states in both appearances.

**REMAINING** (secondary screens / fine-tuning — safe to do next): P0-2 Billing DS header · P0-5 MCP card buttons 44pt · P0-6 Fleet glyph slot (row is already a button) · P1-10/11 Billing card chrome+dividers · P1-12 `DSButton` 44pt (global — do carefully) · P1-13 Settings row padding 12/13 · P1-14 onboarding/Connect-sheet DS headers · P1-15/16/17 paywall surfaces · all P2.

---


Read-only audit (2026-06-12) of the 4 shipping tabs (Inbox, Fleet, Activity, Settings) plus onboarding, add-host, paywall, billing, compare, about. Issues located to `file:line` with exact token/value fix.

Key reference values:
- Header horizontal padding = **18** (`DSScreenHeader.swift:64`). Tab content padding = **16**. Settings section/body = **20 / 16**. These three competing values (16/18/20) cause most misalignment.
- `.dsCard()` = `t.surface` + 1px `t.border` + `t.r4`, padding 14.
- Tokens: `s5=16`, `s6=20`; `r3=0`, `r4=0` (square), `r5=4`.

## P0 — breaks consistency / HIG violations

1. **Settings header geometry differs (system nav bar + circular button).** `AppRoot.swift:1094-1105` uses a system `ToolbarItem` rendering a circular `square.grid.2x2` button → adds nav-bar top inset (pushes `settings_` ~40px lower than other tabs) + a circular button that exists nowhere else. Fix: move the Library action into `DSScreenHeader` `trailing:` as `DSIconButton`, drop the toolbar item, `.toolbar(.hidden, for: .navigationBar)` on Settings.
2. **BillingView uses system nav title.** `BillingView.swift:112-113` `.navigationTitle("Billing")` — only settings-family screen with a stock bar. Fix: `DSDetailHeader("billing", onBack:)` or `DSScreenHeader`, remove nav-title lines.
3. **Activity "while you were away" empty state uses system `ContentUnavailableView` + system fonts.** `BridgeAuditFeedView.swift:18-23` + `:29-46` use SF fonts / `.caption`. Fix: `DSEmptyState(dotMatrix:.idle, title:"no decisions yet", …)`; replace `.caption*`→`.dsMonoPt`.
4. **Activity shows TWO stacked empty/error states.** `ActivityView.swift:32-44` shows loadError card AND BridgeAuditFeedView empty state. Fix: guard feed with `else if loadError == nil`; route disconnected through one `DSEmptyState(icon:.server,…)` matching Fleet.
5. **MCP approval-card buttons < 44pt.** `InboxCards.swift:262-316` ~34pt tall. Fix: swap to real `DSButton` variants or `.frame(minHeight:44).contentShape(Rectangle())`.
6. **Fleet reconnect glyph touch target << 44pt.** `FleetView.swift:116` 15pt glyph, no dedicated hit area / fixed-width slot. Fix: wrap in `.frame(width:44,height:44).contentShape(Rectangle())`, constant-width trailing slot.

## P1 — visible polish

7. **Tab content inset 16 but header inset 18 — 2px left misalignment every tab.** `DSScreenHeader.swift:64` (18) vs content 16 (`InboxView.swift:87,103`; `FleetView.swift:55,68,82`; `ActivityView.swift:43,47`). Fix: change header `18`→`16` (also `DSDetailHeader.swift:130`).
8. **`DSListSectionHead` pads 16 but Settings `sectionHead` pads 20.** `Composites.swift:549` vs `SettingsView.swift:662`. Fix: Settings `20`→`16` (also `:392,200`).
9. **Two section-head typographies for the same role.** Settings `dsDisplayPt(10)` (`SettingsView.swift:659-661`) vs `DSListSectionHead` `dsMonoPt(11,.medium)` (`Composites.swift:538-539`). Fix: standardize on `DSListSectionHead`.
10. **BillingView card chrome differs.** `BillingView.swift:233-236` `t.r3`+0.5px vs SettingsView `t.r4`+1px (`:673-676`). Fix: `r3`→`r4`, `0.5`→`1` (also `PremiumComparisonView.swift:102-103`).
11. **Hairline divider weights inconsistent (0.5 vs 1px).** `BillingView.swift:242` vs `DSDivider` (`SettingsView.swift:720`). Fix: use `DSDivider(.soft, leadingInset:16)`.
12. **`DSButton(size:.sm/.md)` both < 44pt.** `DSButton.swift:130` `.sm=26,.md=32,.lg=40`. Fix: add `.frame(minHeight:44).contentShape(Rectangle())` to interactive buttons (pad tappable area, not fill); raise `.md`→36, `.lg`→44.
13. **Settings row vertical padding drift (12 vs 13).** `SettingsView.swift:230-242` (12) vs `:699-715` (13). Fix: unify to 12 (`:714,742,696`).
14. **Onboarding/PasswordPrompt headers don't use DS header.** `OnboardingView.swift:115-120`; Connect sheet `AppRoot.swift:1153-1163` raw `Text` + circular close. Fix: Connect sheet → `DSDetailHeader("connect", onBack:)`.
15. **Paywall spectrum height 8 / full-bleed overhangs content.** `PaywallSheet.swift:24`. Fix: `.padding(.horizontal,20)` or standardize.
16. **Paywall gutter 20 vs PremiumComparison 16.** `PaywallSheet.swift:133` vs `PremiumComparisonView.swift:105,143`. Fix: both 16.
17. **AddHost disabled CTA low-contrast (45% accent).** `AddHostView.swift:768-776` + `DSButton.swift:104`. Fix: neutral disabled treatment (`t.surfaceSunk` + `t.text4`).

## P2 — nitpicks

18. Inbox decided-row padding — resolved by P1-7.
19. Fleet stat labels tiny (10pt mono, low contrast dark) — `FleetView.swift:151` → `dsMonoPt(11)`/`t.text2`.
20. AskQuestion checkmark uses SF system glyph — `InboxCards.swift:136-138` → `DSIconView(.check,…)`.
21. Inbox risk pill color vs quote-block tone dual-encoding — `ChatComponents.swift:254-269`.
22. Onboarding CTA/wordmark/body gutter parity — `OnboardingView.swift`.
23. Settings "Save keys" orphaned right-aligned — `SettingsView.swift:268-272`.

## Suggested execution order
1. P0-1 + P0-2 + P1-14: header unification (all tabs flush `DSScreenHeader`).
2. P1-7 + P1-8 + P1-9: collapse 16/18/20 padding zoo to one 16pt gutter + one section-head.
3. P0-3 + P0-4: Activity/away empty states.
4. P0-5 + P0-6 + P1-12: 44pt touch-target pass.
5. P1-10 + P1-11: card chrome + divider weights.
6. P1-15 + P1-16 + P1-17: purchase-surface polish.
7. P2 batch.

Files most touched: `DSScreenHeader.swift`, `SettingsView.swift`, `BillingView.swift`, `ActivityView.swift`, `BridgeAuditFeedView.swift`, `InboxCards.swift`, `ChatComponents.swift`, `FleetView.swift`, `DSButton.swift`, `PaywallSheet.swift`, `PremiumComparisonView.swift`, `AppRoot.swift`.
