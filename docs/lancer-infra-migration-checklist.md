# Lancer rebrand — infra migration checklist

The code rebrand (Conduit → Lancer) is done. These items are **still named
`conduit` on purpose** because they are *deployed infrastructure / owned
identifiers* — renaming the code string would break the connection to infra
that is still live under the old name. Each needs a real provisioning/DNS/deploy
step, then a one-line code update to point at the new name.

| # | Preserved identifier | What it is | Migration step | Code to update after |
|---|----------------------|-----------|----------------|----------------------|
| 1 | `wss://conduit-push-y4wpy6zeva-ts.a.run.app` | **Live Cloud Run relay** (the phone↔daemon rendezvous) | Deploy push-backend to a new Cloud Run service `lancer-push-*`; keep old alive during cutover | `Packages/LancerKit/Sources/SSHTransport/RelaySettings.swift` (`defaultURLString`) + `daemon/lancerd/relay_install_helper.go` (`resolveRelayURL`) |
| 2 | `conduit-push-smoke-ufeid7srfq-uc.a.run.app` | Smoke-test relay | Redeploy as `lancer-push-smoke-*` | smoke test scripts/CI |
| 3 | `gs://conduit-dist-f1c2466d` | **GCS bucket** for tester distribution (curl\|sh installer) | Create `gs://lancer-dist-*`, copy objects, update installer | install/release scripts, `docs/` install instructions |
| 4 | `conduit-runner-06031906` | agent-runner Cloud Run job/image | Redeploy as `lancer-runner-*` | `daemon/agent-runner/` deploy config |
| 5 | `conduit-my-workspace-a1b2c3d4` | GCP project / workspace id | New project `lancer-*` (or rename) | provisioning configs |
| 6 | `conduit-push.fly.dev` | Fly.io relay (legacy/alt) | Recreate as `lancer-push.fly.dev` or retire | fly config |
| 7 | `*.conduit.dev` (`api.` `push.` `relay.` `releases.` `staging.` `www.`) + `conduit.dev` | **Owned domain + subdomains** | Acquire/point `lancer.dev` (or chosen domain), DNS, TLS, then swap | any hardcoded `*.conduit.dev` URLs in app/daemon/docs |
| 8 | `conduit.app` / `conduitd.app` | Domain(s) in release/marketing copy | Acquire `lancer.app` if desired | marketing/docs |
| 9 | APNs topic = bundle id `dev.conduit.mobile` | Push notification topic | New APNs key/cert for `dev.lancer.mobile`; update push-backend topic | push-backend APNs config |
| 10 | App Store Connect record | Existing `dev.conduit.mobile` app | New app record / bundle id `dev.lancer.mobile`; provisioning profiles, app groups, capabilities | Apple Developer portal (device builds only; sim already builds) |

## Order of operations (suggested)
1. **Domain first** (#7) — everything else can then use `*.lancer.dev`.
2. **Relay** (#1) — deploy `lancer-push-*`, point `RelaySettings.defaultURLString` + daemon `resolveRelayURL`, keep old relay running until all devices re-pair.
3. **Dist bucket** (#3) + installer, so testers pull the `lancerd` binary.
4. **APNs** (#9) + App Store record (#10) for device/TestFlight.
5. Retire the old `conduit-*` infra once nothing points at it.

## Local re-pair after the code rebrand (do this to test now)
The rename changed the daemon name, socket, launchd label, and bundle id, so the
**current install + pairing is dead**. To bring it back up under Lancer:
1. Rebuild + reinstall the daemon: `cd daemon/lancerd && go build -o ~/.lancer/bin/lancerd . ` then `lancerd install` (creates `~/.lancer/`, launchd `dev.lancer.lancerd`).
2. Stop/remove the old `dev.conduit.conduitd` launchd service and `~/.conduit`.
3. On the phone: install the new **Lancer** app build, then pair fresh (the relay URL is now fixed + read-only at the hosted relay).

> Until #1 (relay redeploy) happens, the **default relay is still the conduit-named Cloud Run host** — which is correct and intentional: the rebranded app/daemon keep talking to the existing live relay so pairing keeps working. Only flip `defaultURLString` once `lancer-push-*` is deployed and proven.
