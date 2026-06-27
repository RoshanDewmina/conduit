#!/usr/bin/env bash
# Deploy push-backend to the GCP Compute Engine VM (35.201.3.231).
# Run from the repo root. Requires gcloud auth and SSH access to the VM.
set -euo pipefail

VM_HOST="roshansilva@35.201.3.231"
REMOTE_DIR="$HOME/.lancer/push-backend"
SERVICE_NAME="lancer-push"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$REPO_ROOT/daemon/push-backend/push-backend-linux"

echo "=== Building Linux binary ==="
(cd "$REPO_ROOT/daemon/push-backend" && \
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o push-backend-linux .)

echo "=== Copying binary to VM ==="
ssh "$VM_HOST" "mkdir -p ~/.lancer/push-backend"
scp "$BINARY" "$VM_HOST:~/.lancer/push-backend/push-backend"
ssh "$VM_HOST" "chmod +x ~/.lancer/push-backend/push-backend"

echo "=== Writing env file (if not already present) ==="
ssh "$VM_HOST" 'test -f ~/.lancer/push-backend/.env && echo "Env file already exists — skipping" || cat > ~/.lancer/push-backend/.env << '"'"'ENVEOF'"'"'
# Fill in APNS values once you have the paid developer account + .p8 key
APNS_KEY_ID=PLACEHOLDER
APNS_TEAM_ID=39HM2X8GS6
APNS_KEY_PATH=/home/roshansilva/.lancer/push-backend/AuthKey.p8
APNS_BUNDLE_ID=dev.lancer.mobile
STRIPE_SECRET_KEY=sk_test_51TUqs1GoQwzlBwchpjBykaYsoBqmSGZkqzNG8gullH3vJzPsCBjq8HG2Lam8eXU9o7WXSFawdHrqzZVuAEevkv2G00Fx4hVCW8
STRIPE_WEBHOOK_SECRET=whsec_bm7nIlGSgqFc3ZRGY06Qk8t6UOs1xtZf
STRIPE_PRICE_MONTHLY=price_1TbMv4GoQwzlBwchI0SNIYoT
STRIPE_PRICE_ANNUAL=price_1TbMv4GoQwzlBwch56tIuaOo
# HTTPS is terminated by Caddy on the VM (auto Let's Encrypt cert for the sslip.io
# host), reverse-proxying :443 -> localhost:8080. iOS App Transport Security blocks
# cleartext HTTP, so the app MUST use the https URL. Port 8080 is firewalled to
# localhost only (no public tcp:8080 rule). See docs/cloud-run-production-cutover.md.
PUBLIC_BASE_URL=https://35.201.3.231.sslip.io
# Runner callbacks read CONTROL_PLANE_PUBLIC_URL (falls back to PUBLIC_BASE_URL if
# unset). Must be reachable from the runner network — e.g. a GCP Cloud Run container.
CONTROL_PLANE_PUBLIC_URL=https://35.201.3.231.sslip.io
WEBSITE_BASE_URL=https://conduit.dev
PORT=8080
CORS_ALLOW_ORIGIN=*
# --- GCP Cloud Run execution (leave GCP_PROJECT blank to keep cloud-run disabled) ---
# Set GCP_PROJECT + GCP_CLOUD_RUN_IMAGE together to enable. The image MUST be the
# agent-runner image (build/push via scripts/build-push-runner-image.sh); the sample
# gcr.io/cloudrun/hello has no runner and the backend will refuse to launch against it.
GCP_PROJECT=
GCP_REGION=us-central1
GCP_CLOUD_RUN_IMAGE=
GOOGLE_APPLICATION_CREDENTIALS=/home/roshansilva/.lancer/push-backend/gcp-sa.json
# --- OpenRouter (agent model auth) ---
# OPENROUTER_PROVISIONING_KEY mints capped per-customer sub-keys (preferred, multi-tenant).
# If you only have an ordinary inference key, set OPENROUTER_SHARED_KEY instead — all
# runs share it (cap its spend in the OpenRouter dashboard). Free-tier keys can only
# call :free models; real Claude models need OpenRouter credits.
OPENROUTER_PROVISIONING_KEY=
OPENROUTER_SHARED_KEY=
ENVEOF'

echo "=== Installing systemd service ==="
ssh "$VM_HOST" 'sudo tee /etc/systemd/system/lancer-push.service > /dev/null << '"'"'SVCEOF'"'"'
[Unit]
Description=Lancer Push Backend
After=network.target

[Service]
Type=simple
User=roshansilva
WorkingDirectory=/home/roshansilva/.lancer/push-backend
EnvironmentFile=/home/roshansilva/.lancer/push-backend/.env
ExecStart=/home/roshansilva/.lancer/push-backend/push-backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF'

echo "=== Enabling and starting service ==="
ssh "$VM_HOST" "sudo systemctl daemon-reload && sudo systemctl enable $SERVICE_NAME && sudo systemctl restart $SERVICE_NAME && sleep 2 && sudo systemctl status $SERVICE_NAME --no-pager"

echo ""
echo "=== Health check ==="
sleep 2
curl -sf "http://35.201.3.231:8080/health" && echo " ✓ Backend healthy" || echo " ✗ Health check failed (check firewall rules or service logs)"
echo ""
echo "Push backend deployed at http://35.201.3.231:8080"
echo "Update pushBackendURL in Lancer/LancerApp.swift to this URL once APNs keys are ready."
