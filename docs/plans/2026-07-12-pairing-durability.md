# Pairing durability — one-time onboarding

**Owner bar:** Pairing is one-time during onboarding. Users must **not** re-enter a
code after laptop reboot, LaunchAgent restart, `lancerd` binary replace/hot-reload,
or phone app upgrade/reinstall. New codes are required only for:

1. First onboarding
2. Explicit unpair / intentional `lancerd pair` (or `agent.pair.begin`)
3. True identity loss (Keychain wipe on phone, or operator deleted `~/.lancer/relay-pairing.json`)

## Where state lives

| Side | Location | Survives |
|------|----------|----------|
| Daemon | `~/.lancer/relay-pairing.json` (`relayURL`, `code`, X25519 keys, `confirmedAt`) | Laptop reboot, LaunchAgent restart, binary replace (file on disk) |
| Phone identity | Keychain `RelayDeviceIdentity` (`dev.lancer.relay` / `lancer.relay.device.identity.privKey`) | App upgrade **and** delete+reinstall on same device |
| Phone pairing code | UserDefaults per-machine + `….confirmed` flag | App upgrade (not a full delete of app container + Keychain) |

Backend `PairedAt` is **in-memory only** (Cloud Run). After a cold start the daemon
and phone re-register the **same** code+keys; that is not a re-pair.

## What invalidates pairing

| Event | Re-pair needed? |
|-------|-----------------|
| Laptop reboot / LaunchAgent restart | No |
| `lancerd` binary replace / resident reload | No (same `relay-pairing.json`) |
| Phone app upgrade / reinstall (same device Keychain) | No |
| Explicit `lancerd pair` / `agent.pair.begin` | **Yes** — intentional; orphans previous phones |
| REL-1 auto-remint | Only for **never-confirmed** codes (no `confirmedAt` / no `peer_joined`) |
| Tests writing localhost into live `~/.lancer/relay-pairing.json` | **Yes** — ops footgun; confirmed pairings now **refuse** silent overwrite |

## REL-1 alignment (#110)

- Auto re-mint of **dead unconfirmed** codes: unchanged (`decideExpiryAction(false) → remint`).
- Confirmed phones: `code_expired` → **re-register same code** (daemon + phone), never remint,
  never clear the phone's stored code.
- `confirmedAt` is stamped on first `peer_joined` and loaded into `everConfirmed` on daemon
  restart so a process bounce cannot “forget” confirmation and remint.

## 2026-07-12 incident (POST-110 → code 732590)

Not product “re-pair on restart.” Logs show confirmed production code **818038** was
replaced by a **localhost** test relay (`ws://127.0.0.1:54xxx`) at ~17:13, then a cascade
of test pairings, then restore/re-pair to **732590**. Root cause: live
`~/.lancer/relay-pairing.json` stomped (sim/test / explicit pair against default state dir).
Fix: refuse identity replace while `confirmedAt` is set unless `writeRelayPairingReplacing`
(explicit pair paths only).
