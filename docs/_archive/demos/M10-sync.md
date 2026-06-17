# M10 — Sync + Polish Demo

## Prerequisites
- M8 complete: snippets work.
- Two devices (iPhone + iPad) with the same iCloud account.
- Conduit app signed with App Store or Development provisioning profile with iCloud entitlements.

## Steps

### 1. Verify iCloud entitlements
Settings → General → VPN & Device Management → verify iCloud container `iCloud.dev.conduit.mobile` appears in the app's entitlements.

### 2. Add host on iPhone
Open Conduit on iPhone → Workspaces → Add host "Sync Test" → Save.

**Expected within 30s:** Open Conduit on iPad → Workspaces → "Sync Test" host appears.

### 3. Add snippet on iPad
Settings → Snippets → + → name "List files", body "ls -la" → Save.

**Expected within 30s:** On iPhone Settings → Snippets → "List files" appears.

### 4. Manual sync
Settings → iCloud Sync → Sync now → spinner appears briefly → "Last synced: [time]".

### 5. Verify key material is not synced
SSH private keys from Settings → SSH Keys should NOT appear on the second device.
Each device keeps its own keys (device-local Keychain).

## Pass criteria
- [ ] `SyncEngineTests` passes on macOS (no CloudKit crash).
- [ ] `SyncStatusView` shows in Settings.
- [ ] Host added on device A appears on device B within 30s (requires real devices + iCloud).
- [ ] SSH key material stays device-local.
