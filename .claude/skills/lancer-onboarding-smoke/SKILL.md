---
name: lancer-onboarding-smoke
description: Use when running or planning a live, on-device first-run / onboarding / live-loop smoke test of Lancer — "test the whole app starting with onboarding," verifying pairing, the approval loop, and push. Encodes the ordered checklist (install + run lancerd BEFORE the pairing screen) and points at the runbook for detail.
---

# Lancer Onboarding Smoke

## Overview

The canonical **ordered** path for a live first-run test on a real device. It exists because the
2026-06-24 device test hit a real gap: the app jumped to "pair the bridge" with **no prior step**
telling the user to install and run `lancerd` on their Mac first. This skill makes step 0 explicit
so neither the tester nor the app skips it.

Detailed bring-up + proof of the governed-approval loop lives in `docs/LIVE_LOOP_RUNBOOK.md` —
this skill is the short ordered checklist on top of it, not a duplicate. Launch state:
`docs/PUBLISH_READINESS_CHECKLIST.md`.

## The ordered checklist

Run top to bottom; do not advance past a failing step.

0. **Daemon first (the easily-missed prerequisite).** Install + run `lancerd` on the Mac, with
   `APPROVAL_RELAY_SECRET` in its launchd env (see the Live-loop C2 notes). The onboarding UI must
   reach this point *before* showing the pairing screen — if the app's pairing screen has no
   preceding "install & run the bridge on your computer" step, that is a **bug to file/fix**, not
   a tester error. (`OnboardingFeature/BridgePairingView.swift`, `ProvisioningWizard.swift`.)
1. **Pair.** Phone scans the QR / enters the PIN; confirm the bridge registers and the TOFU
   host-key prompt appears (fail-closed — it must not be silently skipped).
2. **Connect.** Confirm the orb reaches `connected` and a session attaches.
3. **Dispatch.** Send a prompt from the phone; confirm tokens stream back over the transport.
4. **Approval loop.** Trigger a gated action; approve from the phone; confirm the action returns
   and completes. This is the #1 V1 gate.
5. **Push while closed.** Background/close the app, trigger an approval, confirm the push arrives
   and approving from the notification works (the C2 scenario).

## Hard rules

- **Security stays fail-closed:** the TOFU prompt and `BiometricGate` are part of the test, not
  obstacles to route around. Never log secrets or the relay key.
- **Distinguish observed vs assumed.** Mark each step PASS only if you actually saw it on the
  device; "should work" is not a pass (see `$lancer-verification-gate`).
- **A UX gap is a finding.** Missing prerequisite steps, dead-end screens, or unclear copy in the
  onboarding flow are reportable outcomes of this smoke test, not skip-and-move-on items.

## Done when

Every step is marked PASS (observed on device) or has a filed finding with the screen/file, and
you've reported which steps passed, which failed, and any onboarding-flow gaps discovered.
