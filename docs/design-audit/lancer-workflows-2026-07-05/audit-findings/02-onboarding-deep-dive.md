# Onboarding / Pair Machine — Deep-Dive Findings (findings + proposed changes, not yet rebuilt)

Building on the existing artifact (which already fixed 2 issues in code and flagged the notification-denied gap). This pass focuses on sequence, friction, and fresh citations — not re-litigating what's already settled.

## 1. What's working — keep it

- **Pairing-before-account-before-policy** is the right relative order and shouldn't be touched. GitHub's own iOS app confirms the developer-tool pattern: its entire first screen is logo + "Sign in" + ToS link — nothing else. Lancer's single merged product-proof-and-pair screen is *already* leaner than that once you count Lancer needs to explain what it does (GitHub needs no explanation).
- **Code-only pairing as primary path, QR deferred** — still correct. Coupang Play and GitHub's device-verification screen (below) both confirm code-first with camera/scan as a secondary affordance, not primary.
- **Inline field-adjacent errors, typed-digits-preserved** — correct, keep.
- **Notification pre-prompt with a Settings-deep-link denied-recovery** — the mechanism is right. GitHub Mobile shows real dev-tool audiences tolerate almost zero ceremony, so keep this pre-prompt lean (one line + two buttons), not a marketing screen.

## 2. Proposed changes, with reasoning

