# 16 — Open Questions

> Unresolved questions from the audit, including pre-existing open items and new items raised by the Wave 4 adversarial review. Every item here must be resolved before the phase it gates. Owner = Roshan unless a doc or code reference is cited.

---

## Design decisions (must resolve before implementation phase noted)

### Q1 — Pairing mental model: who generates the code? (before Phase 4)
The current codebase shows both "desktop-generates-QR" and "phone-generates-QR" patterns in different surfaces (P1-1 in [03](03-current-ui-audit.md)). **Make the pick and apply it everywhere.**

Recommendation: **desktop-generates, phone-scans** — `lancerd` on the desktop generates a QR code (following the WhatsApp linked-devices / iOS pairing pattern), the phone opens the camera and scans. This is the most widely understood mobile-pairing flow and avoids the phone needing to generate a secret. Update all onboarding copy and any `PairingView` that generates from the phone side.

**Gates:** Phase 4 (Onboarding rebuild).

---

### Q2 — Continue band vs Threads root: behavioral contract (before Phase 3)
[14](14-recommended-direction.md)'s navigation model lists both a **Continue** band on Command Home (recent runs) and a **Threads / Recent work** sidebar root. Without a defined behavioral contract, these look identical to users.

**Proposed contract:** Continue band = curated 3–5 most recently active runs (not paginated), with a "See all →" affordance that deeplinks to Threads root. Threads root = complete paginated run history with search/filter. Express the distinction visibly (band label + "See all" vs full list header).

If timeline forces simplification: eliminate the Threads sidebar root entirely; replace with a search affordance within Command Home. Either way, **resolve before Phase 3 begins.**

**Gates:** Phase 3 (Command Home implementation).

---

### Q3 — Act Now band collapsing behavior for V1 single-machine user (before Phase 3)
The three-band Command Home (Act Now / Continue / Machines) is designed for a populated fleet. For the V1 modal user — one machine, daemon healthy, zero pending approvals, no active runs — the home shows three mostly-empty sections.

**Proposed behavior:** Collapse the Act Now band into a full-width empty-state banner ("All clear") when nothing is pending; the banner disappears when the queue is empty, leaving only Continue and Machines visible. The three-band layout expands as the fleet grows.

Document this collapsing rule explicitly before Phase 3; without it, the implementation agent will render three empty sections.

**Gates:** Phase 3 (Command Home).

---

### Q4 — Run-thread structural chrome: render governance frame before agent output (before Phase 3)
Reviewer B finding: inside a run thread, the differentiation from Claude depends entirely on agent data (diffs, evidence cards, work timeline states). A first-week user with one run and no output sees what looks like a governed chat window.

**Required:** The governance frame must render as structural chrome from the first message — the chip row (agent/machine/repo/policy/budget/model) and the stage label (`Queued → Planning → Editing → Testing → Waiting → Summarizing`) must be visible even when empty. The frame carries the governance identity before content fills it.

Also: rename "New Chat / Start work" (any nav label with "Chat" in it) to "Start work" only — the word "Chat" in a sidebar root is a naming failure that reintroduces the clone association.

**Gates:** Phase 3 (Run thread).

---

### Q5 — Onboarding cliff edge: pairing as re-engagement, not a wall (before Phase 4)
Reviewer B finding: the install-bridge step requires the user to leave the phone, open a terminal on their desktop, run a curl command, and return. Users who install Lancer away from their machine will hit this wall and depend on re-engagement to complete pairing.

**Required architecture:**
- After the demo approval step, onboarding exits gracefully to Command Home.
- The setup-checklist component persists on Command Home as the pairing re-entry point: "Pair your first machine → tap to continue" (not a modal, a band in the empty state).
- Time-to-value targets: <2 min demo value (steps 1–2 only), <6 min paired value (install-already path). Steps 6–8 (policy, permissions) are post-pairing contextual prompts.

**Gates:** Phase 4 (Onboarding rebuild).

---

### Q6 — Monetization trigger hierarchy: solo dev primary path (before Phase 4)
Reviewer B finding: the free/paid split's primary conversion trigger is the 3rd paired host. But the V1 modal user is a solo developer with one machine who never hits this trigger.

**Required reorder:**
1. **Primary:** "After first value moment" — after the first successful lock-screen approval, or end of day 7 of active use → a single contextual prompt (not a paywall) naming what Pro automation would automate for them.
2. **Secondary:** "Power user week" — if ≥N approval decisions in the past 7 days, surface an automation-depth upsell (Pro = policy presets, auto-approve rules).
3. **Tertiary:** 3rd host addition (for the multi-machine minority).

Frame Pro messaging around **automation depth** ("stop approving the same safe patterns manually"), not fleet size.

**Gates:** Phase 4 (Monetization wiring).

---

### Q7 — Roadmap: minimum-viable-phase definitions and accessibility exit criteria (before Phase 2)
Reviewer B finding: the roadmap has no time bounds and no per-phase accessibility exit criterion. Phase 2 alone (approval redesign) spans biometric, Watch, diff UI, notifications, and audit records — potentially months of solo-dev work.

