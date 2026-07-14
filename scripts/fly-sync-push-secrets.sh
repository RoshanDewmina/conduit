#!/usr/bin/env bash
# Copy the existing push-backend secret contract to Fly without printing values.
# Requires authenticated gcloud/fly CLIs and the APNs .p8 on disk.
set -euo pipefail

PROJECT="${GCP_PROJECT:-roshan-agent-f1c2466d}"
APNS_P8="${APNS_P8_PATH:-$HOME/Downloads/Personal-Docs/AuthKey_L8LVU9X82W.p8}"
FLY_APP="${FLY_APP:-conduit-push}"
APP_ATTEST_ENV="${APP_ATTEST_ENV:-development}"
SUPABASE_JWT_ISSUER="${SUPABASE_JWT_ISSUER:-https://sfuqarvoxfupvadsvejb.supabase.co/auth/v1}"
export PATH="${HOME}/.fly/bin:${PATH}"

if ! fly auth whoami >/dev/null 2>&1; then
  echo "Not logged into Fly. Run: fly auth login" >&2
  exit 1
fi
if [[ ! -f "$APNS_P8" ]]; then
  echo "APNs .p8 not found at $APNS_P8 (set APNS_P8_PATH)" >&2
  exit 1
fi

echo "Reading GCP secrets (values not printed)..."
APPROVAL_RELAY_SECRET="$(gcloud secrets versions access latest --secret=APPROVAL_RELAY_SECRET --project="$PROJECT")"
APNS_KEY_ID="$(gcloud secrets versions access latest --secret=APNS_KEY_ID --project="$PROJECT")"
APNS_TEAM_ID="$(gcloud secrets versions access latest --secret=APNS_TEAM_ID --project="$PROJECT")"
APNS_KEY_P8_BASE64="$(base64 < "$APNS_P8" | tr -d '\n')"

echo "  APPROVAL_RELAY_SECRET len=${#APPROVAL_RELAY_SECRET}"
echo "  APNS_KEY_ID len=${#APNS_KEY_ID}"
echo "  APNS_TEAM_ID len=${#APNS_TEAM_ID}"
echo "  APNS_KEY_P8_BASE64 len=${#APNS_KEY_P8_BASE64}"
echo "  APP_ATTEST_ENV=$APP_ATTEST_ENV (use production for TestFlight/App Store)"

ARGS=(
  -a "$FLY_APP"
  APPROVAL_RELAY_SECRET="$APPROVAL_RELAY_SECRET"
  APNS_KEY_ID="$APNS_KEY_ID"
  APNS_TEAM_ID="$APNS_TEAM_ID"
  APNS_BUNDLE_ID=dev.lancer.mobile
  APNS_KEY_PATH=/tmp/secrets/apns.p8
  APNS_KEY_P8_BASE64="$APNS_KEY_P8_BASE64"
  PUBLIC_BASE_URL="https://${FLY_APP}.fly.dev"
  LANCER_ENV=production
  APP_ATTEST_TEAM_ID=39HM2X8GS6
  APP_ATTEST_BUNDLE_ID=dev.lancer.mobile
  APP_ATTEST_ENV="$APP_ATTEST_ENV"
)

if gcloud secrets describe SUPABASE_JWT_SECRET --project="$PROJECT" >/dev/null 2>&1; then
  SUPABASE_JWT_SECRET="$(gcloud secrets versions access latest --secret=SUPABASE_JWT_SECRET --project="$PROJECT")"
  echo "  SUPABASE_JWT_SECRET len=${#SUPABASE_JWT_SECRET}"
  ARGS+=(
    SUPABASE_JWT_SECRET="$SUPABASE_JWT_SECRET"
    SUPABASE_JWT_ISSUER="$SUPABASE_JWT_ISSUER"
  )
else
  echo "  SUPABASE_JWT_SECRET: not in GCP (standard-account endpoints remain unavailable)"
fi

fly secrets set "${ARGS[@]}"
echo "Done. Redeploy if the image/config changed: (cd daemon/push-backend && fly deploy --ha=false)"
