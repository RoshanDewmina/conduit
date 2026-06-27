# App Store Submission Prep — Lancer

> **File:** `docs/audit/APP_STORE_SUBMISSION_PREP.md`
> **Branch:** `oc/appstore-prep`
> **Date:** 2026-06-15
> **Context:** Read `docs/audit/LAUNCH_STRATEGY_RESEARCH.md` §6.1 for rejection-risk grounding.

---

## 1. App Review Notes — Draft for App Store Connect

Paste the following verbatim into **App Store Connect → App → Review Information → App Review Notes**:

---

**What Lancer does:**
Lancer relays commands and outputs between the user's own iOS device and their own remote machine (a daemon they install on their own host). The daemon connects over SSH to a personal devbox, cloud VM, or local machine. The iOS app displays terminal output, approval requests from AI coding agents (Claude Code, Codex, opencode), and lets the user approve or deny actions.

**Why it is not "remote code execution":**
- All code execution happens on the user's own machine. The app does NOT download, interpret, or execute code on the device.
- The app is an SSH terminal client — it displays text output and sends keystrokes that the user types. This is functionally identical to Blink Shell (App Store, SSH terminal, $19.99/yr), which is an established and approved category.
- The "approval relay" sends only structured metadata (command text, file paths, risk classification) from the user's own daemon to the user's own phone, encrypted end-to-end. No binary code crosses the wire. The relay server (open-source, self-hostable) forwards only ciphertext it cannot decrypt.