**Required additions to [15](15-implementation-roadmap.md):**
- Each phase gets a "minimum viable slice" — the smallest unit verifiable in a diff-vs-baseline screenshot that a user would notice.
- Phase 2: cut Watch integration to post-V1 explicitly (already post-V1 per architecture, but the phase scope includes it — remove it).
- Every phase gets an accessibility exit criterion: "Dynamic Type AX5 + VoiceOver labels pass on new/modified surfaces before the phase is closed."

**Owner:** Update doc 15 before Phase 2 begins.

---

## Citation verification (do before using as a specification source)

### Q8 — WWDC session numbers in docs 04 and 12 (Reviewer A, Findings 1–3)
The following session numbers are **unverified guesses** that could point to wrong content:
- Doc 04 item 3: "WWDC26 'Design intuitive search experiences'" — title may be wrong or session may not exist under this title.
- Doc 04 item 13: "WWDC26 'Get the most out of Device Hub'" at `/wwdc2026/260/` — session number 260 unverified.
- Doc 12: "WWDC25 Meet Liquid Glass" at `/wwdc2025/219/` and "WWDC25 New design system" at `/wwdc2025/356/` — both numbers unverified.

**Action:** Verify all numbers against `developer.apple.com/wwdc25/` and `developer.apple.com/wwdc26/` before sharing these docs as a specification source. Until verified, treat as titles only.

---

### Q9 — Dead Codex evidence URL in doc 08 (Reviewer A, Finding 4)
Doc 08 cites `https://developers.openai.com/codex/agent-approvals-security` — the domain `developers.openai.com` does not exist. This will 404. **Remove this citation.** The approval-UX reasoning in [08](08-approval-and-security-experience.md) stands without it (Apple HIG + Mobbin + Revolut/Manus patterns are the evidence base). If the original source was an OpenAI platform doc, the correct domain is `platform.openai.com`.

---

### Q10 — US App Store external-link commission rate is TBD, not 0% (Reviewer A, Findings 5–6)
Doc 11's Cloud V2 strategy notes "(currently) 0% commission" for US external-purchase links, citing a Dec 2025 MacRumors URL that is unverifiable. The underlying legal situation (Epic v. Apple + appeals) is real, but the commission rate is **litigation-dependent and actively changing**.

**Do not model Cloud V2 at 0% commission.** Build the Cloud V2 pricing to be commission-agnostic — test at both 0% and ~27% scenarios. Confirm the applicable rate from `developer.apple.com/news/` before shipping Cloud V2.

---

## Technical investigations (before phase noted)

### Q11 — `ASWebAuthenticationSession` vs `SFSafariViewController` for Stripe Checkout V2 (before V2 Cloud)
Reviewer A finding: doc 11's V2 Cloud recommendation uses `ASWebAuthenticationSession` for the Stripe Checkout redirect flow. This is wrong — `ASWebAuthenticationSession` shows a "Logging in to [domain]" sheet UI that is confusing in a payment context. Stripe's iOS SDK and Apple guidance both recommend `SFSafariViewController` (or Safari open) for redirect-based payment flows.

**Action:** When building V2 Cloud, use `SFSafariViewController` for the Stripe Checkout navigation. The external-link disclosure interstitial (leaving the App Store) is still required regardless of which API is used.

---

### Q12 — Family Sharing entitlement validation in `PurchaseManager` (before Phase 4)
Reviewer A finding: enabling Family Sharing on the Pro non-consumable requires that `Transaction.currentEntitlements` does not filter out `ownershipType == .familyShared`. If the entitlement check gates only on `ownershipType == .purchased`, family members' purchases will be rejected.

**Action:** Before Phase 4, verify `PurchaseManager.swift`'s entitlement check handles `.familyShared`. Test with sandbox family accounts. Add to the Phase 4 DoD: "Family-shared Pro purchase grants entitlement in sandbox."

---

### Q13 — Does the runtime force `.preferredColorScheme(.dark)` at scene level? (before Phase 1)
Docs 12 and 14 note that the app "currently forces dark" at scene level, which is why `simctl ui appearance` has no effect. But this behavior needs to be confirmed and a decision made:

- If the force is intentional (dark-only V1): keep it, document it, ship with the in-app toggle disabled.
- If it was a workaround: remove it and let `LancerAppearance` drive the scheme correctly.

Find the call site (search for `.preferredColorScheme(.dark)` at the `WindowGroup` or `Scene` level) and make the explicit decision before Phase 1.

---

## Monitoring points (no action now; watch as product evolves)

- **iOS 27 GM**: Re-verify `glassEffect` Reduce-Transparency fallback behavior and any Liquid Glass API changes from WWDC25 beta to shipping OS.
- **App Store Connect external-link policy**: Monitor `developer.apple.com/news/` for commission rate decisions affecting Cloud V2 economics.
- **Run-thread differentiation**: After Phase 3 ships, run a usability pass specifically on the first-week experience (one machine, zero diffs) to confirm the structural chrome carries the governance identity without agent output.
