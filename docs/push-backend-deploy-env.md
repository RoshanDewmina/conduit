# Push backend deploy env (owner-run)

> **Status:** deployed and live — `https://35.201.3.231.sslip.io/health` → HTTP 200.
> Open item: confirm the APNs secrets below are set on the *running* instance (health doesn't prove it — push reads env lazily at first send), then repoint to a vanity domain before public release.

Do not commit secrets (`.p8`, API keys, webhook secrets, tokens) to git.
Use Secret Manager or deployment-time environment variables.

## Required push/APNs values

- `APPROVAL_RELAY_SECRET=<strong random value>` (required; production startup fails closed without it)
- `APNS_KEY_ID=L8LVU9X82W`
- `APNS_TEAM_ID=39HM2X8GS6`
- `APNS_BUNDLE_ID=dev.conduit.mobile`
- `APNS_KEY_PATH=/secrets/apns.p8` (runtime path in container)

Local source of the `.p8`: `~/Downloads/Personal-Docs/AuthKey_L8LVU9X82W.p8` (never commit it).

## Example Cloud Run deploy flow

```bash
cd daemon/push-backend

gcloud run deploy conduit-push --source . --region australia-southeast1 \
  --allow-unauthenticated --min-instances 1 --port 8080

# One-time secret creation (skip if already created):
printf '%s' "$APNS_KEY_ID" | gcloud secrets create APNS_KEY_ID --data-file=-
printf '%s' "$APNS_TEAM_ID" | gcloud secrets create APNS_TEAM_ID --data-file=-
printf '%s' "$APPROVAL_RELAY_SECRET" | gcloud secrets create APPROVAL_RELAY_SECRET --data-file=-
gcloud secrets create APNS_KEY --data-file "/absolute/path/AuthKey_L8LVU9X82W.p8"

# Update service with APNs secrets and runtime env.
gcloud run services update conduit-push --region australia-southeast1 \
  --set-secrets APPROVAL_RELAY_SECRET=APPROVAL_RELAY_SECRET:latest,APNS_KEY_ID=APNS_KEY_ID:latest,APNS_TEAM_ID=APNS_TEAM_ID:latest \
  --update-secrets /secrets/apns.p8=APNS_KEY:latest \
  --set-env-vars APNS_KEY_PATH=/secrets/apns.p8,APNS_BUNDLE_ID=dev.conduit.mobile
```
