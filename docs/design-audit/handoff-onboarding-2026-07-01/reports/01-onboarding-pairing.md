# Workflow 01: Onboarding / Pairing

Status: **awaiting your approval** (doc-only; no SwiftUI implementation in this phase)  
Updated: 2026-06-30

## Current Screenshots

### Primary path (refreshed 2026-06-30, iPhone 17 Pro, dark)

![Value + code-only pairing](../screenshots/current/onboarding-valuepair_unified-chrome_iphone-17-pro_dark.png)

![Account choice](../screenshots/current/onboarding-account-choice_unified-chrome_iphone-17-pro_dark.png)

![Offline display name](../screenshots/current/onboarding-offline-name_unified-chrome_iphone-17-pro_dark.png)

![System notification permission (post-onboarding)](../screenshots/current/onboarding-notifications_permission-prompt_iphone-17-pro_dark.png)

### Pairing edge states — design targets (not yet captured live)

The simulator capture pass could not drive the **number pad** reliably (idb companion unavailable; `type_text` does not commit digits to `.numberPad` fields). Edge-state **behavior is verified in code** (`OnboardingPairingBlock` in `OnboardingRedesignGalleryView.swift`); **screenshots should be taken manually or via UITest** before implementation.

| State | Current UI behavior (code) | Design target (Mobbin-backed) |
| --- | --- | --- |
| Verifying / connecting | Status line: `Connecting…` then `Waiting for your desktop…` | [Wise verification](https://mobbin.com/screens/9cd832e6-b6c8-4e69-9a69-6a8ca3d6858e) — inline spinner on field; disable primary CTA |
| Invalid / mismatch | Status line: `That code didn't match — check it and try again.` | [Nike invalid code](https://mobbin.com/screens/5a8bda37-cd47-4c51-9363-9a79228f9b3e) — red field border + inline error; **do not clear input** |
| Expired code | Status line: `That code's expired — get a new one from your machine.` | [KakaoTalk expired verification](https://mobbin.com/flows/e2854335-004f-41ca-9d04-34c875b0df5b) — explain expiry + recovery CTA |
| Offline / relay unreachable | Status line: `Couldn't connect…` or `relay unreachable — retrying…` | [Meta Quest pairing recovery](https://mobbin.com/flows/4d8367cf-bc32-467e-8e88-360e96eabbc2) — keep code visible + Try again |
| Notification denied | **No in-app denied state today** — iOS sheet only | [Meta Quest notifications flow](https://mobbin.com/flows/2de8c265-7df5-46f1-b011-5f9546f483d4) — pre-prompt copy + Settings deep link after deny |

**UX gap to fix in redesign:** failures today appear as a **muted center status line** (`t.text4`), not a dedicated inline error under the code field. The chosen direction promotes errors to field-adjacent, high-contrast copy (Mobbin pattern) while keeping the typed code visible.

Historical captures (pre-unified chrome, kept for reference):

![Earlier first run intro](../screenshots/current/onboarding-first-run_intro_iphone-17-pro_dark.png)

![Earlier carousel intro](../screenshots/current/onboarding-carousel-screen1_intro_iphone-17-pro_dark.png)

## Current Structure

The merged first-run screen is the right IA: value framing and code-only pairing share one step (`valuePair` in `OnboardingRedesignView`).

Core screens today:

1. **Value + pairing** — hero, `OnboardingValueRows`, 6-digit code field, `Pair & continue`
2. **Account gate** — standard account vs self-hosted offline (`AccountEntryView`)
3. **Policy** — caution preset cards
4. **Optional SSH** — skippable add-machine prompt
5. **Post-onboarding** — system notification permission on first `onboardingSeen`

Implementation map:

- `Packages/LancerKit/Sources/OnboardingFeature/OnboardingRedesignGalleryView.swift` — `OnboardingRedesignView`, `OnboardingValueRows`, `OnboardingPairingBlock`
- `Packages/LancerKit/Sources/OnboardingFeature/OnboardingPairing.swift` — wire format, status helpers
- `Packages/LancerKit/Sources/OnboardingFeature/AccountEntryView.swift`
- `Packages/LancerKit/Sources/OnboardingFeature/BridgePairingView.swift` — settings re-pair; keep aligned with onboarding
- `Packages/LancerKit/Sources/OnboardingFeature/QRScannerView.swift` / `OnboardingScanScreen.swift` — **deferred for V1**; must not be primary path
- `Packages/LancerKit/Sources/AppFeature/AppRoot.swift` — `onboardingSeen`, notification prompt timing

## Current Issues

| Issue | Severity | Files |
| --- | --- | --- |
| `OnboardingValueRows` is abstract — user cannot see the product they are about to trust | **P0** | `OnboardingRedesignGalleryView.swift` (`OnboardingValueRows`) |
| Three equal-weight marketing rows compete with pairing | P1 | same |
| Pairing errors are easy to miss (small centered status, not field-adjacent) | P1 | `OnboardingPairingBlock` |
| `pairingMessage` state exists but is **never set** — dead error path | P2 | `OnboardingRedesignView` |
| Account gate appears **after** value+pair tap; hierarchy is OK but copy still leads with account benefits before pairing success | P2 | `AccountEntryView.swift` |
| Offline path works but "No Supabase" in hero copy is implementation detail users should not see | P2 | `AccountEntryView.swift` |
| No in-app **notification denied** recovery surface | P1 | `AppRoot.swift`, future onboarding/settings |
| QR / camera surfaces still in tree — must stay unreachable in V1 | P1 | `QRScannerView.swift`, `OnboardingScanScreen.swift` |

## Mobbin / Pattern References

| Example | What it does well | Adapt for Lancer | Do not copy |
| --- | --- | --- | --- |
| [Vibecode: Introducing Pinch to Build](https://mobbin.com/screens/f165f181-cefa-422c-ac22-1a07ba570835) | Real product screenshot makes a dev tool legible immediately | **Hero:** static Lancer product visual (Home + approval + machine) | Consumer bright styling |
| [Granola welcome](https://mobbin.com/screens/5de8fd45-4580-4191-8cbd-0008a01b8b1e) | One concrete promise + product preview | Single headline + one proof visual | Meeting-notes tone |
| [Universe first run](https://mobbin.com/screens/177cb31c-75f2-4ba2-8b5c-7be12c3d1bcf) | Product mock in device frame above setup field | Pair code beside product preview | Domain-signup framing |
| [Rivian charger setup](https://mobbin.com/screens/a04cfe19-c00a-49f2-bb1a-47d202a961bf) | Physical device photo + time estimate builds trust | "Connect this phone to your machine" with machine health preview | Consumer hardware glamour |
| [Fitbit 4-digit code](https://mobbin.com/screens/dd97453d-0ccf-4f87-9359-5ab12b00a479) | Minimal code entry tied to physical device | Keep 6-digit auto-submit; add "where to find code" help link | Wearable-specific chrome |
| [WhatsApp linking a device](https://mobbin.com/flows/dd21cacc-071a-4f4a-8813-ecf59e796ac7) | Trusted device-linking mental model | Copy: link phone ↔ machine, not "sign in" | QR-first mechanics |
| [Meta Quest pairing](https://mobbin.com/flows/4d8367cf-bc32-467e-8e88-360e96eabbc2) | Verification + invalid/unreachable recovery | Expired/offline/invalid recovery block under code field | VR illustration style |
| [Meta Quest notifications](https://mobbin.com/flows/2de8c265-7df5-46f1-b011-5f9546f483d4) | Pre-prompt education before system sheet | Explain approval alerts; post-deny Settings link | VR product shots |
| [Nike invalid code](https://mobbin.com/screens/5a8bda37-cd47-4c51-9363-9a79228f9b3e) | Red field border + inline error + resend timer | Inline invalid/expired errors; preserve typed digits | SMS-specific copy |
| [Coinbase incorrect code](https://mobbin.com/screens/e76b3784-5ea8-425a-b8ca-8e268ea30a0a) | Security framing + clear retry | High-trust pairing failure copy | Crypto branding |
| [Marcus security setup](https://mobbin.com/flows/ceb716a9-5d1a-4a8b-b7d0-bcf57c92be34) | Security as confidence, not friction | Notification + biometric rationale | Banking legal density |

### Fresh Mobbin pass (2026-06-30, MCP)

Additional flows/screens reviewed this session: [Brave Sync QR + expiry timer](https://mobbin.com/screens/53c3fdf5-a622-4484-aa67-8ed340ca85c0), [Lime code entry + flashlight utility](https://mobbin.com/screens/d87c949f-3a94-4e21-9c71-e5f96d27766c), [Depop recovery code primer](https://mobbin.com/screens/3052cd2d-a0b2-4999-a57c-1c025d509929), [Udemy resend countdown](https://mobbin.com/screens/b6b27a74-2b0a-485a-aead-06899da68925), [KakaoTalk expired verification](https://mobbin.com/flows/e2854335-004f-41ca-9d04-34c875b0df5b).

## Chosen Direction

**Scope: targeted full redesign of step 0 (value + pairing)** — not a whole-app shell change.

Replace `OnboardingValueRows` with one **static Lancer product visual** (full redesign of the hero block, not a polish pass on the three rows).

### Hero / product proof (new)

Static in-app mock showing:

- One connected machine with health label
- One pending approval with risk level
- Short read-only work-thread excerpt (not a terminal)
- Visible approve/deny pattern — **preview is not interactive**

Asset: versioned PNG in repo; update when Home/Review ship. Reduce Motion → same static image.

### Copy (locked for V1)

- **Headline:** "Steer AI coding agents from your phone."
- **Body:** "Pair this phone with your machine, review risky actions, and keep work moving without opening a laptop."
- **Pairing:** "On your machine, run `lancerd pair`" + 6-digit field + "Where do I find my code?" + recovery link for expired/invalid

### Pairing errors (redesign — new)

Promote relay failure messages from centered status line to **field-adjacent inline errors** (danger token), with:

- Code field keeps user input
- Primary button disabled while verifying
- Secondary "Try again" / "Get a new code on your machine" where applicable

### Account + notifications (targeted fixes, not full redesign)

- Account gate: keep after pairing attempt; demote account hero — pairing success or explicit skip first
- Offline name: remove "No Supabase" from user-facing copy
- Notifications: add lightweight pre-prompt before system sheet; if denied → Settings deep link + Continue (new surface)

## Proposed Screen Structure

1. **Chrome** — unified `OnboardingScaffold`; step dots; back on steps > 0
2. **Hero** — product visual in contained phone frame; legible at small Dynamic Type
3. **Promise** — headline + one body paragraph (no equal-weight rows)
4. **Pairing** — code field, inline status/errors, help + recovery links
5. **Account** (step 2) — calm choice cards; offline path respectful
6. **Policy** (step 3) — unchanged IA; visual pass only
7. **Notifications** — pre-prompt → system sheet → denied recovery if needed

## Required States

| State | Design requirement | Captured? |
| --- | --- | --- |
| Empty first run | Product visual + setup code; no generic bullet list | Yes |
| Loading pair verification | Disable primary; inline "Verifying…" / spinner on field | **No** (code-verified; capture in impl) |
| Invalid code | Inline error under field; preserve input | **No** (design target + Mobbin) |
| Expired code | Explain short TTL + get new code on machine | **No** |
| Offline phone | Network problem + Try again | **No** |
| Machine unreachable | Daemon/relay help affordance | **No** |
| Account choice | Two calm paths + returning-user link | Yes |
| Account skipped (offline name) | Respectful local name; no "broken" framing | Yes |
| Notification prompt | System sheet after onboarding | Yes |
| Notification denied | Settings action + continue | **No** (not built) |

## Designer Notes

- **Hierarchy:** product proof → pairing → account → policy
- **Spacing:** more vertical room on first run; code field + CTA within thumb reach on iPhone SE class devices
- **Typography:** one display headline, one body; monospaced only for `lancerd pair` instruction
- **Iconography:** drop decorative feature icons; icons only for help/recovery
- **Motion:** static image first; optional slow loop later with Reduce Motion fallback
- **Accessibility:** code field labeled; product preview gets accessibility summary (not OCR of tiny labels)
- **Risk:** do not communicate pairing failure by color alone — pair icon + text

## Implementation Notes (deferred — file map only)

- Add `OnboardingProductPreview` (or equivalent); remove `OnboardingValueRows`
- Wire `pairingMessage` or replace with structured `PairingUIState` enum → inline error view
- Map `OnboardingPairingBlock.pairingFailureMessage(for:)` to UI states explicitly
- Align `BridgePairingView` error presentation with onboarding
- Audit QR paths — confirm unreachable in release V1
- Snapshot / UITest captures for all Required States rows marked **No**
- Store preview asset under `DesignSystem` or `OnboardingFeature/Resources` with source note

## Approval Ask

**Do you approve this doc-only direction for Workflow 01?**

Specifically:

1. **Full redesign of step 0:** replace abstract value rows with a static Lancer product visual + locked headline/body copy above.
2. **Pairing error redesign:** field-adjacent inline errors (Mobbin pattern) instead of muted centered status text.
3. **Account/notifications:** targeted copy and denied-notification recovery (no whole-app IA change).
4. **Defer implementation** until you explicitly start a separate implementation phase.

Reply **approve** to proceed to Workflow 02 (Home), or note changes and I will revise this doc first.
