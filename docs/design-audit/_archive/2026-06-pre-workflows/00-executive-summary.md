# 00 — Executive Summary

> Decision-oriented brief for the owner. Full research is in [01](01-current-product-and-codebase.md)–[15](15-implementation-roadmap.md); this doc names the five critical findings, the chosen direction, what to do first, and what remains unresolved. Read this, then [14](14-recommended-direction.md) (the implementation spec), then [15](15-implementation-roadmap.md) (the phase plan).

## What this audit is

A full-stack design audit of Lancer v1 — 10 research lanes across 4 waves, with 2 adversarial reviewers. Coverage: current product truth (repo + screenshots), Apple platform and Liquid Glass guidance, competitor/pattern research across 7 workflow categories, IA, chat/agent UX, approval/security UX, fleet/terminal, onboarding, monetization, and the design system. Audit date: 2026-06-29.

---

## Five critical findings

### 1. The live approval loop works — but the home lies
The phone→relay→daemon→approval return path is proven on device (live-loop C2 PASSED). The codebase is genuinely strong. But **Command Home currently shows fiction**: hard-coded sidebar footer "Relay connected · 3 hosts," stubbed Governance numbers (`AppRoot.swift:1390`), and contradictory machine state across three sources. For a governance product — where trust is the whole value — a fake safety number is worse than no number. **The trust-integrity fixes (`Phase 0.5`) are the prerequisite to everything else.** Direction A amplifies whatever the home displays; fix the home first or you amplify fiction.

### 2. The paywall is wired to nothing
`showingPaywall` is declared at `AppRoot.swift:191` and consumed at `:356` but **never set `true`**. `isPro=true` in DEBUG. The paywall gates nothing. This is the single highest-leverage monetization fix: wire `showingPaywall = true` at the three scale/automation triggers (3rd host, Pro feature tap, active-week moment) and the persistent Settings row. **No other monetization work matters until the trigger is wired.**

### 3. High/critical Approve is a single tap alongside Deny
`InboxApprovalDetail` presents a `.primary` Approve button next to Deny for consequential actions. This is the highest-risk UX gap: a distracted or thumb-slipping user can approve a critical destructive action in a single tap. **Fix before any redesign ships:** action-sheet confirm for `high`; mandatory `BiometricGate` for `critical`; `Deny` as the default/prominent option.

### 4. The design system is half-tokenized — and stopping further bypass is free
The `DesignSystem` module ships a complete, semantic, scheme-adaptive token set. The debt (~152 `.font(.system…)`, ~155 raw `Color(.sRGB…)`, ~142 literal `cornerRadius:`) is **bypass of a good system, not absence of one**. Three CI lint rules (fail on raw color/font outside `DesignSystem/`; warn on literal corner radius) stop new debt for zero implementation cost. **Add the lints before touching a single UI file.**

### 5. Glass is leaking into the content layer
`DSButton` applies `glassEffect` to **every button** — a direct violation of the WWDC25 Liquid Glass guideline ("glass is for the navigation layer, used sparingly, never in the content layer"). The fix is one call-site removal from `DSButton.swift`; the impact is that Lancer's buttons start reading solid/confident rather than "chrome on chrome."

---

## Recommended direction: A "Command Console"

**Direction A wins** (weighted matrix: A=420, C=395, B=340). The decisive margins: best fit to existing architecture (lowest build cost, lowest regression risk), best information scalability, balanced usability. Direction C (Safety-Triage) is the close second on trust/differentiation but depends entirely on zero-state quality and buries dispatch intent. Direction B (Conversation-Led) scores highest on dispatch speed but carries the highest Claude-clone risk.

The final direction is **A with C's framing and B's vocabulary grafted in**: A's dashboard home, C's risk-sorted attention-first triage and audit-forward posture, B's run/evidence vocabulary (state-sorted threads, work timeline, evidence cards).

**The one-sentence version:** Lancer is a warm control room for AI coding agents — what needs you, what's running, what your machines are doing — with a risk-tiered approval at the center, and chat as a governed run you drill into, never as the front door.

See [13](13-design-directions.md) for the full matrix and [14](14-recommended-direction.md) for the implementation spec.

---

## What to do first (ordered)

1. **Add the 3 CI lints** — stop raw-literal debt growth before touching anything. Zero risk. (Phase 0)
2. **Trust-integrity fixes** — un-stub the Governance numbers, fix machine state to one source, replace the hard-coded footer, fix billing copy. (Phase 0.5)
3. **Collapse `DSButton.primary`→`.accent`; de-glass buttons** — one DSButton.swift change; most visible quick win. (Phase 1)
4. **Up-gate the Approve button** — action-sheet for high, BiometricGate for critical, Deny as default. Security-sensitive; test with `swift test`. (Phase 2 entry point)
5. **Wire the dead paywall** — `showingPaywall = true` at the 3 triggers + persistent Settings row. (Phase 4, but if you can do it in a day, do it now)

---

## Adversarial review — corrections applied

**Applied to existing docs:**
- Doc 14: RELAY/DIRECT chip — V1 is relay-only; removed the DIRECT affordance spec from the V1 Machines screen (post-V1 only).
- Doc 12: `simctl ui appearance` description corrected — the command works but the app's scene-level `.preferredColorScheme(.dark)` overrides it; use the in-app `LancerAppearance` toggle for light-mode testing.

**Deferred to [`16-open-questions.md`](16-open-questions.md):**
- WWDC session numbers (219/356/260) are unverified guesses — verify before acting on any cited session.
- `developers.openai.com` Codex citation in doc 08 is a dead URL — remove or replace.
- US App Store external-link commission rate is **not 0%** — it is litigation-dependent and TBD; do not model Cloud V2 at 0% commission.
- `ASWebAuthenticationSession` is wrong for Stripe Checkout (V2 Cloud) — use `SFSafariViewController`.
- Run-thread structural chrome must render even when empty (governance identity before agent output).
- Onboarding install-bridge cliff edge — treat pairing as a Command Home re-engagement task, not a wall.
- Monetization trigger hierarchy: 3rd-host trigger is wrong for the V1 modal user (solo dev, 1 machine) — reorder to "after first value moment" as primary.
- Roadmap lacks time bounds and per-phase accessibility exit criteria.
- Continue band vs Threads sidebar root behavioral contract undefined.

---

## Scope and confidence

All Apple-platform claims are grounded in HIG, WWDC25, and App Store Connect docs. All competitor-pattern claims are grounded in Mobbin flows. All codebase claims are grounded in repo files read during Wave 1. **Beta caveat:** iOS 27 / Xcode 27 is beta at audit time; `glassEffect` behavior should be re-verified against shipping iOS 27. WWDC session numbers in docs 04 and 12 are unconfirmed — treat as titles only until verified. Full citation index: [sources.md](sources.md).
