# Conduit — Remaining Work Before Production

> ⚠️ **SUPERSEDED (2026-06-13).** This file is stale in two material ways:
> (1) "BLOCKER 1: free Apple team" is **wrong** — the account is the **paid** team
> `39HM2X8GS6` (a free team cannot mint the APNs `.p8` that already exists). (2) The
> "v0.1.0 conduitd on GCP" notes describe the **stale Swift** daemon; the canonical
> daemon is the Go source (policy engine + resident `daemon`). For current state use
> **`docs/PUBLISH_READINESS_CHECKLIST.md`** + **`docs/CONDUIT_PROJECT_DOSSIER.md`**
> (and `docs/ship-gate-owner-steps.md` for the owner's App-Store steps). Kept for the
> code-complete inventory below, which is still useful history.

Last updated: 2026-05-28 (rev — block-model redesign complete)

## Block-model redesign — status (block-model-redesign-research.md §7)

Phases 0–7 are now landed:

- ✅ Phase 0 — terminal-safe input field, bundled shell scripts, debug
  paywall bypass, dup keyboard-rail audit, status-bar overlap fix
- ✅ Phase 1 — failing tests for OSC 133 state machine
- ✅ Phase 2 — OSC 133 A/B/C/D wiring in `PTYBridge`
- ✅ Phase 3 — `BlockState` enum + lifecycle owned by OSC 133 markers
- ✅ Phase 4 — `sendKeystrokes`, `LivePromptInputView`, direct PTY input
- ✅ Phase 5 — Mode toggle retired. **Both** inline TUIs (Claude/Codex)
  **and** alt-screen TUIs (htop/vim/tmux) now render via an embedded
  SwiftTerm `TerminalView` inside the active block. No more full-screen
  `isRaw` swap — one path serves all live programs.
- ✅ Phase 6 — `tmux ls` detection on connect + attach sheet UI
- ✅ Phase 7 — OSC 133 missing-marker fallback, byte-pattern interactive-
  CLI hint, os.signpost telemetry, full `conduitGlassChrome` adoption,
  Warp-style dark theme cascaded at AppRoot


## What's confirmed done (code complete, tested)

### Core SSH
- SSH connect (password + Ed25519) ✅
- TOFU host-key confirmation sheet ✅
- Block-mode terminal (command + output as units) ✅
- Raw PTY mode via SwiftTerm (vim, htop, tmux) ✅
- Auto mode-switch (block ↔ PTY) ✅
- Keyboard accessory rail (Ctrl-C/D/Z, Ctrl latch, arrows, presets) ✅
- tmux auto-attach on connect ✅
- Auto-reconnect on network change ✅
- ANSI SGR parser (colors, bold, italic) ✅
- Ed25519 key generation + Keychain ✅
- GRDB persistence (hosts, blocks, snippets) ✅

### AI + Agent
- Risk scorer (low/medium/high/critical) ✅
- AI clients (Anthropic, OpenAI) ✅
- NL→command synthesis (`#` prefix wired to `SessionViewModel.translateAndInsert`) ✅
- "Explain block" AI action (streaming, wired in `SessionView`) ✅
- Biometric gate at app launch (LaunchLockView + BiometricGate.shared) ✅
- DaemonChannel (conduitd JSON-RPC over SSH) wired ✅
- ApprovalIngest (ingest daemon events into ApprovalRepository) wired ✅
- LiveInboxViewModel with real Allow/Reject → conduitd response ✅
- Codex hook: `docs/codex-conduit-hook.sh` + `docs/codex-hooks.json` ✅
- conduitd `agent-hook` command with risk mapping, patch support, auto-approve fallback ✅

### Watch app
- Multi-tab Watch app (Inbox, Activity, Session, Snippets) ✅
- WatchConnector phone↔watch communication ✅
- WatchApprovalTransfer (approval sync to Watch) ✅
- ConduitWatchWidget (inbox count widget) ✅
- App group entitlement (`group.dev.conduit.mobile`) ✅

### Session surfaces
- SFTP file browser (SFTPFilesView / SFTPFilesViewModel / SFTPClient) ✅
- Preview (SmartPreviewView + WKWebView + SSHProxyURLSchemeHandler) ✅
- Port auto-detection (PortDetector wired in PreviewViewModel) ✅
- Diff review (DiffView + UnifiedDiffParser) ✅
- Session Inbox (per-session approval filter) ✅

### Payment + App Store prep
- StoreKit 2 one-time purchase (PurchaseManager + BillingView) ✅
- External link to conduit.dev/subscribe (Stripe) — US storefront only (BillingEligibility) ✅
- Privacy manifest (Conduit/PrivacyInfo.xcprivacy) ✅ — declares optional APNs device identifier, no tracking
- App Store metadata (fastlane/metadata/en-US/) ✅
- Screenshots (docs/screenshots/, 6 images at 1320×2868) ✅
- Fastlane automation (fastlane/Fastfile) ✅
- APNs entitlement updated to `production` ✅
- `conduit://` URL scheme registered in Info.plist + project.yml ✅
- Stripe billing backend: checkout, portal, subscription-status, webhook, return endpoints ✅
- `daemon/push-backend/.env.example` documenting all required env vars ✅

### Quality
- 106/106 SwiftPM tests passing in 24 suites (verified 2026-05-28 via `swift test` on `Packages/ConduitKit`) ✅
- 116/116 iOS simulator tests passing on iPhone 17 Pro (verified 2026-05-28 via XcodeBuildMCP `test_sim`, scheme `ConduitKitTests`) ✅
- Zero Swift 6 concurrency warnings ✅
- BUILD SUCCEEDED (full scheme: iOS + watchOS + widget, simulator iOS 26.4.1) ✅
- App launches on iPhone 17 Pro simulator ✅
- Dark mode: no crashes ✅
- `conduit://billing/complete` deep link fires URL handler ✅
- conduitd v0.1.0 installed on GCP (35.201.3.231), hook wired ✅
- conduitd auto-approve fallback verified (exits 0 when socket absent) ✅
- conduit.dev website deployed to Vercel ✅

---

## BLOCKER 1: Paid Apple Developer Program ($99/year)

The current Apple Developer account (`dewminaimalsha2003@gmail.com`, team `39HM2X8GS6`) is a **free personal team**. Free accounts cannot:
- Use CloudKit or Push Notifications entitlements
- Submit to the App Store
- Use TestFlight

**To fix:** Enroll at developer.apple.com/enroll  
**OR:** If you have a paid account under a different Apple ID (e.g. sidewhinder2k3@gmail.com):
1. Open Xcode → Settings → Accounts → + → sign in with paid Apple ID
2. Update `DEVELOPMENT_TEAM` in `project.yml` with the new team ID
3. Run `xcodegen generate`

---

## BLOCKER 2: DNS for conduit.dev (2 min)

The website is deployed on Vercel. conduit.dev needs one DNS record to go live.

**In AWS Route53 → conduit.dev hosted zone:**
- Type: **A** | Name: `conduit.dev` | Value: `76.76.21.21` | TTL: 60
- Type: **CNAME** | Name: `www` | Value: `cname.vercel-dns.com` | TTL: 60

Script ready: `scripts/update-dns.sh` (run `aws configure` first, then `./scripts/update-dns.sh`)

Once set, https://conduit.dev/privacy and /subscribe will be live (Apple checks these during review).

---

## BLOCKER 3: App Store Connect setup (30 min, requires paid account)

After enrolling in the paid program:
- [ ] Create app: Bundle ID `dev.conduit.mobile`
- [ ] Add IAP: `dev.conduit.mobile.pro` | Non-Consumable | $14.99 | "Conduit Pro"
- [ ] Enable CloudKit container: `iCloud.dev.conduit.mobile`
- [ ] Enable Push Notifications capability
- [ ] Fill Privacy Nutrition Label → no tracking; declare optional device identifier for APNs approval alerts and subscription data if Stripe billing is enabled
- [ ] Age rating → 4+
- [ ] Upload screenshots from `docs/screenshots/`
- [ ] App description is in `fastlane/metadata/en-US/description.txt`

---

## BLOCKER 4: TestFlight + release (20 min, requires paid account)

```bash
# Set env vars
export APPLE_ID="sidewhinder2k3@gmail.com"
export APP_STORE_CONNECT_TEAM_ID="<your paid team ID>"

# Upload to TestFlight
fastlane beta

# Or upload to App Store (after TestFlight testing)
fastlane release
```

Alternatively via Xcode:
1. Product → Archive (scheme: Conduit, destination: Any iOS Device)
2. Xcode Organizer → Distribute App → App Store Connect → Upload

---

## Non-blocking (do after TestFlight)

### Live Block I/O validation

The M12 core implementation is in progress, but before calling it production
ready, validate against a real SSH host and real shells:

- [ ] `claude --version` stays as `--` and runs one-shot on iOS.
- [ ] `claude` / `codex` inline TUI accepts repeated messages without
      creating garbled follow-up blocks.
- [ ] Ctrl-C exits the foreground inline TUI and returns to a fresh prompt.
- [ ] `htop`, `top`, `vim`, and `tmux` exercise the alt-screen path.
- [ ] tmux attach/resume works after disconnect/reconnect.
- [ ] bash, zsh, and fish bundled shell-integration scripts emit OSC 133
      A/C/D plus OSC 7 on real shells.

### Codex approval loop: interactive hook trust (requires iPhone connected)

The mechanical setup is complete (hook installed on server, auto-approve fallback verified).
The interactive trust step must be done manually:

1. SSH to `35.201.3.231`
2. Run `codex`, then `/hooks` → trust `~/.codex/hooks/conduit-hook.sh`
3. Open Conduit iOS → connect to `35.201.3.231` → stay on Inbox tab
4. Give Codex a file-write task: `create /tmp/conduit-test.txt with "hello"`
5. **Reject once** → verify `/tmp/conduit-test.txt` not created
6. **Allow once** → verify `/tmp/conduit-test.txt` contains `"hello"`
7. Check `~/.conduit/codex-hook-events.jsonl` for the two event records

See `docs/SERVER.md` for full instructions.

### Stripe billing backend

1. Create recurring Stripe Prices for monthly and annual Conduit Pro.
2. Configure `daemon/push-backend` using `daemon/push-backend/.env.example` as a guide.
3. Point `docs/website/subscribe.html` at the deployed billing backend or serve it from the same origin.
4. Register the Stripe webhook endpoint at `/billing/webhook` in the Stripe dashboard.
5. Redeploy: `vercel --prod` from `docs/website/`

> **Note:** `billingEntitlements` is in-memory only. Back it with Redis or a database before production (see `billing.go`).

### Push backend (30 min, requires APNs .p8 key from paid account)
1. developer.apple.com → Keys → Create → Enable APNs → Download `AuthKey_KEYID.p8`
2. Copy to `daemon/push-backend/AuthKey_KEYID.p8`
3. `cd daemon/push-backend && fly launch && fly secrets set APNS_KEY_ID=... && fly deploy`
4. Set `pushBackendURL` in `Conduit/ConduitApp.swift` to the Fly.io URL

### CloudKit sync (needs paid account for container activation)
SyncKit architecture is implemented. The container `iCloud.dev.conduit.mobile` needs to be
activated in App Store Connect → CloudKit Dashboard before it works.
