#!/usr/bin/env bash
# release-ios-testflight.sh — archive + export + upload Lancer to TestFlight.
# Chain proven 2026-06-23 (first upload) — cloud signing via the ASC API key;
# no local Apple Distribution cert required. Re-run safe; each run cuts a new build.
#
# Usage: scripts/release-ios-testflight.sh [output-dir]
# Requires: ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO_ROOT/build/testflight-$(date +%Y%m%d-%H%M%S)}"
ASC_KEY_ID="NRBCY4FS7Z"
ASC_ISSUER_ID="d0745161-e32f-4b43-bd2e-e899f635684c"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
TEAM_ID="39HM2X8GS6"
SCHEME="Lancer"
PROJECT="$REPO_ROOT/Lancer.xcodeproj"

[ -f "$ASC_KEY_PATH" ] || { echo "missing ASC key: $ASC_KEY_PATH" >&2; exit 1; }
mkdir -p "$OUT"

echo "== xcodegen (project must match project.yml)"
(cd "$REPO_ROOT" && xcodegen generate)

echo "== archive"
xcodebuild archive \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$OUT/Lancer.xcarchive" \
  -allowProvisioningUpdates \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "== export"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><true/>
</dict></plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "$OUT/Lancer.xcarchive" \
  -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -authenticationKeyPath "$ASC_KEY_PATH"

IPA="$(ls "$OUT"/export/*.ipa | head -1)"
echo "== upload: $IPA"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "== DONE. Build uploaded; it appears in App Store Connect → TestFlight after processing."
