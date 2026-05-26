#!/usr/bin/env bash
# Deploy push-backend to the GCP Compute Engine VM (35.201.3.231).
# Run from the repo root. Requires gcloud auth and SSH access to the VM.
set -euo pipefail

VM_HOST="roshansilva@35.201.3.231"
REMOTE_DIR="$HOME/.conduit/push-backend"
SERVICE_NAME="conduit-push"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$REPO_ROOT/daemon/push-backend/push-backend-linux"

echo "=== Building Linux binary ==="
(cd "$REPO_ROOT/daemon/push-backend" && \
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o push-backend-linux .)

echo "=== Copying binary to VM ==="
ssh "$VM_HOST" "mkdir -p ~/.conduit/push-backend"
scp "$BINARY" "$VM_HOST:~/.conduit/push-backend/push-backend"
ssh "$VM_HOST" "chmod +x ~/.conduit/push-backend/push-backend"

echo "=== Writing env file (if not already present) ==="
ssh "$VM_HOST" 'test -f ~/.conduit/push-backend/.env && echo "Env file already exists — skipping" || cat > ~/.conduit/push-backend/.env << '"'"'ENVEOF'"'"'
# Fill in APNS values once you have the paid developer account + .p8 key
APNS_KEY_ID=PLACEHOLDER
APNS_TEAM_ID=39HM2X8GS6
APNS_KEY_PATH=/home/roshansilva/.conduit/push-backend/AuthKey.p8
APNS_BUNDLE_ID=dev.conduit.mobile
STRIPE_SECRET_KEY=sk_test_51TUqs1GoQwzlBwchpjBykaYsoBqmSGZkqzNG8gullH3vJzPsCBjq8HG2Lam8eXU9o7WXSFawdHrqzZVuAEevkv2G00Fx4hVCW8
STRIPE_WEBHOOK_SECRET=whsec_bm7nIlGSgqFc3ZRGY06Qk8t6UOs1xtZf
STRIPE_PRICE_MONTHLY=price_1TbMv4GoQwzlBwchI0SNIYoT
STRIPE_PRICE_ANNUAL=price_1TbMv4GoQwzlBwch56tIuaOo
PUBLIC_BASE_URL=http://35.201.3.231:8080
WEBSITE_BASE_URL=https://conduit.dev
PORT=8080
CORS_ALLOW_ORIGIN=*
ENVEOF'

echo "=== Installing systemd service ==="
ssh "$VM_HOST" 'sudo tee /etc/systemd/system/conduit-push.service > /dev/null << '"'"'SVCEOF'"'"'
[Unit]
Description=Conduit Push Backend
After=network.target

[Service]
Type=simple
User=roshansilva
WorkingDirectory=/home/roshansilva/.conduit/push-backend
EnvironmentFile=/home/roshansilva/.conduit/push-backend/.env
ExecStart=/home/roshansilva/.conduit/push-backend/push-backend
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
echo "Update pushBackendURL in Conduit/ConduitApp.swift to this URL once APNs keys are ready."
