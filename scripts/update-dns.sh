#!/bin/bash
# Update conduit.dev DNS in Route53 to point to Vercel
# Run this after configuring AWS credentials:
#   aws configure  (or export AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY)

set -e

DOMAIN="conduit.dev"
VERCEL_IP="76.76.21.21"
VERCEL_CNAME="cname.vercel-dns.com"

echo "Looking up hosted zone for $DOMAIN..."
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$DOMAIN" \
  --query "HostedZones[0].Id" \
  --output text | sed 's|/hostedzone/||')

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "None" ]; then
  echo "Error: No Route53 hosted zone found for $DOMAIN"
  exit 1
fi
echo "Zone ID: $ZONE_ID"

aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "'"$DOMAIN"'",
          "Type": "A",
          "TTL": 60,
          "ResourceRecords": [{"Value": "'"$VERCEL_IP"'"}]
        }
      },
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "www.'"$DOMAIN"'",
          "Type": "CNAME",
          "TTL": 60,
          "ResourceRecords": [{"Value": "'"$VERCEL_CNAME"'"}]
        }
      }
    ]
  }'

echo ""
echo "✅ DNS records updated. Propagation takes ~1-5 minutes."
echo "   Test: curl -I https://conduit.dev/privacy"
