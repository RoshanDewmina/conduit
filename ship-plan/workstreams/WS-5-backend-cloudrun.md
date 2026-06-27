# WS-5 — Push backend → GCP Cloud Run + prod URL  (covers 17-pt #7, #8)

> Cloud target = **GCP Cloud Run** (owner-locked; supersedes the Fly.io suggestion in Part II). Owner runs the `gcloud` auth; you write/deploy + do the iOS wiring. Coordinates with WS-4 (webhook URL).

## Context
Repo `/Users/roshansilva/Documents/command-center`. Backend: `daemon/push-backend/` (Go). iOS build: `cd Packages/LancerKit && swift build`. Read `docs/SERVER.md`.

**Confirmed problems:**
- Push backend URL is **hardcoded** to `http://35.201.3.231:8080` in `Lancer/LancerApp.swift:14` — **plain HTTP** (ATS rejects this in Release) on a raw IP. Cloud Run gives auto-HTTPS + a stable URL + scale-to-zero.
- `didReceiveRemoteNotification` currently returns `.noData` (Inbox can't update in background).
- Backend reads the APNs key path via `os.Getenv("APNS_KEY_PATH")` and `main.go` already supports it.
- Cloud is split across 3 providers; `AgentKit/Provisioners/` has a complete+wired `FlyProvisioner` and dead `LightsailProvisioner`/`OrbstackProvisioner` stubs.

## Tasks
1. **Deploy to Cloud Run** (region `australia-southeast1` to match the existing VM; `--min-instances 1` so the in-memory entitlement cache survives):
   ```bash
   cd daemon/push-backend
   gcloud run deploy lancer-push --source . --region australia-southeast1 \
     --allow-unauthenticated --min-instances 1 --port 8080
   ```
   Capture the printed `https://lancer-push-…-ts.a.run.app` URL.
2. **Secret Manager** — create `APPROVAL_RELAY_SECRET` (strong random value; backend refuses production startup without it), `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_ANNUAL`, `APNS_KEY` (the `.p8` file), `APNS_KEY_ID`, `APNS_TEAM_ID`, `PUBLIC_BASE_URL`, `WEBSITE_BASE_URL`. Wire into the service and **mount the `.p8` as a volume file** at `/secrets/apns.p8` matching `APNS_KEY_PATH`:
   ```bash
   gcloud run services update lancer-push --region australia-southeast1 \
     --set-secrets APPROVAL_RELAY_SECRET=APPROVAL_RELAY_SECRET:latest,STRIPE_SECRET_KEY=STRIPE_SECRET_KEY:latest,STRIPE_WEBHOOK_SECRET=STRIPE_WEBHOOK_SECRET:latest,STRIPE_PRICE_MONTHLY=STRIPE_PRICE_MONTHLY:latest,STRIPE_PRICE_ANNUAL=STRIPE_PRICE_ANNUAL:latest,APNS_KEY_ID=APNS_KEY_ID:latest,APNS_TEAM_ID=APNS_TEAM_ID:latest,PUBLIC_BASE_URL=PUBLIC_BASE_URL:latest,WEBSITE_BASE_URL=WEBSITE_BASE_URL:latest \
     --update-secrets /secrets/apns.p8=APNS_KEY:latest \
     --set-env-vars APNS_KEY_PATH=/secrets/apns.p8,APNS_BUNDLE_ID=dev.lancer.mobile,CORS_ALLOW_ORIGIN=https://conduit.dev
   ```
3. **iOS: kill the hardcoded IP.** Move the URL to build config — add `LANCER_PUSH_BACKEND_URL` to `project.yml` `settings.base` and `Info.plist`, then in `LancerApp.swift:14` read `Bundle.main.infoDictionary?["LANCER_PUSH_BACKEND_URL"] as? String ?? ""`. No plain-HTTP fallback in Release.
4. **Improve the remote-notification handler** — return `.newData` and post a `NotificationCenter` broadcast so the Inbox updates in background; add `Notification.Name.lancerRemoteApprovalReceived` to `NotificationsKit/Notifications.swift`.
5. **Provisioner cleanup** — remove or clearly gate the dead `LightsailProvisioner`/`OrbstackProvisioner` stubs so only `.fly` is offered (full multi-cloud is post-launch).

## Constraints
- **Never commit the `.p8`, any secret, or the deployed URL's secrets.** The URL itself is fine in build config.
- Keep `fly.toml` intact (no Fly migration). Don't break the existing lancerd path.

## Acceptance
- Cloud Run service live over HTTPS; secrets in Secret Manager; `.p8` mounted + readable. · Hardcoded IP gone; URL in build config; `xcodegen generate` regenerates cleanly. · Remote-notif handler posts the broadcast + returns `.newData`. · Dead provisioner stubs removed/gated. · `swift build` green; no secrets committed.

## Report Template (fill in, return)
```
## WS-5 Report
### Cloud Run: <URL (https), region, min-instances; deploy output tail>
### Secret Manager: <secrets created; .p8 mounted at /secrets/apns.p8?>
### iOS URL: <project.yml + Info.plist + LancerApp.swift:14 change; no plain-HTTP in Release?>
### Remote-notif handler: <.newData + broadcast added?>
### Provisioner stubs: <removed/gated?>
### Secrets committed: <none — confirm> · xcodegen regenerates: <clean?>
### swift build: <green/red> · Files changed: <list> · Owner-action items: <gcloud auth etc> · Deviations/risks:
```