**A. Swap the primary Mobbin citations for panels A/B — GitHub's own device-verification flow, not consumer hardware.**
Fresh search surfaced [GitHub device verification](https://mobbin.com/screens/d16fca7b-018c-41a5-83e3-80e63ae2d896) ([variant](https://mobbin.com/screens/d522b478-85f1-4a95-849a-a1f8dc8c48b5)): a 6-digit monospaced field, "We just sent your code to X… code expires at 7:31PM," resend link, and a nudge toward stronger auth going forward. This is structurally identical to what panels A/B already do, and it's a *software developer-tool device-link*, not a VR headset or game console. Meta Quest/Xbox/Fitbit should be demoted to secondary references (they still validate "keep the code visible during retry") and GitHub's screen should be the lead citation. This directly answers the brief's suspicion that consumer-hardware pairing was a weaker analogy — it was.

**B. Account choice should not be a mandatory full-screen gate in onboarding at all — defer it.**
Self-hosted/offline is a fully working mode with zero account. Forcing a decision screen between "pairing succeeded" and "you can use the app" adds friction for exactly the persona most likely to bail after one bad screen: a developer evaluating the product. GitHub's minimal-first-screen pattern and Raycast's onboarding (`Welcome → Log in/Create Account → feature screens → Finish`, [screens here](https://mobbin.com/screens/76d2a569-05bd-4694-8d1a-7dff72ff768f)) look superficially like a counter-example — Raycast asks for an account almost immediately — but Raycast's product is *architecturally* cloud-first (AI credits, sync); nothing works without an account. Lancer's local/self-hosted mode is architecturally the opposite: a real, supported, zero-account path. Copying Raycast's placement here would contradict Lancer's own product design. Recommendation: default silently to local pairing, surface "Add a Lancer account" as a single low-weight, skippable option — ideally moved out of the blocking sequence entirely (last screen, or a Settings-triggered prompt the first time a second device is paired) rather than a forced choice screen.

**C. Policy defaults: keep the concept, cut the forced three-way decision.**
Apple's own WWDC26 Session 347 (agentic-risk mitigation) gives an externally-validated reason to keep *some* policy-preset step — its risk taxonomy (Destructive/Exfiltration = High, Data Manipulation/Injection = Medium) is a real analogue to Lancer's Balanced/Always-ask/Fast-lane presets, and this is a genuinely new citation the existing artifact's iOS-27 section didn't extract (it only covered panels A/B, not D). But a first-run user has no context yet for what "risky writes" or "destructive actions" mean — asking them to pick among three preset cards abstractly is friction without comprehension. Ship "Balanced" pre-selected with a one-tap "Continue with recommended" and a secondary "Customize," rather than three equally-weighted cards demanding an uninformed decision. This isn't Mobbin-sourced — it's standard progressive-disclosure practice — flagging that explicitly rather than inventing a fake citation.

**D. Notifications should move earlier, not stay last — and for a different reason than typical onboarding advice.**
ChatGPT's own notification ask ([Mobbin](https://mobbin.com/screens/6ca31203-996b-46c7-abbc-ebc8a7486035)) is contextual — it fires *after* a task completes, not during onboarding. That's the right pattern for an engagement notification (nice-to-have, safe to defer). Lancer's notification is not that: it's the delivery mechanism for the product's entire core promise ("steer agents while away from the laptop"). If the first real approval fires before the user has granted notification permission, the single most important moment in the whole app silently fails to reach them — a worse first impression than asking one screen earlier. So: don't copy ChatGPT's *timing* (post-first-use), but do keep ChatGPT's *copy pattern* (concrete example + Turn on / Maybe later) and move it to fire immediately after pairing succeeds, before account/policy — asked at the exact moment the user just proved phone-and-machine can talk to each other, which is also the most contextually obvious moment to explain "and here's how you'll know when it needs you."

**E. Genuine gap: nothing explains what "your machine" means before the terminal command.**
Current copy: *"On your machine, run `lancerd pair`."* For Lancer's actual audience (developers running CLI coding agents) this is probably fine, but it never states *why* — that Lancer connects to CLI agents (Claude Code, Codex, etc.) already running on a computer. One line above the pairing card — e.g. "Lancer connects to the coding-agent CLIs already running on your computer" — closes the brief's concern about a "scary first ask" without adding a screen. This is a copy fix, not a structural one.

**F. No new iOS 27 finding beyond what's already in the artifact for Passkeys/App-Intent-donation.**
Checked `2026-07-05-ios27-wwdc26-platform-capabilities.md` fully: it contains no section on Passkeys/`ASAuthorization` changes and no mention of App Intent donation during onboarding — both are simply outside what that research pass covered. Saying so explicitly rather than forcing a finding, per the brief. The one applicable iOS-27 item beyond what the artifact already surfaced (pairing as `IntentAuthenticationPolicy`, OCR/Barcode tools, notification coalescing) is the Session 347 risk-taxonomy point folded into (C) above.

## 3. Proposed new sequence

1. **Product proof + code** — unchanged, first. The only truly blocking screen (nothing works without a paired machine); add the one-line "connects to CLI agents already running on your computer" context per (E).
2. **Pairing error / retry** — unchanged, inline state on step 1, not a separate forward step. Re-cite primarily against [GitHub device verification](https://mobbin.com/screens/d16fca7b-018c-41a5-83e3-80e63ae2d896) per (A).
3. **Notifications pre-prompt + denied recovery** — moved up from position 5 to position 3, immediately after pairing succeeds, because it's mechanism-critical to the core loop, not an engagement nicety like ChatGPT's version — asking early avoids the worst-case "first real approval never reached me."
4. **Policy defaults** — moved from 3 to 4, reframed as a one-tap "Continue with Balanced (recommended)" default plus a secondary "Customize" affordance rather than a forced three-card decision, since the user has no comprehension context for the tiers yet.
5. **Account choice** — moved from 2 to last, and demoted from a mandatory gate to a skippable, low-weight offer (or removed from the onboarding sequence entirely in favor of a Settings-surfaced / second-device-triggered prompt) — asked last because a user who has just seen pairing work and understood how alerts function has the most reason to trust Lancer enough to consider an account relationship, and because Lancer's own architecture makes an account genuinely optional, unlike Raycast's.

**Status:** findings/proposals only — nothing rebuilt yet. Waiting on go-ahead to rebuild `01-onboarding.html` with the new sequence.

**Files referenced (no edits made):**
`docs/design-audit/workflows/01-onboarding-pairing.md`
`docs/design-audit/lancer-core-wireframes-2026-07-05/index.html` (`#onboarding`, lines 1203–1290)
`docs/design-audit/2026-07-05-ios27-wwdc26-platform-capabilities.md`
`workflow-onboarding-v2.html` (prior audit artifact, not modified)