**Architecture summary:**
User's phone ↔ (TLS WebSocket) ↔ open-source blind relay ↔ (WebSocket) ↔ lancerd daemon (Go, on user's host) ↔ (SSH to user's own machine). The relay never has access to plaintext data, SSH keys, or source code. End-to-end encryption uses X25519 ECDH + ChaCha20-Poly1305.

**Test account / demo:**
No login required. On first launch the app shows an onboarding screen. For reviewer/demo screenshots, use the current real-app debug seams (`LANCER_UITEST_RESEED=1`, optional `LANCER_FAKE_RELAY_HOST=1`, and `LANCER_DESTINATION=inbox|machines|settings|sessions`) rather than the deleted gallery harness. The production app requires the user to install `lancerd` on their own machine (open-source, `go install github.com/lancer-dev/lancerd@latest`) and pair via QR code.

**Precedent:**
Blink Shell (CA Tech Kids Inc., ID 1594898306) — SSH terminal app. Lancer adds AI-agent approval on top of the same SSH terminal pattern. The agent interaction is text-in/text-out over SSH, identical to a terminal session. No executable code is downloaded to the device.

**In-app purchases:**
`dev.lancer.mobile.pro` — Non-consumable $14.99 (lifetime Pro). Enables CloudKit sync, relay prioritization, and unlimited approval history. Use a sandbox account to test.

---

*If Apple requests a demo video: record the real app with the seeded DEBUG reviewer seam showing the Inbox approval flow, or use a live paired host. The deleted gallery mode must not be referenced in reviewer instructions.*

---

## 2. Guideline 2.5.2 Risk Analysis

### 2.1 The Guideline

> **2.5.2** Apps should be self-contained in their bundles, and should not read or write data outside the designated container area, nor should they download, install, or execute code, including other iOS, watchOS, macOS, or tvOS apps.

### 2.2 Lancer-specific risk assessment

| Risk surface | Status | Rationale |
|---|---|---|
| **SSH terminal** | ✅ Mitigated | SSH is an established, approved category (Blink Shell, Termius, Prompt 2). The app transmits keystrokes typed by the user and renders text output — it does not download or execute code. |
| **AI-agent approval relay** | ✅ Mitigated | The approval payload is structured JSON (command text, file paths, risk band). The app displays it and sends back a yes/no decision. No interpreted code, no bytecode, no binary payload. The user's daemon evaluates the decision and runs the command on the user's own host — not on iOS. |
| **Blind relay E2EE** | ✅ Neutral/positive | The relay server (run by the user or on Lancer's infrastructure) forwards only ciphertext. It never decrypts, inspects, or transforms payloads. This is a transport-layer detail, not an execution mechanism. |
| **Future: cloud-hosted agents** | ⚠️ **Do NOT submit this** | If Lancer ever runs agents on Lancer's own cloud servers, that triggers 2.5.2. The initial submission must be pure device-to-device relay only. Cloud agent execution is a separate product and a separate review. |
| **WebSocket relay on push-backend** | ✅ Mitigated | The push-backend relays push notifications and approval metadata. It does not inject or modify payload content. It is a transparent pipe. |

### 2.3 Concrete mitigations

1. **Remove any "run on cloud" copy from the submitted build.** The app's copy, description, and reviewer notes must all frame it as device-to-device relay. No claims about cloud-based agent execution.

2. **Strip or DEBUG-gate any feature that could be construed as downloading code.** Specifically, the SFTP/text-preview feature reads remote files over SFTP and displays their content on screen — this is file browsing, not code execution. Ensure it cannot write executables or trigger their interpretation.

3. **Review notes must explicitly state:**
   - "The app does not download, interpret, or execute any code on the iOS device itself."
   - "All AI agent execution occurs on the user's own remote machine via SSH."
   - "The relay service is an encrypted pass-through — it cannot inject commands or modify payloads."

4. **Cite Blink Shell explicitly** as a precedent for the SSH terminal pattern.

5. **Budget for 1–3 rejection cycles** (3–7 days each per [SwapTest analysis](https://swaptest.net/blog/ios-preflight-check-app-store-rejection-guide)). Each rejection requires a written explanation or a phone call with App Review. Do not panic — iterate.

### 2.4 If rejected under 2.5.2

- Appeal with a technical architecture diagram showing that the iOS device is purely a display/input surface and the daemon is on the user's own machine.
- Offer to provide a screen recording demonstrating the full flow (pair → terminal → approval → decision), showing no code is downloaded.
- If the reviewer cites "remote execution", clarify that SSH-based terminal access has been approved in dozens of apps, and the AI agent layer is text-in/text-out over the same SSH pipe.
- Escalate via the Apple Developer Contact form or request a phone call with App Review (available for paid-account developers).

---

## 3. PrivacyInfo.xcprivacy — Draft Content

This is the XML to replace or augment the existing `Lancer/PrivacyInfo.xcprivacy`. **Do not add this to the project during the audit — it is a reference draft only.**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ================================================================ -->
    <!-- REQUIRED REASON API ACCESS                                       -->
    <!-- ================================================================ -->
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <!-- UserDefaults (CA92.1): AppStorage for onboarding state,
             app lock preference, terminal font/size prefs, theme. -->
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>

        <!-- File timestamp (C617.1): SFTP file browser displays file
             modification dates to the user. -->
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>

        <!-- Disk space (not currently used — uncomment if the app ever
             shows "available disk space" in a debug/settings screen).
             Reason code DDA9.1 for displaying available capacity. -->

        <!-- System boot time (NOT included. Sentry is linked as an
             optional binary dependency but the DSN is left empty, so
             the crash reporter never starts — see LancerApp.swift.
             If a production DSN is added later, add:
             REASON 35F9.1 "Declared for crash reporter" -->
    </array>

    <!-- ================================================================ -->
    <!-- DATA COLLECTION (PRIVACY NUTRITION LABEL BACKING)                -->
    <!-- ================================================================ -->
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <!-- APNs device token — used solely for push notification
             delivery when the daemon requests an approval. -->
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeDeviceID</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
            </array>
        </dict>
    </array>

    <!-- ================================================================ -->
    <!-- TRACKING DECLARATION                                            -->
    <!-- ================================================================ -->
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
</dict>
</plist>
```

### 3.1 Reason code justifications

| API category | Reason code | Justification |
|---|---|---|
| `UserDefaults` | `CA92.1` | `@AppStorage` for user-facing preferences: onboarding completion flag, app-lock toggle, terminal font size, color scheme. No KVO observation of third-party defaults domains. |
| `FileTimestamp` | `C617.1` | SFTP file browser displays `file.modificationDate` in file listings so the user knows timestamps before transferring. |
| `SystemBootTime` | N/A (omitted) | The crash reporter SDK (Sentry) is linked but never initialized — `sentryDSN = ""` in `LancerApp.swift`. If a production DSN is configured in the future, add `35F9.1` (crash reporter). Verify against actual code before submission. |
| `DiskSpace` | N/A (omitted) | Not currently used. If a "free space" indicator is added to settings, add `DDA9.1` (display file capacity). |

### 3.2 What the current manifest declares (for reference)

The existing `Lancer/PrivacyInfo.xcprivacy` already declares `UserDefaults` (CA92.1), `FileTimestamp` (C617.1), and `DeviceID` (APNs, non-tracking, app functionality). The draft above is identical in substance. The `SystemBootTime` declaration was removed per the WS-8 audit (Sentry is disabled). **Verify one more time that no code path reads `ProcessInfo.processInfo.systemUptime` or `hostinfo(…).uptime` before submission.**

---

## 4. App Store Metadata Checklist

### 4.1 Categories

| Field | Value | Notes |
|---|---|---|
| **Primary category** | Developer Tools | Must be accurate; impacts search ranking and featured placement |
| **Secondary category** | Productivity | Optional but recommended |
| **Subtitle** (30 chars) | Approve AI agents from anywhere | Existing in `docs/app-store-metadata.md` |
| **Name** | Lancer — Agent Approvals | May need to drop subtitle suffix if Apple flags the 30-char limit on the name field itself |

### 4.2 Age Rating (4+)

| Question | Answer |
|---|---|
| Made for kids (under 17)? | No |
| Unrestricted web access? | No (SSH is not web access) |
| Gambling/contests? | No |
| Violence/cartoon/realistic? | None |
| Sexual content/nudity? | None |
| Medical/treatment information? | No |
| **Recommended rating** | **4+** |

**Rationale:** The app is a terminal emulator and approval dashboard. It displays text output from the user's own machine. No user-generated content moderation is needed because the content is the user's own terminal output. No age-restricted content is delivered or displayed by the app itself.

### 4.3 Encryption Export Compliance (ITSAppUsesNonExemptEncryption)

**Current setting in `Info.plist` and `project.yml`:**

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**Rationale for `false`:**

The app uses only encryption that qualifies for an exemption under EAR Category 5 Part 2 (ENC) — specifically:

1. **TLS/HTTPS** for all network connections to the relay server and push-backend. TLS is a standard, publicly available cryptographic protocol and qualifies for the mass-market encryption exemption (ERN).

2. **X25519 ECDH + ChaCha20-Poly1305** for end-to-end encryption of the approval relay. This is used solely for authentication of the pairing channel and confidentiality of relayed metadata. The keys are ephemeral and derived per-session. The algorithm is publicly available (RFC 7748, RFC 8439).

3. **Apple CryptoKit / CommonCrypto** for Keychain operations (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Keychain encryption is a platform feature, not an app feature — it is covered by Apple's existing exemptions.

**Conditions for exemption:**
- The app does not implement a custom cryptosystem for file encryption.
- The encryption is not a primary feature of the app — the app is a terminal/approval client.
- No encryption function is provided that could be used by third parties as a general-purpose security product.

**If Apple requests a classification:** submit a `CCATS` (commodity classification) self-assessment using the standard "mass market" questionnaire. In practice, apps using only TLS + platform crypto with `ITSAppUsesNonExemptEncryption = false` are routinely approved without CCATS review. Verify against the current [Apple export compliance docs](https://developer.apple.com/documentation/security/export-compliance-for-apps-with-encryption).

### 4.4 Privacy Nutrition Labels

As declared in the PrivacyInfo.xcprivacy draft (§3 above) — the App Store Connect privacy questionnaire must match:

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| **Device ID** (APNs token) | Yes | No | No | App Functionality |
| **Product Interaction** (analytics) | No | — | — | — |
| **Crash Data** | No | — | — | Sentry linked but never initialized |
| **Contact Info** | No | — | — | — |
| **User Content** | No | — | — | Terminal output is ephemeral and never leaves the device to our servers |
| **Search History** | No | — | — | — |
| **Purchase History** (within app) | No* | — | — | *StoreKit IAP is processed by Apple — no purchase data is collected by Lancer servers |
| **Location** | No | — | — | — |
| **Usage Data** | No | — | — | — |
| **Diagnostics** | No | — | — | — |
| **Other Data** (SSH keys, host pairings) | No | — | — | Stored only in the device Keychain, never transmitted to Lancer servers |

### 4.5 Screenshot Set

Per `docs/app-store-metadata.md` and `docs/screenshots/`:

| # | Screen | Content | Notes |
|---|---|---|---|
| 1 | Inbox / Approval cards | High-risk approval card showing command + blast radius + risk band | Hero shot — "one-tap approve from phone" |
| 2 | Decision in progress | Bottom sheet or inline action sheet with Approve / Deny / Edit / Allow-always | Demonstrate the core interaction |
| 3 | Fleet glance | Cross-vendor status dashboard showing active agents, session health | Show multi-agent support |
| 4 | Activity feed | "While you were away" timeline of autonomous decisions | Audit-trail value prop |
| 5 | Autonomy presets | Settings: Always ask / Auto-approve reads / Critical only | Policy customization |
| (6) | iPad variant | Same as above but on iPad canvas | Required for iPad-targeting apps |

- **Device:** iPhone 17 Pro (6.9" display, 1320×2868) for 6.5"/6.7"/6.9" iPhones
- **iPad:** 12.9" or 13" iPad Pro (2048×2732)
- **Style:** Light appearance (higher conversion), consistent 1px border radius
- **No text smaller than ~11pt in screenshots** per Apple HIG
- **Status bar:** Clean (hide carrier/time if displaying mock data — use the standard status bar setting in Simulator)

### 4.6 Keywords (100 characters)

Current from `docs/app-store-metadata.md`:

```
claude code,codex,opencode,ai agent,approvals,ssh,devops,audit,policy,governance,terminal,fleet
```

**Verified:** 94 characters. Fits within the 100-character limit.

### 4.7 Promotional Text & Description

Use the text from `docs/app-store-metadata.md` (§Promotional text, §Description). Ensure:

- **No claim** that the app runs agents on Lancer's servers.
- **No claim** of "lockscreen approval" unless physical-device APNs flow is verified (see `PUBLISH_READINESS_CHECKLIST.md` §C2).
- **Privacy-first language**: "Your code never leaves your host", "You own the bridge", "The relay sees only ciphertext".

---

## 5. Pre-Submission TestFlight Plan & Rejection Contingency

### 5.1 TestFlight timeline

| Phase | Action | Duration | Gate |
|---|---|---|---|
| **T0** | Archive from Xcode (Release config) + upload via Xcode Organizer or `fastlane beta` | 1 day | Requires `DEVELOPMENT_TEAM=39HM2X8GS6`, distribution provisioning profile |
| **T1** | Internal TestFlight (up to 100 invited testers via email). Test on physical device: APNs delivery, approval relay loop, background/foreground, terminal session. **Confirm the app-lock screen notification + approve action works.** | 7–14 days | Physical iPhone, push-backend deployed with APNs keys |
| **T2** | External TestFlight (up to 10,000 testers). Distribute via invite link. Gather crash logs, feedback on onboarding clarity, first-run experience. | 7+ days | Beta 1 accepted by App Review (usually 24–48h for beta review) |
| **T3** | Release build submission. Set "Manually release this version." No automatic release — control the date. | — | T1 + T2 clean |

### 5.2 TestFlight-specific review notes

Apple reviews the first TestFlight external build. Use the same App Review notes from §1. Additionally:

- Note that the app requires the user's own daemon (`lancerd`) running on their own host — testers must install it separately.
- Provide a `DEBUG`-scheme test scenario using `LANCER_UITEST_RESEED=1` and `LANCER_DESTINATION=inbox` to see seeded approval cards without a live daemon.

### 5.3 Common rejection scenarios and responses

| Scenario | Likelihood | Response |
|---|---|---|
| **Guideline 2.1 — App Completeness** (missing features, placeholder UI) | Medium | Ensure no `TODO` or placeholder screens survive in the Release build. QA every navigation path. Verify the Billing screen handles the non-consumable IAP correctly. |
| **Guideline 2.5.2 — Remote code / non-self-contained** | Medium-High | See §2 above. Cite SSH terminal precedent. Offer architecture diagram and screen recording. Pay special attention to the SFTP browser (can it download + execute a binary? NO — iOS cannot execute downloaded files outside the container, and SFTP only writes to the app sandbox). |
| **Guideline 3.1.1 — IAP confusion** | Low | The non-consumable $14.99 ("Lancer Pro — Lifetime") unlocks CloudKit sync and relay prioritization. Ensure it's clearly described. Verify that the free tier provides genuine utility (self-host relay is free forever). |
| **Guideline 4.0 — Design / copycat** | Low | Lancer's UI is original. Avoid visual similarity to Blink Shell or Termius. |
| **Guideline 5.1.1 — Privacy / data collection** | Low | Our privacy manifest declares no tracking, and the only data collected is the APNs device token for push notifications. Ensure the privacy nutrition label answers in App Store Connect match the manifest. |
| **Guideline 5.1.2 — Location / contacts** | Not applicable | The app does not request location or contacts access. |
| **Guideline 5.6 — Developer conduct / spam** | Low | Ensure the app name does not include misleading keywords. The name "Lancer — Agent Approvals" is descriptive. |

### 5.4 Rejection-cycle contingency budget

| Resource | Estimate |
|---|---|
| Rejection cycles to budget for | 1–3 |
| Days per cycle | 3–7 |
| Total worst-case delay | 21 days |
| **Buffer in launch timeline** | **3–4 weeks** between first TestFlight upload and intended public release date |

Source: [SwapTest preflight check guide](https://swaptest.net/blog/ios-preflight-check-app-store-rejection-guide) | [RevenueCat rejection guide 2026](https://www.revenuecat.com/blog/growth/the-ultimate-guide-to-app-store-rejections)

### 5.5 Escalation paths

If stuck in rejection purgatory:

1. **Respond to the rejection message** with a clear, point-by-point rebuttal citing the guideline text and explaining why Lancer complies. Include an architecture diagram (as a file attachment).

2. **Request a phone call** via the App Store Connect Contact form — paid developer accounts can request a review call.

3. **File a request for guideline clarification** at `https://developer.apple.com/contact/app-store-guidelines/`.

4. **If the rejection is about remote code execution specifically**, draft a 1-page technical whitepaper showing:
   - The iOS app's sandbox (no `JSCore`, no `WKWebView` evaluation, no `dlopen`, no `NSTask`)
   - The daemon runs on the user's own machine (diagram)
   - The relay is ciphertext-only
   - SSH terminal apps are an established App Store category

### 5.6 Pre-flight checklist (final)

Before uploading:

- [ ] `swift build && swift test` passes in `Packages/LancerKit`
- [ ] Xcode Release archive succeeds (iOS app target — not just SPM)
- [ ] No DEBUG-only features leak into Release build (seeded reviewer seams, auto-trust host key)
- [ ] All `NSPrivacy*` declarations match actual API usage
- [ ] `ITSAppUsesNonExemptEncryption = false` and the rationale is documented
- [ ] App Review notes drafted (§1 above) and pasted into App Store Connect
- [ ] IAP product `dev.lancer.mobile.pro` exists in App Store Connect (Non-Consumable, $14.99)
- [ ] APNs push notifications are functional on physical device (not just simulator)
- [ ] Privacy nutrition label in App Store Connect matches `PrivacyInfo.xcprivacy`
- [ ] Screenshots captured (5 iPhone + 1 iPad, light appearance, correct resolution)
- [ ] Age rating set to 4+
- [ ] Categories: Primary = Developer Tools, Secondary = Productivity
- [ ] Marketing / Support / Privacy URLs are live (or placeholders updated)
- [ ] Keywords fit within 100 characters
