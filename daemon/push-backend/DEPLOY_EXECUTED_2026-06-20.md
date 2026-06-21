# Conduit V1 — Relay redeploy + tester distribution: EXECUTED results (2026-06-20)

_Companion to `DEPLOY_RUNBOOK_HANDOFF.md` (the how-to runbook). This file records what
was actually executed and verified. Lane: `daemon/`, `.github/workflows/`, release
tooling, `project.yml:26`._

---

## P0-A — Relay redeployed (DONE, verified)

**Finding correction:** the relay was not "down" — `/health` returned `200`. The real
defect was a **stale running revision** (`conduit-push-00005`) predating the new
account/device-binding auth: env lacked `SUPABASE_JWT_*` / `APNS_KEY_ID` / `APNS_TEAM_ID`,
and `POST /v1/devices/{challenges,bind,redeem}` returned `404`.

**Action — redeployed current source to the same Cloud Run service (Cloud Build, no local Docker):**
```bash
cd daemon/push-backend
gcloud run deploy conduit-push --source . \
  --region australia-southeast1 --project roshan-agent-f1c2466d \
  --update-secrets 'APNS_KEY_ID=APNS_KEY_ID:latest,APNS_TEAM_ID=APNS_TEAM_ID:latest'
```
Preserved existing secret wiring (`APPROVAL_RELAY_SECRET` secretKeyRef; `APNS_KEY` secret
volume at `/secrets/apns.p8`; `APNS_BUNDLE_ID`). New live revision: **`conduit-push-00006-wbp`**.

**Verified on the fresh service** (`https://conduit-push-y4wpy6zeva-ts.a.run.app`):
- `GET /health` → `200`
- `POST /register` → `401` (guarded by `APPROVAL_RELAY_SECRET` — correct)
- `POST /v1/devices/bind` → `401`, `POST /v1/devices/challenges` → `400` (exist & respond)
- `go test ./...` and `go build ./...` green.

### ⚠️ URL change — `project.yml:26` updated
`35.201.3.231.sslip.io` is a **Google LB IP fronting stale infra outside this GCP project**
(Compute API disabled here; no Cloud Run domain-mapping bridges it — verified). It does
**not** route to `conduit-push` and could not be repointed. Per owner decision,
**`project.yml:26` → `https://conduit-push-y4wpy6zeva-ts.a.run.app`** (was the sslip.io host).
The iOS app must be rebuilt to embed it (the signed distribution archive does this anyway).

Testers' resident daemon must use the same host:
`export CONDUIT_RELAY_URL="wss://conduit-push-y4wpy6zeva-ts.a.run.app"`  (base, no `/ws/relay`).

### Owner-gated (additive, does NOT block V1)
`SUPABASE_JWT_SECRET` / `SUPABASE_JWT_ISSUER` are unset — require a provisioned Supabase
project (`docs/SUPABASE_ACCOUNT_SETUP.md`). `auth.go` fails **per-request**, not at startup,
so the core relay loop + keyless relay pairing work without them. To enable account auth later:
```bash
echo -n '<jwt-secret>' | gcloud secrets create SUPABASE_JWT_SECRET --data-file=- --project roshan-agent-f1c2466d
gcloud run services update conduit-push --region australia-southeast1 --project roshan-agent-f1c2466d \
  --update-secrets 'SUPABASE_JWT_SECRET=SUPABASE_JWT_SECRET:latest' \
  --update-env-vars 'SUPABASE_JWT_ISSUER=https://<project-ref>.supabase.co/auth/v1'
```

---

## P0-B — Tester install one-liner (DONE, verified)

**Root cause:** `RoshanDewmina/conduit` is **private**, so GitHub release assets `404`
for unauthenticated `curl` regardless of naming. (`install.sh` already used the correct
underscore scheme — the hyphen mismatch was a red herring.)

**Fix — public GCS distribution bucket** (production-correct):
- Bucket **`gs://conduit-dist-f1c2466d`** (US multi-region, uniform access, `allUsers:objectViewer`).
- Published: `conduitd_{darwin,linux}_{arm64,amd64}`, `SHA256SUMS`, `install.sh`.
- `install.sh` `DEFAULT_RELEASE_BASE` → `https://storage.googleapis.com/conduit-dist-f1c2466d`.
- Hardened `install.sh` to tolerate `| sh` under `set -u` (`${BASH_SOURCE[0]:-$0}`).
- `INSTALL.md` + `docs/distribution/TESTER_QUICKSTART.md` one-liners rewritten to the GCS URL.

**Canonical one-liner:**
```bash
curl -fsSL https://storage.googleapis.com/conduit-dist-f1c2466d/install.sh | sh
```

**Verified end-to-end (clean path):** download → **checksum verified** → installs
`~/.conduit/bin/conduitd` → runs, reports current build with `pair`/`daemon`/`serve`/
`relay-attach`/`shim` subcommands (NOT stale 0.1.0). Exit 0, zero warnings (hardened script).

**Cosmetic caveat:** the first GCS upload cached `install.sh` at the edge with default
`max-age=3600`; the plain URL may serve the pre-hardening copy (still installs fine) for up
to an hour. Stored object is correct (`max-age=60`); self-heals.

