# Live Loop Preflight — 2026-06-22

> Pre-device cheat sheet for proving Lancer's live approval loop on a physical iPhone.
> Goal: when the owner sits down with the device, everything checkable WITHOUT it is already green.
> Source: `docs/LIVE_LOOP_RUNBOOK.md` (Phases 1–6). Verified read-only from this Mac — no servers
> started, no config mutated. **15 verified-now items (13 pass / 2 flag), 11 owner-gated.**

---

## A. OWNER-GATED / DEVICE-REQUIRED (do these on the day — 11)

Needs a physical device, App Store Connect, APNs secrets on the running backend, or a human tap.

1. **Physical iPhone, signed dev build installed** (Push entitlement, `aps-environment`). Build with `Lancer.entitlements` (has `aps-environment: production`) — **NOT** `Lancer-DeviceTesting.entitlements` (see B-flag #14). [Runbook 5c]
2. **Confirm APNs secrets on the *running* backend instance** — `/health` does NOT prove this (push reads env lazily at first send). Verify `APPROVAL_RELAY_SECRET`, `APNS_KEY_ID=L8LVU9X82W`, `APNS_TEAM_ID=39HM2X8GS6`, `APNS_BUNDLE_ID=dev.lancer.mobile`, `APNS_KEY_PATH=/secrets/apns.p8` are set on whichever backend the app actually talks to. **See B-flag #15 — code points at conduit-push (Cloud Run), runbook §5a names the sslip.io box; resolve which is authoritative before trusting this.** [Runbook 5a]
3. **macOS Remote Login ON** + login pw in Keychain (`security add-generic-password -s lancer-localhost-ssh …`) — only needed for the SSH/sim harness (Phase 3), not the V1 relay path. Currently ABSENT (B #13). [Runbook 2]
4. **On-device: launch Lancer once, accept notifications** → device registers APNs token via `LancerApp` → `Notifications.registerDeviceToken`. Confirm backend received the token for this `sessionId`. [Runbook 5c.1]
5. **On-device: pair phone to relay** (Settings → Connection pairing code; host `lancerd` connects with it). [Runbook 5b]
6. **Background / fully close the app**, then trigger an `ask` from the host (`claude 'write "push" to ./p.txt'` in the gated workspace). [Runbook 5c.2–3]
7. **Lock-screen / Dynamic Island notification fires** with Approve/Reject actions; tap Approve → agent unblocks WITHOUT foregrounding the app. **This is the milestone never yet passed — treat any failure as P0.** Capture a screen recording. [Runbook 5c.4–5, CHECKPOINT 5c]
8. **Real remote host** (only localhost-sim subset proven so far). [Runbook context]
9. **Per-vendor `continue`/follow-up live** (Claude/Codex/OpenCode/Kimi) — argv exists (B #11) but live behavior unproven; CLI resume flags drift. [Runbook 4, CHECKPOINT 4]
10. **App Store Connect record + App IDs/capabilities** for `dev.lancer.mobile` (+ `.widget`, `.liveactivity`); IAP `dev.lancer.mobile.pro` $14.99; `ITSAppUsesNonExemptEncryption`. (GUI, paid Apple account.) [Runbook 6a]
11. **TestFlight upload + tester install** (archive Release, bump build number, distribute; external testers need Beta App Review). [Runbook 6c–6d, CHECKPOINT 6]

---

## B. VERIFIED-NOW (checked read-only from this Mac — 15)

### Build / daemon
1. **lancerd Go build** — PASS. `go build` OK (`/tmp/lancerd-preflight`). [Phase 1]
2. **lancerd `go test ./...`** — PASS. `ok lancer/lancerd 23.5s`, `ok lancer/lancerd/policy` (cached). [Phase 1, CHECKPOINT 1]
3. **Resident daemon up + has policy engine** — PASS. Socket `~/.lancer/lancerd.sock` present; launchd plist `dev.lancer.lancerd.plist` loaded; pid 9190 running. Resident `~/.lancer/bin/lancerd` is **byte-identical** (SHA-256 `0eede40e…`) to the fresh build and contains policy-engine symbols (17 hits). Reports `version 0.1.0-dev` — that is the Go source's version *string*, NOT the stale Swift 0.1.0 prebuilt the runbook warns about. [Phase 2, CHECKPOINT 2]
4. **APNs `.p8` key present locally** — PASS. `~/Downloads/Personal-Docs/AuthKey_L8LVU9X82W.p8` exists (257 bytes, not committed). [Runbook 5a]

### Relay / backend reachability
5. **Default relay (code) reachable** — PASS. `wss://conduit-push-y4wpy6zeva-ts.a.run.app` `/health` → HTTP 200 (Google Frontend / Cloud Run). Matches `RelaySettings.defaultURLString` AND daemon `relay_install_helper.go:defaultRelayURL`. [Phase 5]
6. **Runbook's sslip.io relay reachable** — PASS (but see flag #15). `https://35.201.3.231.sslip.io/health` → HTTP 200 (Caddy). **Different deployment** from the code's relay. [Runbook 5a]
7. **iOS push backend URL wired** — PASS. `project.yml:26` `LANCER_PUSH_BACKEND_URL=https://conduit-push-y4wpy6zeva-ts.a.run.app`; resolved at runtime by `AppRoot.pushBackendURL()` (DEBUG env override → Info.plist). Non-blank → ships a build that can reach push. [Runbook 6b]

### Config / signing
8. **Xcode project + scheme exist** — PASS. `Lancer.xcodeproj` present; scheme `Lancer.xcscheme` (+ `LancerMac.xcscheme`). [Phase 1]
9. **aps-environment = production** — PASS. `Lancer.entitlements` has `aps-environment: production`; app target wires `Lancer/Lancer.entitlements` (`project.yml:104`). Matches `APNS_BUNDLE_ID=dev.lancer.mobile` → production APNs. [Runbook 6b]
10. **Bundle id / team / signing** — PASS. `PRODUCT_BUNDLE_IDENTIFIER=dev.lancer.mobile`, `DEVELOPMENT_TEAM=39HM2X8GS6`, `CODE_SIGN_STYLE=Automatic`, `MARKETING_VERSION=1.0.0`, `CURRENT_PROJECT_VERSION=1`. [Runbook 6]

### Code paths (handlers/scripts present)
11. **dispatch + per-vendor continue argv exist** — PASS. `daemon/lancerd/dispatch.go`: `continueArgv` (claude `--continue -p`, codex `exec resume`, kimi `--continue`, opencode `run --continue`); explicit shell-free argv. *Presence verified; live behavior is owner-gated A #9.* [Phase 4]
12. **Decision-relay + dispatch code paths exist** — PASS. iOS `ApprovalRelay.forwardDecisionOnly` (AppRoot.swift ×4), `performDispatch`/`continueRun` wired; `RunControl.continueRun`. `DeviceIdentity.sessionID()` used consistently at registerDeviceToken AND decision POST → sessionId parity (the MAJOR-8 fix) is in place in code. [Runbook context, Triage B]
13. **Hook + smoke + regression scripts present** — PASS. `docs/lancer-hook.sh`, `docs/codex-lancer-hook.sh`, `docs/opencode-lancer-hook.sh`; `scripts/validation/resident-bridge-smoke.sh`; `scripts/relay-regression.sh` (all executable). [Phases 2–3]

### FLAGS (verified-now, needs attention before/at device time)
14. **FLAG — DeviceTesting entitlements has NO `aps-environment`.** `Lancer-DeviceTesting.entitlements` lacks the push key (only `Lancer.entitlements` has it). A device build signed with the DeviceTesting entitlements will **not receive push**. Owner must archive/run with `Lancer.entitlements` for the Phase 5c test. The app target already points at `Lancer.entitlements` (good) — just don't swap to DeviceTesting for the push run.
15. **FLAG — relay host mismatch (runbook vs code).** Runbook §5a tells the owner to verify APNs secrets on `https://35.201.3.231.sslip.io` (a Caddy box), but the **shipping code (app + daemon) talks to `conduit-push-y4wpy6zeva-ts.a.run.app` (Cloud Run, Google Frontend)** — a different deployment. Both return 200 on `/health`, but APNs delivery happens on whichever backend the **app** registers against = conduit-push. **Action: confirm the APNs `.p8`/env (A #2) are set on the conduit-push Cloud Run service**, not the sslip.io box, or the lock-screen push will silently never fire. (Consistent with `lancer-infra-migration-checklist.md`: conduit-push is the intentional live relay pre-rebrand-cutover.)

### Not verifiable here (needs the simulator/app-target build — out of this preflight's read-only scope)
- App-target iOS build SUCCEEDED (`build_sim`) — runbook CHECKPOINT 1's second half; run before device day.
- `resident-bridge-smoke.sh` PASS + fail-closed (daemon-stopped `fileWrite` holds, exit 1) — runbook CHECKPOINT 2.
- SSH-loop / relay-regression on the booted sim (CHECKPOINT 3 / 5b).

---

## Bottom line
- **13 verified-now PASS, 2 FLAGS** (both hidden blockers for the on-device push test): DeviceTesting
  entitlements lack `aps-environment` (#14), and the runbook points APNs verification at the wrong
  relay host vs what the code actually uses (#15).
- **11 owner-gated** items remain; the gating milestone is A #7 (lock-screen Approve while app closed).
- Resolve both flags before the device session or Phase 5c will fail silently.

## RESOLUTION — 2026-06-22 (both flags + the real root cause)
- **#14 fixed:** added `aps-environment: production` to `Lancer-DeviceTesting.entitlements`, so a
  device build signed with either entitlements set now receives push (no silent-no-push footgun).
- **#15 fixed:** runbook §5a now names `conduit-push-…run.app` (Cloud Run) as the authoritative
  APNs backend, not the sslip.io box.
- **ROOT CAUSE FOUND & FIXED (this is almost certainly why A #7 never passed):** verified read-only
  on the *running* `conduit-push` Cloud Run service (`australia-southeast1`) that all 5 APNs env
  keys are set (`APNS_BUNDLE_ID`/`APNS_KEY_ID`/`APNS_TEAM_ID`/`APPROVAL_RELAY_SECRET` + the literal
  key-path env) — **but the `APNS_KEY` secret volume was declared and never
  mounted** (`volumeMounts: []` on revision `…-00007-mh8`), so the `.p8` did not exist at the
  configured key path and APNs failed silently at first send. Mounted it via
  `gcloud run services update --update-secrets` → new revision `conduit-push-00008-wkw`,
  100% traffic, `/health` 200, mount now present at `/secrets`. Rollback target if needed:
  `…-00007-mh8`.
- **Still owner-gated:** the actual on-device lock-screen Approve-while-closed run (A #7) — now
  unblocked on the backend side; needs a physical iPhone to confirm.
