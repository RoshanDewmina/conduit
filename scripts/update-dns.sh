#!/usr/bin/env bash
# Update conduit.dev DNS in GCP Cloud DNS to point to Vercel.
# Run this after authenticating: gcloud auth login
#
# Prerequisites:
#   1. A Cloud DNS managed zone for conduit.dev in GCP
#   2. The zone must be configured as the authoritative NS at your registrar
#
# Usage: ./scripts/update-dns.sh [--project PROJECT_ID]

set -euo pipefail

PROJECT="${GCLOUD_PROJECT:-gen-lang-client-0839010810}"
DOMAIN="conduit.dev"
VERCEL_IP="76.76.21.21"
VERCEL_CNAME="cname.vercel-dns.com."

# Allow override: ./scripts/update-dns.sh --project my-project
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "=== Finding Cloud DNS zone for $DOMAIN ==="
ZONE_NAME=$(gcloud dns managed-zones list \
  --project="$PROJECT" \
  --filter="dnsName:${DOMAIN}." \
  --format="value(name)" 2>/dev/null | head -1)

if [[ -z "$ZONE_NAME" ]]; then
  echo ""
  echo "No Cloud DNS managed zone found for ${DOMAIN} in project ${PROJECT}."
  echo "Create one first:"
  echo "  gcloud dns managed-zones create conduit-dev \\"
  echo "    --project=$PROJECT \\"
  echo "    --dns-name=${DOMAIN}. \\"
  echo "    --description='conduit.dev' \\"
  echo "    --visibility=public"
  echo ""
  echo "Then update your registrar's NS records to the values shown by:"
  echo "  gcloud dns managed-zones describe conduit-dev --project=$PROJECT"
  exit 1
fi

echo "Zone: $ZONE_NAME"

echo ""
echo "=== Removing existing A / CNAME records (if any) ==="
gcloud dns record-sets delete "${DOMAIN}." \
  --type=A --zone="$ZONE_NAME" --project="$PROJECT" --quiet 2>/dev/null || true
gcloud dns record-sets delete "www.${DOMAIN}." \
  --type=CNAME --zone="$ZONE_NAME" --project="$PROJECT" --quiet 2>/dev/null || true

echo ""
echo "=== Adding Vercel records ==="
gcloud dns record-sets create "${DOMAIN}." \
  --type=A \
  --ttl=60 \
  --rrdatas="$VERCEL_IP" \
  --zone="$ZONE_NAME" \
  --project="$PROJECT"

gcloud dns record-sets create "www.${DOMAIN}." \
  --type=CNAME \
  --ttl=60 \
  --rrdatas="$VERCEL_CNAME" \
  --zone="$ZONE_NAME" \
  --project="$PROJECT"

echo ""
echo "=== Current zone records ==="
gcloud dns record-sets list --zone="$ZONE_NAME" --project="$PROJECT" \
  --format="table(name,type,ttl,rrdatas)"

echo ""
echo "✅ DNS records updated."
echo "   Propagation typically takes 1–5 minutes once NS delegation is complete."
echo "   Test: dig conduit.dev +short"
echo "         curl -I https://conduit.dev/privacy"
