# APNs Relay Regression Checklist — Physical Device

**Target:** Prove the full approval loop through APNs push on a real iPhone (not simulator).

## Prerequisites

- [ ] **Apple Developer Program** ($99/yr, active membership)
- [ ] **APNs auth key (.p8)** downloaded from developer.apple.com → Certificates → Keys → `+` → Apple Push Notifications service (APNs) → Download. Save as `AuthKey_<KEY_ID>.p8`.
- [ ] **Push-backend deployed** to Fly.io (or the GCP VM at `35.201.3.231`):
  ```bash
  # Deploy via: scripts/deploy-push-backend.sh
  # Or Fly:
  fly launch --name lancer-push
  fly secrets set ...
  fly deploy
  ```
- [ ] **APNs env vars set** on the push backend (see exact `fly secrets set` command below)
- [ ] **Physical iPhone** with iOS 17+ running the Lancer Release build
- [ ] **Push Notifications entitlement** enabled in the app (Xcode → Signing & Capabilities)
- [ ] **`pushBackendURL`** in the app points to the deployed backend URL (e.g. `https://conduit-push.fly.dev`)
- [ ] **Remote Login enabled** on the Mac serving as the SSH host (System Settings → General → Sharing → Remote Login: ON)
- [ ] **Host machine** running `lancerd daemon` with policy.yaml (default:ask for file write / exec)

## `fly secrets set` — complete env var list

Run this on the push-backend Fly.io app. Fill in your actual APNs key values.

```bash
fly secrets set \
  APNS_KEY_ID=ABC123DEFG \
  APNS_TEAM_ID=39HM2X8GS6 \
  APNS_KEY_PATH=/app/AuthKey_ABC123DEFG.p8 \
  APNS_BUNDLE_ID=dev.lancer.mobile \
  APPROVAL_RELAY_SECRET="$(openssl rand -hex 32)" \
  LANCER_ENV=production \
  PORT=8080 \
  CORS_ALLOW_ORIGIN='*' \
  PUBLIC_BASE_URL='https://conduit-push.fly.dev' \
  CONTROL_PLANE_PUBLIC_URL='https://conduit-push.fly.dev' \
  WEBSITE_BASE_URL='https://conduit.dev' \
  DATA_DIR=/data
```

Copy the `.p8` file onto the Fly VM:
```bash
fly ssh console
mkdir -p /app
# Paste the AuthKey_<KEY_ID>.p8 contents via `cat > /app/AuthKey_<KEY_ID>.p8`
chmod 600 /app/AuthKey_*.p8
exit
```

Also set billing/runner secrets if this is a full production deployment:
```bash
fly secrets set \
  STRIPE_SECRET_KEY=sk_live_... \
  STRIPE_WEBHOOK_SECRET=whsec_... \
  STRIPE_PRICE_MONTHLY=price_... \
  STRIPE_PRICE_ANNUAL=price_... \
  OPENROUTER_PROVISIONING_KEY=sk-or-key-... \
  OPENROUTER_SHARED_KEY=sk-or-key-... \
  OPENROUTER_BASE_URL=https://openrouter.ai/api/v1 \
  GCS_ARTIFACTS_BUCKET=lancer-artifacts-prod \
  GITHUB_WEBHOOK_SECRET=...
```

## Test Procedure

### 1. Build the app for device (Release)

```bash
xcodebuild -project Lancer.xcodeproj -scheme Lancer \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath /tmp/lancer-device-dd \
  build
```

### 2. Install on physical iPhone

- Open Xcode → Window → Devices & Simulators
- Drag the `.app` from `/tmp/lancer-device-dd/Build/Products/Release-iphoneos/` onto the device
- Or use a TestFlight internal build

### 3. Enable push notifications

- Open Settings → Notifications → Lancer
- Ensure **Allow Notifications** is ON
- Ensure **Lock Screen**, **Banner** (temporary), and **Sounds** are ON

### 4. Start a relay session

- Open Lancer on the iPhone
- Connect to the test host (e.g. your Mac via SSH)
- Verify the session header shows **Connected** (green dot)
- Background the app (press Home button) — the approval push is the test

### 5. Trigger an approval from the host

On the host machine, SSH in and run a command that hits the `default:ask` policy:

```bash
lancerd agent-hook -- PreToolUse --tool fileWrite --input '{"path":"/tmp/test-approval.txt","content":"hello"}'
```

Or if the resident daemon and Claude agent are running, just let the agent make a tool call that triggers `default:ask`.

### 6. Verify push arrives

- [ ] Push notification appears on the **Lock Screen** within ~2 seconds
- [ ] Notification title: `Approval needed · <hostname>`
- [ ] Notification body: shows the command or action description
- [ ] Check `fly logs` on the push-backend for a `pushApproval` log line

### 7. Tap Approve

- [ ] Force-press or swipe the notification to reveal **Approve / Reject** actions (category: `approval`)
- [ ] If the app shows notification actions inline on the lock screen, tap **Approve**
- [ ] If not, unlock the phone, open Lancer, find the approval in Inbox, and tap Approve

### 8. Verify agent unblocks

- [ ] The pending agent call completes within ~5 seconds of approval
- [ ] The host-side `lancerd daemon` audit log shows `decision: approve` for the approval ID
- [ ] The agent continues to the next step (or exits cleanly)

### 9. Verify audit log records the decision

On the host:
```bash
cat ~/.lancer/audit.log | grep -i approve
```

Expected: a line showing the decision (`approve` or `reject`), the approval ID, the tool, and the rule that matched.

## Fallback / troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| No push arrives | APNs key invalid or backend not deployed | `fly logs`, verify APNS_KEY_ID/APNS_TEAM_ID |
| Push arrives but no actions | Notification category mismatch | Verify APNs payload `category: "approval"` matches Notification Service Extension |
| Agent hangs past timeout | Decision never relayed back to lancerd | Check `APPROVAL_RELAY_SECRET` matches between backend and lancerd config |
| "No device token" in backend logs | App never registered for remote notifications | Check `pushBackendURL` in app; verify APNs token fetch on app launch |
| Session shows Offline | Daemon channel didn't arm | Reconnect; check SSH host has `lancerd` installed and reachable |

## Expected outcome

```
                       ┌──────────┐
   agent tool call ──► │ lancerd ├──► queue.json (pending)
                       └────┬─────┘
                            │ POST /approval
                            ▼
                     ┌──────────────┐
                     │ push-backend  │──► APNs ──► iPhone Lock Screen
                     │ (Fly.io/GCP) │
                     └──────┬───────┘
                            │ POST /approval/decision (Bearer relayToken)
                            ▼
                       ┌──────────┐
                       │ lancerd  │──► agent unblocks
                       └──────────┘
```

## Result

- **PASS**: Full loop works — push arrives, approve unblocks agent, audit logged
- **PARTIAL**: Push arrives but auto-denies from lock screen works differently than expected
- **FAIL**: Push never arrives or agent never unblocks

Fill in date, result, and notes below:

```
Date:       _______________
Result:     _______________
Notes:      _______________
```

## Refs

- Push backend: `daemon/push-backend/main.go`
- Relay security: `daemon/push-backend/relay_security.go`
- iOS relay client: `Sources/SSHTransport/E2ERelayClient.swift`
- Simulator regression: `scripts/relay-regression.sh`
