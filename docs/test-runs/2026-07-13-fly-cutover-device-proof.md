# Fly relay cutover — physical-device proof

Date: 2026-07-13 (America/Toronto)  
Source PR: #116  
Merged commit: `e376b9dc`  
Built source commit: `fa93d2d2` (the reviewed PR head)  
Device: physical iPhone 17, iOS 27.0, Developer Mode enabled

## Result

The hosted relay cutover from the retired Cloud Run endpoint to
`wss://conduit-push.fly.dev` completed without re-pairing or changing the phone/daemon
pairing identity. The Fly backend, daemon endpoint migration, in-place app upgrade,
and phone/daemon relay pairing are proven. The user-driven approval return-path and
new-chat checks remain explicitly open below until they are observed live.

## Immutable-source gates

- `go test -race ./...` from `daemon/lancerd`: pass.
- `go test -race ./...` from `daemon/push-backend`: pass.
- `swift test` from `Packages/LancerKit`: pass (692 tests in the main suite, plus
  the Intents and HostService suites).
- Generic iOS Simulator app-target build: `BUILD SUCCEEDED`.
- Physical iPhone Debug build: `BUILD SUCCEEDED` in 234.771 seconds.
- `fly config validate`: pass.
- Independent sensitive-diff review: approve after pairing persistence was changed
  to cross-process locked, atomic, full-identity CAS writes and legacy confirmation
  was backfilled on both daemon and phone.
- GitHub PR #116: daemon, LancerKit, app-target, and review checks all passed.

## Backend proof

- Fly app: `conduit-push`, machine version 2, region `iad`, state `started`.
- Deployed image: `deployment-01KXF01H5EEW5YAX2HEY6J5PAF`.
- Fly machine health check: passing.
- `GET /health`: HTTP 200.
- `/ws/relay` without required parameters: HTTP 400 (route live, malformed request rejected).
- Unauthenticated `POST /register`: HTTP 401.
- Unauthenticated `POST /v1/devices/bind`: HTTP 401.

## Pairing-preserving migration proof

1. Created a fresh mode-0600 backup of the live pairing before restart under
   `~/.lancer/backups/`.
2. Built and installed the daemon from PR head `fa93d2d2`; its local SHA-256 was
   recorded outside this repository.
3. Installed the iPhone app as an **upgrade**. The app was never uninstalled and its
   container/Keychain were not reset.
4. Restarted the resident daemon. Startup changed only the exact retired hosted URL.
5. The pairing file remained mode 0600, remained confirmed, and its code/private-key/
   public-key identity fingerprint exactly matched the pre-cutover fingerprint.
6. The daemon connected to Fly, and the upgraded physical phone paired three seconds
   later with no code entry:

   ```text
   migrated hosted relay endpoint to wss://conduit-push.fly.dev; pairing identity preserved
   connected to relay as daemon
   paired with phone
   ```

7. `lancerd doctor`: 12 OK, 0 failures; relay pairing reported confirmed on Fly.

## Live interaction matrix

| Check | Status | Evidence |
|---|---|---|
| App upgrade preserves pairing | Pass | In-place install; same identity fingerprint; no code entry |
| Daemon exact-host migration | Pass | Fly URL persisted; custom/lookalike migrations covered by tests |
| Phone ↔ daemon rendezvous | Pass | Real `paired with phone` after both upgraded |
| Foreground approval delivery | Partial | Host audit recorded escalation and daemon recorded relay send; first 120-second request received no phone decision and remains pending |
| Approval decision returns to host | Open | Requires a fresh user-tapped approval; do not infer from delivery |
| New chat + follow-up | Open | Requires user-visible physical-device run |
| Force-quit/reopen continuity | Open | Requires user-visible physical-device run |
| Locked/background APNs approval | Open | Requires user-visible physical-device run |

## PR #114 follow-up gate

PR #114 remained intentionally unmerged after an independent final audit found that its
transcript-wrapper fix had green mechanical CI but no post-fix UI proof. A conflict-free
current-master integration commit (`fb688efd`, merged commit `e376b9dc` + PR #114 head)
was built successfully for the same physical iPhone and installed as an upgrade. The first
attempt failed during package extraction with ENOSPC; only this run's temporary DerivedData
was removed, and the clean retry reached `BUILD SUCCEEDED` in 295.916 seconds.

The remaining gate is visual: open the existing “Fix triple…” conversation and prove that
the raw XML wrapper/orphan “(no reply text)” bubble is absent while real assistant and tool
content remains visible. PR #114 must not merge until that screenshot/runtime observation is
captured.

## Operational notes

- The current Fly environment uses development App Attest, appropriate for this
  development-device run; production/TestFlight promotion still requires the
  production App Attest environment.
- Standard-account endpoints are fail-closed because Supabase JWT configuration is
  not present on Fly. That is separate from the paired self-hosted relay proof.
- The LaunchAgent install was checked before restart. Its approval relay secret is
  present in the mode-0600 plist, and the value was never printed or copied into this
  report.
- Never run bare `lancerd pair` during follow-up verification. Never uninstall the
  paired physical app; app deletion currently removes the code/URL in UserDefaults.
