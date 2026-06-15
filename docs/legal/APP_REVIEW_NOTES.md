# App Review Notes — Conduit

**Purpose:** Paste the text below into App Store Connect → App Information →
"Notes for Review" when submitting the app. Also include reviewer demo
instructions from §2 below.

---

## 1. Notes for Review — core text

```
Conduit is an "approval firewall / audit cockpit" for AI coding agents
(Claude Code, Codex, opencode) that run on the USER'S OWN computer or
server.

The iOS app DOES NOT execute, compile, download, or install code. It
displays approval requests relayed from the user's host via SSH and sends
back binary decisions (approve / deny / edit). All code execution happens
on the user's Mac or Linux machine.

Architecture overview:

  [User's Mac/Linux host]
      ├── Runs AI agents (Claude Code, Codex, opencode)
      ├── Runs conduitd daemon → listens for approval requests
      └── SSH connection ←──── [Conduit iOS app]
                                    └── Shows transcript + approval UI
                                    └── Sends approve/deny/edit decisions

Data flow:
  1. An agent on the user's host proposes an action (e.g., edit a file,
     run a command).
  2. conduitd suspends the action and sends a notification to the phone
     (either via SSH keepalive or optional push relay).
  3. The iOS app displays the proposed action to the user.
  4. The user approves, denies, or edits; the decision goes back over SSH.
  5. conduitd on the host executes (or discards) the action.

Guideline compliance notes:
  - Guideline 2.5.2: The app does NOT download, install, or execute code
    on the iOS device. It is a remote-control/approval interface for a
    machine the user owns. This is the same model as Blink Shell
    (ID 1594898306) and other iOS SSH clients that have been on the
    App Store for years.
  - Guideline 5.1.1: The app collects only the APNs device token for
    optional push notifications. Full privacy policy at the URL in
    metadata. PrivacyInfo.xcprivacy is included.
  - Guideline 3.1.1: Conduit Pro is a one-time non-consumable IAP
    ($14.99) that unlocks multi-host management and advanced surfaces.
    No auto-renewing subscriptions are currently shipped.
  - Guideline 4.2 (Minimum Functionality): The app is fully functional
    out of the box — SSH connection, approval display, decision relay.
    No placeholder or beta content.
  - Built with Xcode 26 / iOS 26 SDK (meets April 28, 2026 requirement).
```

---

## 2. Reviewer Demo Instructions

### Prerequisites for reviewer

The reviewer needs a macOS or Linux machine with SSH enabled and the
`conduitd` daemon running. Follow the steps below to set up the demo
environment.

### Option A: Demo mode (recommended for review — no SSH required)

The app includes a built-in demo mode that shows all UI surfaces without
requiring a live SSH connection or external hardware:

1. Launch the app on the simulator or device.
2. The app will detect "no paired hosts" and offer onboarding.
3. **Skip pairing** — the app's Debug Gallery can be activated for review
   purposes:
   - Set environment variable `SIMCTL_CHILD_CONDUIT_GALLERY=review` on
     launch, OR
   - The app shows the full UI flow with mock data: session list, approval
     cards, transcript blocks, and settings.
4. Navigate: Session list → Tap a mock session → See approval UI →
   Approve / deny / edit flows → Settings for IAP display.
5. The demo mode exhibits the app's full functionality for review.

**Important for reviewer:** The debug gallery flag (`CONDUIT_GALLERY=review`)
activates pre-seeded mock data so you can evaluate every screen without a
remote host. All IAP products and restore flow are also testable in demo
mode via the StoreKit configuration.

### Option B: Live SSH connection (for thorough review)

If the reviewer has a Mac available:

1. On the Mac, ensure SSH Remote Login is enabled (System Settings →
   General → Sharing → Remote Login).
2. Install `conduitd` from the `conduitd/` directory in the project repo:
   ```
   swift build -c release
   cp .build/release/conduitd /usr/local/bin/
   ```
3. Start conduitd:
   ```
   conduitd serve
   ```
4. On the iOS device, tap "Pair with host." The app shows a QR code
   scanner. On the Mac, run:
   ```
   conduitd pair
   ```
   This displays a QR code. Scan it with the iOS app.
5. After pairing, the app connects to the host via SSH and shows a live
   session view. No commands need to be typed — conduitd will show the
   terminal prompt and the connection is visible.
6. For a full approval-flow demo, run `claude` or another agent on the
   host — the app will display pending approval requests.

### Demo account / credentials

**Not applicable.** Conduit has no user account system. Pairing is
device-to-device. If using Option B, the SSH credentials are the
reviewer's own login credentials for the Mac they set up.

### Notes for the reviewer

- **All IAP testing:** Use the StoreKit configuration file included in the
  project (Conduit/StoreKitConfig.storekit) to test the non-consumable IAP
  without real payment.
- **Camera permission** is requested only during QR-code pairing.
- **Face ID permission** is requested if the user enables "Require Face ID
  for SSH keys" in Settings.
- **Notifications permission** is requested if the user enables push alerts
  in Settings. This is optional — the app is fully functional without it.
- **No login wall.** The app works entirely without any account. No
  registration, no sign-up, no tracking consent prompt.
- The app uses the SSH protocol (via SwiftNIO + Citadel libraries). No
  custom VPN profiles, no NEVPNManager, no MDM configuration.
- All cryptographic operations (SSH keys, X25519 key agreement, ChaCha20
  encryption) use standard iOS Security framework and CryptoKit APIs.

---

## 3. Version information to include in review notes

| Field | Value |
|-------|-------|
| Build SDK | iOS 26 SDK (Xcode 26) |
| Minimum deployment target | iOS 26.0 |
| Tested on | iPhone 17 Pro (simulator and device) |
| Primary language | English |
| Copyright | {{DATE}} — [Legal entity name placeholder] |

---

## 4. Common rejection risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Guideline 2.5.2 (code execution) | App is an SSH remote-control client — code runs on user's host, not on iOS. Cite Blink Shell precedent. Demo mode shows no dynamic code loading. |
| Guideline 5.1.1 (incomplete privacy) | Privacy policy URL live + accessible in-app. Completed privacy labels. PrivacyInfo.xcprivacy included. No ATT needed (no tracking). |
| Guideline 3.1.1 (IAP rules) | One-time non-consumable IAP. No free-trial subscription. All IAP products visible in demo mode. Restore button in Settings. |
| Guideline 4.2 (minimal functionality) | Full SSH client, approval UI, session management, settings — not a placeholder. Demo mode proves completeness. |
| SDK requirement (April 28, 2026) | Built with Xcode 26 / iOS 26 SDK — compliant. |

---

## Sources

- Apple App Review Guidelines:
  <https://developer.apple.com/app-store/review/guidelines/>
- Apple SDK minimum requirements (April 28, 2026):
  <https://developer.apple.com/news/upcoming-requirements/?id=02032026a>
- Blink Shell on the App Store (SSH client precedent):
  <https://apps.apple.com/us/app/blink-shell-build-code/id1594898306>
- Apple Review Guideline 2.5.2 — Self-Contained Apps:
  <https://developer.apple.com/documentation/appstore-guidelines#2-5-Software-Requirements>
