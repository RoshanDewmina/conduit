# 04 — Security & Privacy

Baseline is **strong and fail-closed**. Two boundary findings (one Medium, one Low) and one
supply-chain note; everything else verified safe.

## Trust boundaries traced
phone ↔ E2E relay (WebSocket, ciphertext opaque to relay) ↔ lancerd; deep links; WebKit preview
proxy; Keychain; GRDB local DB; APNs/Live Activity; pasteboard; logs; third-party SSH stack.

## Findings
- **SEC-2 (Medium, OPEN)** — cold-launch relay-token hydration race. `ApprovalRelay.swift:270-291`
  spawns hydration as a fire-and-forget `Task`; `postDecisionToBackend`'s `guard !relayToken.isEmpty`
  (`:306`) runs *before* the URLSession suspension (`:314`), so a cold-launch forward sees an empty
  token and queues instead of relaying. Not a leak or bypass — a **reliability** regression in the
  cold-launch fast path. Fix: `await` hydration. (Also TEST-01.) MASVS MSTG-AUTH-adjacent.
- **SEC-1 (Low, OPEN)** — `lancer://` deep-link handler (`LancerApp.swift:59-76`) validates scheme +
  host but not path/params. No current bypass (auth token is server-validated by Supabase); tighten
  for defense-in-depth. MASVS MSTG-PLATFORM-1.
- **SEC-3 (Note)** — `swift-nio-ssh` is a community fork (`Wellz26` @ `a05e6bbe…`, 0.3.6), not Apple
  upstream — accepted (Catalyst/cert patch) but single-maintainer dependency in the crypto path.
  Add a quarterly drift check. MASVS MSTG-CODE-1.

## Verified safe (challenged and confirmed)
- **Keychain:** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `synchronizable=false`; relay creds
  use `afterFirstUnlockThisDeviceOnly` for cold-launch; legacy UserDefaults scrubbed post-migration.
- **TOFU:** unknown/mismatched host keys throw and require explicit user trust; SHA256 fingerprints
  only stored (`TOFUHostKeyValidator.swift`). Fail-closed.
- **BiometricGate:** biometry-lockout falls back to passcode and *throws* on failure — no silent
  degrade; simulator-only graceful path.
- **Relay auth (two-tier):** shared-secret guards control-plane endpoints; per-session `relayToken`
  guards `/approval/decision`; both constant-time compared; production refuses to start without the
  secret (`relay_security.go`). Decision re-posts idempotent (first-decision-wins DB guard).
- **WebKit preview:** navigation restricted to localhost + `lancer-preview://`; external URLs
  off-ramped to Safari (`SessionWorkspaceContainer.swift:833-841`). No unrestricted JS bridge.
- **Pasteboard:** no tokens/keys/private keys written (only public keys, commands, prompts).
- **Logging:** pairing code + tokens `.private`; no public-interpolated secret found; `print` only
  in `#Preview`/`#if DEBUG`.
- **Secrets in source:** none. `project.yml` Supabase key is the public anon key (RLS-protected);
  service-role key explicitly never committed. Secret-commit guard hook present.
- **Debug seams:** all `LANCER_*` test/mock seams + `DebugSeeder` are `#if DEBUG` (one intentional
  exception: `LANCER_RELAY_URL`, BUILD-2).

## Privacy manifest & entitlements
- `PrivacyInfo.xcprivacy` present: file-timestamp (SFTP, `C617.1`), UserDefaults (`CA92.1`), APNs
  device-ID declared `tracking:false`. No tracking/analytics collection (Sentry DSN empty).
- Entitlements scoped: `aps-environment=production` (correct for TestFlight), CloudKit/iCloud/app
  group/Keychain all app-prefixed. Usage strings present for camera, Face ID, mic, speech.
- `ITSAppUsesNonExemptEncryption=false` (correct). No App Review blocker found.

## Data protection
Local GRDB DB relies on the iOS default protection class (`completeUntilFirstUserAuthentication`) —
acceptable for non-PII operational state; consider an explicit class only if sensitive transcript
content is later persisted unredacted.

## Certificate pinning
**Not recommended.** Relay is WebSocket-over-TLS to a controlled Cloud Run endpoint; the E2E payload
is already opaous to the relay, and pinning adds operational fragility (rotation) for marginal gain
against this threat model. Revisit only if the relay endpoint set stabilises long-term.