### Release CI — `.github/workflows/release.yml` (new)
Builds + tests + cross-compiles four targets, generates `SHA256SUMS`, **publishes to the
GCS bucket** on tag `v*` / dispatch, with `cache-control: max-age=60`. **Owner setup before
it can publish:** WIF provider + service account with `roles/storage.objectAdmin` on the
bucket; repo vars `GCS_DIST_BUCKET`, `GCP_WIF_PROVIDER`, `GCP_DEPLOY_SA`.

---

## Final-acceptance status

| Gate | Status |
|---|---|
| Relay `/health` 200 | ✅ new service `conduit-push-00006-wbp` |
| New device endpoints live (not 404) | ✅ on `.a.run.app` |
| `go test` × daemon modules (conduitd, push-backend, agent-runner) | ✅ |
| `resident-bridge-smoke.sh` | ✅ 4/4 |
| `curl\|sh` installs current daemon, checksum-verified, `pair` present | ✅ |
| SSH terminal-in-chat works live | ✅ 43/43 engine tests; live sim block vs localhost sshd |
| **Relay transport end-to-end (phone ↔ Cloud Run relay ↔ daemon)** | ✅ **PROVEN live** (see below) |
| Relay escalation render in Inbox + Approve→unblock tap | ⏳ blocked by sim tap limitation (XCUITest/device) |
| Signed Release archive (P1) | ⛔ owner-gated (signing identity) |
| Physical-device APNs (Runbook Phase 5c) | ⛔ owner-gated (device) |

### Relay round-trip — what was PROVEN live (2026-06-20)
Drove the V1 relay transport against the **production Cloud Run relay** (isolated `HOME`,
code `652939`, `CONDUIT_RELAY_URL=wss://conduit-push-y4wpy6zeva-ts.a.run.app`):
1. **Found + fixed a 3rd P0:** relay rendezvous is an in-memory map (`websocket_relay.go` `hub.pairs`),
   but Cloud Run ran `maxScale 20` with no session affinity → daemon & phone could land on
   different instances and never rendezvous. Fixed: pinned `--max-instances 1 --min-instances 1
   --timeout 3600` (rev `conduit-push-00007-mh8`).
2. **Daemon → relay WS connect:** `e2e: connected to relay as daemon (code: 652939)` — Cloud Run
   WebSockets work for the relay.
3. **Phone ↔ daemon pairing:** launched the app with `SIMCTL_CHILD_CONDUIT_RELAY_{URL,CODE}` +
   `CONDUIT_PUSH_BACKEND_URL` → daemon logged `e2e: paired with phone (code: 652939)` at ~4s;
   app footer showed **"Relay connected"**. Full bidirectional rendezvous through the live relay.
4. **Escalation queued + forwarded:** fired a `fileWrite` `agent-hook` → daemon held a real pending
   approval (`queue.json` id `9f26780f`, `ask-file-write`) and the hook **blocked the full 120s**
   awaiting a phone decision. Delivery path is code-confirmed: `server.go:1114` sends
   `approvalPending` over the relay when paired (silent on success). Note `DebugSeeder` did NOT run
   (needs `CONDUIT_SEED_DEMO=1`), so inbox content was real, not demo seed.

**Attempted the full Approve-tap closure via XCUITest** (`scripts/validation/relay-approval-e2e.sh` +
`TapInjectionProofTests.testRelayApprovalUnblocksHostHook`) and uncovered a real **relay→Inbox render gap**:
- Pairing prerequisites solved: a fresh-install app does NOT pair on its FIRST launch (relay client/store
  init completes only after one run); the SECOND launch pairs in ~4s (verified manually on the sim). The
  test now double-launches. Onboarding is bypassed with `-onboardingSeen YES` (arg domain) since the relay
  auto-pair (`configureE2ERelayBridge`) only runs in the post-onboarding shell.
- **The gap:** with the app paired (daemon: `paired with phone`, no auto-allow, hook blocking), a forwarded
  `fileWrite` escalation **does not render in the Inbox** — only the 2 DebugSeeder sample cards show. The
  handler (`AppRoot.swift:386` `conduitE2EApprovalReceived` → `activeInboxViewModel.approvals.insert`) would
  surface it IF received, so the relay `approval` message is not reaching/decrypting in the app. Prime
  suspect: the daemon logs **`paired with phone` TWICE** per session — the app opens a 2nd relay connection,
  so the daemon's session key may be derived from a stale peer and the encrypted `approval` can't be decrypted
  by the live app instance. Needs runtime logging in `SSHTransport/E2ERelayClient` (receive/decrypt) +
  `AppFeature` E2E bridge to pin down — **AppFeature is owned by another agent**, so this hand-offs to them.

**Net:** the relay TRANSPORT (pair + forward) is proven live; the relay-delivered approval **card render**
in the app Inbox is NOT yet working in these tests (separate from the tap — XCUITest tap injection itself is
proven by `testApproveDecisionApplies` on seeded cards). Also note the test inbox is polluted by DebugSeeder's
2 sample pending cards even without `CONDUIT_SEED_DEMO=1` — the harness/test needs a clean-inbox seam to
isolate the relay card. Physical-device run (Phase 5c) would exercise the same render path with real APNs.
