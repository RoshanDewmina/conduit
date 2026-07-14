#!/bin/sh
# Fly stores the APNs .p8 as a string secret; decode it into the unprivileged
# container's temporary filesystem without printing the key.
set -eu
umask 077

if [ -n "${APNS_KEY_P8_BASE64:-}" ]; then
  mkdir -p /tmp/secrets
  printf '%s' "$APNS_KEY_P8_BASE64" | base64 -d > /tmp/secrets/apns.p8
  chmod 600 /tmp/secrets/apns.p8
  export APNS_KEY_PATH=/tmp/secrets/apns.p8
fi

unset APNS_KEY_P8_BASE64

exec ./push-backend
