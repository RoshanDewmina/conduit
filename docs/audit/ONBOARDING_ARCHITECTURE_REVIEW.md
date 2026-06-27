# Lancer Onboarding & Connection Architecture Review

> **Research + recommendations only.** No code changed.
> Date: 2026-06-15. Branch: `opencode/phase-next`.
> Replaces/extends: `docs/audit/ONBOARDING_CONNECT_RESEARCH.md`.

## Table of contents

1. [Competitor matrix](#1-competitor-matrix)
2. [Question 1: Relay vs alternatives](#2-question-1-relay-vs-alternatives)
3. [Question 2: Handshake direction](#3-question-2-handshake-direction)
4. [Question 3: How comparable tools do it (2025–2026)](#4-question-3-how-comparable-tools-do-it-2025-2026)
5. [Question 4: Verdict for Lancer](#5-question-4-verdict-for-lancer)
6. [Prioritized recommendation (concrete, file-referenced)](#6-prioritized-recommendation)
7. [Bottom line](#7-bottom-line)

---

## 1. Competitor matrix

| Tool | Connect UX | Transport | Who hosts relay | Security | LAN/offline path |
|---|---|---|---|---|---|
| **Tailscale** | `tailscale up --auth-key <key>` or browser SSO then admin device approval | WireGuard P2P (DERP relay fallback) | User's own tailnet (or headscale) traffic P2P after coordination | Node keys + SSO + ACLs + Tailnet Lock; relay sees ciphertext | Excellent — P2P via NAT traversal |
| **VS Code Remote Tunnels** | `code tunnel` → GitHub device-code OAuth → vscode.dev URL | Microsoft Dev Tunnels relay (SSH over WebSocket) | Microsoft (free, opaque) | GitHub OAuth, AES-256-CTR SSH over relay; relay sees encrypted tunnel | None — always through Azure relay |
| **GitHub Codespaces** | Browser click → cloud VM in ~30s | Runs in cloud — not a local machine remote | GitHub/Microsoft | Browser TLS + SSH within cloud VPC | No — cloud-only |
| **Cloudflare Tunnel** | Dashboard → one-line install with embedded token | Outbound-only to Cloudflare edge (4 conns, anycast) | Cloudflare (free tier, $0+ paid) | Tunnel UUID + credential file; Zero Trust policies; edge sees plaintext unless app encrypts | No — always through Cloudflare |
| **ngrok** | `ngrok config add-authtoken <TOKEN>` → tunnel | Outbound to ngrok cloud | ngrok (free tier, paid) | Authtoken + account; edge terminates TLS | No — always through ngrok |
| **Termius** | Account login → E2E vault sync across devices | Direct SSH (no relay), cloud used only for config sync | N/A (no tunnel/proxy) | X25519 + XSalsa20-Poly1305 E2EE for vault; SOC 2; offline-first | Yes — offline-first, direct SSH |
| **Warp** | Account on each device; Settings Sync (Beta); no mobile pairing yet | Local terminal; cloud for settings only | N/A | Account-based; SOC 2; terminal is local | Yes — terminal is local |
| **Omnara** | `pip install omnara && omnara` → mobile sees sessions via cloud relay | Cloud relay (bridge → Omnara cloud → phone) | Omnara | Open source bridge; cloud sees metadata (not agent execution) | No — cloud relay required |
| **CC Pocket** | `npx @ccpocket/bridge` → QR, mDNS auto-discovery, or manual URL | Direct LAN / Tailscale P2P (self-hosted bridge, no relay) | User (self-hosted bridge on dev machine) | Fully self-hosted, open source; data encrypted in transit | Excellent — direct LAN; remote via Tailscale |
| **Blink.sh** | Manual host entry (IP + credentials in app) | Direct SSH | N/A | Standard SSH key trust | Excellent — direct |
| **Lancer (current)** | Phone shows QR → `lancerd pair` scans it → `lancerd relay` connects | Blind WebSocket relay (ciphertext-only) | User (self-host via Tailscale Funnel or GCP; default `relay.conduit.dev` not deployed) | X25519 ECDH + ChaCha20-Poly1305; relay sees only ciphertext; ephemeral keys | None — relay-only |

---

## 2. Question 1: Is a RELAY the right architecture?

### The case for "relay right now, extend later"

Lancer's blind relay (`daemon/push-backend/websocket_relay.go`) has the right security
properties: it forwards only ciphertext, holds no key material, and the
X25519 ECDH handshake means compromise of the relay buys an attacker
nothing but opaque bytes. This is the same model Warp's mobile pairing
targets ([Warp #5093](https://github.com/warpdotdev/Warp/issues/5093),
[mobile pairing pattern](https://www.mintlify.com/dyoburon/jarvis/networking/mobile-pairing)).

**Strengths of the current relay approach:**
- **Works everywhere.** NAT, firewall, CGNAT, cellular — both sides dial
  out. No inbound ports. No UPnP, no STUN/TURN/ICE.
- **Zero user setup.** No VPN, no Tailscale install, no SSH key config.
- **Security is sound.** After `peer_joined`, all traffic is
  ChaCha20-Poly1305 with ephemeral X25519 keys. The relay is blind.
- **Already built.** `e2e_client.go`, `e2e_crypto.go`, `E2ERelayClient.swift`,
  `PairingCrypto.swift` — this is not speculative.

**Weaknesses:**
- **Single point of failure.** If `relay.conduit.dev` is down, *all*
  pairing breaks. The relay is self-hostable (`LANCER_RELAY_URL` env var)
  but the default is a single domain not yet deployed.
- **Latency.** All traffic bounces through the relay, even two machines on
  the same LAN. This matters for the block terminal (PTY frames are
  latency-sensitive — see `SessionViewModel.onBlockBytes`).
- **Relay cost.** The relay operator pays for bandwidth. For a free-tier
  tool, this scales with user count. (`websocket_relay.go` is ~220 lines
  and near-stateless, so a single `e2-micro` handles thousands of
  concurrent pairs, but egress bandwidth costs.)
- **No offline/LAN path.** If both devices are on the same network with
  no internet, pairing fails.

### Alternatives evaluated

#### Direct LAN/P2P (WebRTC, custom STUN/ICE)
- **Pros:** Zero infrastructure cost, lowest latency, works offline.
- **Cons:** Requires STUN/TURN servers for NAT traversal (same hosting
  problem as the relay). ICE negotiation adds round-trips. Cellular NAT
  (CGNAT) often blocks P2P entirely — you still need a TURN relay.
  WebRTC on iOS adds ~200KB framework overhead.
- **Verdict:** Good as an optimization layer but cannot replace the relay —
  you still need the relay as TURN fallback.

#### Tailscale/WireGuard mesh
- **Pros:** P2P traffic, NAT traversal via DERP relays (same model as
  "direct + relay fallback"), strong identity model (node keys + ACLs).
- **Cons:** Requires the user to install and configure Tailscale. That's
  an extra dependency and an extra login flow. Lancer would either need
  to embed Tailscale (heavy) or require it as a prerequisite (friction).
- **Verdict:** Good for the *power-user* SSH path — `BridgePairingView`
  already has an "advanced · connect over SSH" link. The Tailscale
  DERP architecture is worth **stealing the idea from**: maintain a
  preference for direct connection, fall back to relay.

#### SSH reverse tunnel (`ssh -R`)
- **Pros:** No new infrastructure; the user already has SSH.
- **Cons:** Requires a publicly-reachable SSH server (a VPS) or the
  phone to accept inbound SSH (impossible on cellular). No E2E story
  without adding a layer. High latency. Complex reconnect.
- **Verdict:** Wrong tool. This is what Lancer is *replacing*.

#### ngrok / Cloudflare Tunnel
- **Pros:** Mature, well-maintained, free tier available, excellent NAT
  traversal (outbound-only).
- **Cons:** The tunnel endpoint terminates TLS — the tunnel operator
  (ngrok/Cloudflare) sees **plaintext** unless the app adds its own
  encryption layer. Both are opaque dependencies. Neither is
  self-hostable (ngrok has a self-hosted option for paying customers
  only; Cloudflare Tunnel requires Cloudflare). Lancer already has
  the blind relay — adding an ngrok tunnel in front of it is just
  another hop.
- **Verdict:** No benefit over the existing blind relay.

#### Hybrid (direct-when-possible, relay-as-fallback)
- **Pros:** Best of both worlds: low latency on LAN, relay for everything
  else.
- **Cons:** Adds complexity (connection negotiation, ICE or mDNS
  discovery, fallback logic). The relay code already exists; the direct
  path does not.
- **Verdict:** **This is the right long-term architecture.** Do not build
  it now — ship the relay first, add LAN-direct in a follow-up.

### Verdict: Relay is correct for v1, but MUST add a LAN-direct path and a self-host fallback

The blind relay is the right starting point: it works everywhere, is
already built, and is security-proven. The risk is a single point of
failure (`relay.conduit.dev`). Mitigate by:
1. Making the relay self-host trivially (already done via `LANCER_RELAY_URL`
   and `DEPLOY.md`).
2. Adding a LAN-direct path (mDNS + direct TCP/WebSocket) so same-network
   pairs skip the relay entirely.
3. In the QR payload, encode a `lanURL` alongside the `relay` URL so the
   phone and daemon can negotiate direct first.

The `QRPairingPayload` struct in `BridgePairingView.swift:351` and
`qrPairingPayload` in `relay_install_helper.go:31` already have a
simple `{ v, relay, code, pk }` shape — a `lanURL` field fits naturally.

---

## 3. Question 2: Is host-prints-QR → phone-scans the best handshake direction?

### Current state: phone-shows-QR is the default

`BridgePairingView.swift` (line 114–159) renders a QR on the phone
containing `{ v, relay, code, pk }` where `pk` is the phone's ephemeral
public key. The user is told to scan it with `lancerd pair`. But
`lancerd pair` (`relay_install_helper.go:69`) ALSO generates its
own QR and prints it to the terminal — creating **two QRs in two
different directions** with no clear primary flow.

A "scan a code shown by the host instead" button
(`BridgePairingView.swift:165`) exists for the reverse direction.
The relay handles both: order-independent, first peer creates the pair,
second peer triggers `peer_joined`.

### Analysis of the direction choice

| Direction | UX | Security | Caveat |
|---|---|---|---|
| **Phone shows QR → host scans** | Phone already on, user looks at phone, host needs a camera to scan (terminal can't scan a QR — `lancerd pair` would need to read from webcam or accept a typed code). | Phone is source of trust: phone generates keypair, host never needs a camera. | Host terminal has no camera — the host can't actually scan a phone QR. The code must be typed manually, which is friction + phishable. |
| **Host prints QR → phone scans** | Host terminal is already running `lancerd pair`, renders ANSI QR. Phone has camera — natural scan. | Host generates keypair, QR carries host's public key. Phone must trust the host key — but the phone user is physically present, so visual confirmation works. | Requires the user to look at the host terminal. The QR encodes `{ v, relay, code, pk }` where `pk` is the DAEMON's public key. |
| **Both (bidirectional, current)** | Confusing — which QR do I scan? | Both directions work at the protocol level; the issue is UX clarity. | The relay's order-independence is correct, but the UI doesn't guide the user to one clear flow. |

### Verdict: Host-prints-QR → phone-scans is the correct primary direction

**Reasons:**
1. **The host terminal can already render ANSI QRs.** `lancerd pair`
   (`relay_install_helper.go:69`) does this today — the QR is inverted
   for dark terminals. The phone has a camera. This is the natural
   pairing motion.
2. **The installer flow** (`curl ... | sh`) runs on the host. After
   installing, `lancerd pair` prints the QR and the code. The user
   already has their phone in hand — they scan. No typing.
3. **Phone-shows-QR is physically impossible for the host to scan.**
   A terminal cannot read a camera image. The typed-code fallback
   (`BridgePairingView.swift:95–101`) is the actual path for
   phone-shows-QR, which is friction + phishable.
4. **The phone-scans direction is what CC Pocket uses**, and it's
   considered the gold standard for mobile pairing (QR code from bridge
   → scan in app).
5. **Security is symmetric** — the X25519 ECDH works identically
   regardless of which side generates first. The relay is
   order-independent (`websocket_relay.go:70–86`).

**What to change:**
- Make `BridgePairingView` default to **scanning a host QR**, not
  showing one. The phone shows a camera viewfinder (already built:
  `QRScannerView.swift`) waiting for the host QR.
- Show the typed-code fallback when the camera is unavailable
  (simulator, no permission) — already built.
- Keep the phone-generates-QR path as an **alternative** for the
  "I don't have a camera on my host" scenario (Raspberry Pi, headless
  server) — triggered by a "show QR for the host to type" button.
- Merge `lancerd pair` and `lancerd relay` into a single `lancerd pair`
  command that prints the QR AND starts the relay session, so the user
  doesn't need to run two commands.

---

## 4. Question 3: How comparable tools do it (2025–2026)

### Tailscale — `tailscale up --auth-key` + device approval

Tailscale's auth-key model is the closest parallel to Lancer's
pairing code. An admin generates a pre-approved key, embeds it in a
one-liner, and the node joins the tailnet without interactive auth.
Keys can be ephemeral (auto-removed on disconnect), single-use, or
reusable, with configurable expiry.
[Src](https://tailscale.com/docs/features/access-control/auth-keys).
Device approval adds a human-in-the-loop gate that's exactly what
Lancer's phone-approves flow does — but at the *node join* level, not
per-action. The Co-ordination server (or headscale for self-host) is
the analogue of Lancer's relay — but Tailscale traffic goes P2P once
coordination completes, with DERP relays as fallback.

**Takeaway:** Pre-approved ephemeral keys are a proven pattern for
"install once, trust forever." Lancer's 6-digit code is an ephemeral
pre-auth key. The DERP relay architecture (P2P-first, relay-fallback)
is the direction Lancer should grow toward.

### VS Code Remote Tunnels — GitHub device-code OAuth

`code tunnel` authenticates via GitHub OAuth device-code flow. The
remote machine runs a tunnel client that connects to Microsoft Dev
Tunnels (Azure relay). The client connects from vscode.dev or VS Code
Desktop via the same GitHub identity. All traffic goes through
Microsoft's relay — no P2P.
[Src](https://code.visualstudio.com/docs/remote/tunnels).

**Takeaway:** This works because Microsoft can assume every user has a
GitHub or Microsoft account. Lancer has no account system — so it
cannot use device-code OAuth without adding identity infrastructure.
The relay-only transport is a deliberate choice (simplicity over
performance), which validates Lancer's same choice.

### Cloudflare Tunnel — token-in-one-line install

Cloudflare's dashboard literally hands you a one-line install command
with the tunnel token embedded: `sudo cloudflared service install <TOKEN>`.
The token is a JSON credential file that authenticates the connector to
the tunnel. The connector makes 4 outbound connections to Cloudflare's
edge.
[Src](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/).

**Takeaway:** This is the gold standard for *delivery UX*. The token and
the install are fused into one copy-paste. Lancer's `curl ... | sh &&
lancerd pair` is architecturally identical — but Cloudflare does it
at scale with signed binaries and a global edge network.

### CC Pocket — QR + mDNS + direct LAN (closest analogue to Lancer)

CC Pocket runs `npx @ccpocket/bridge@latest` on the host, which starts
a local bridge server. The mobile app pairs via QR code, mDNS
auto-discovery, or manual URL. The transport is **direct LAN** (TCP
connection to the bridge) or **Tailscale P2P** for remote access. No
cloud relay.
[Src](https://play.google.com/store/apps/details?id=com.k9i.ccpocket).

**Takeaway:** CC Pocket's architecture is what Lancer v2 should be:
self-hosted bridge on the agent machine, QR pairing, direct LAN, and
Tailscale for remote. CC Pocket proves this works today, and it's
open source. The difference is that CC Pocket's bridge is for
Codex/Claude Code session control — same use case as Lancer.

### Termius — E2E encrypted vault sync

Termius syncs hosts, keys, and configs between devices via E2E
encrypted cloud sync (X25519 + XSalsa20-Poly1305). Unlike the others,
Termius does not tunnel or relay SSH traffic — each device connects
directly to the SSH server.
[Src](https://docs.termius.com/security/encryption-overview.md).

**Takeaway:** Lancer should also support this pattern for its SSH path:
paired hosts should sync across the user's devices via iCloud Keychain
(maybe already done via `HostRepository`). But the *pairing* problem
(trust a brand-new host) is what Termius doesn't solve — it assumes
you already have SSH access.

### Omnara — cloud relay

Omnara runs a bridge on the dev machine that forwards agent activity to
Omnara's cloud. The mobile/web app connects to the cloud to see
approvals, diffs, and logs. Non-open-source cloud relay.
[Src](https://omnara.com).

**Takeaway:** Same model as Lancer's relay but with a proprietary
backend. Lancer's blind-relay approach is strictly more secure
(Omnara's cloud can read the data). The market validates the
"bridge on host → relay → phone" pattern.

### Warp — no mobile pairing yet

Warp has no mobile app. Issue [#5093](https://github.com/warpdotdev/Warp/issues/5093)
requests QR-based login for multi-device auth. The described pattern in
a related spec ("QR + blind E2E relay") is byte-for-byte Lancer's
architecture — strong external validation.
[Src](https://www.mintlify.com/dyoburon/jarvis/networking/mobile-pairing).

### Blink.sh / Dashwave — manual host entry

Both are mobile SSH clients. You type or paste a hostname/IP and
credentials. No pairing, no relay, no onboarding flow. They solve a
different problem (I-already-have-SSH-access) than Lancer (I-want-to-
bootstrap-trust-with-a-new-host).

---

## 5. Question 4: Verdict for Lancer

### Current architecture assessment

The architecture is **structurally sound but operationally incomplete**.
The crypto is right (X25519 ECDH + HKDF-SHA256 + ChaCha20-Poly1305).
The blind relay is right. The relay code exists and is tested
(`TestRelayRoundTrip`, `TestE2ECryptoRoundTrip`). The iOS client code
exists (`E2ERelayClient.swift`, `PairingCrypto.swift`). The QR scanning
code exists (`QRScannerView.swift`).

The gaps are:
1. **No relay deployed.** `defaultRelayURL = "wss://relay.conduit.dev"`
   does not resolve. The entire pairing flow is dead without it.
2. **No release pipeline.** `install.sh` downloads from
   `conduit.dev/releases/latest` which does not exist. `curl|sh` is
   a dead end.
3. **Two commands to pair.** `lancerd pair` prints a QR but does not
   connect to the relay. `lancerd relay` connects but needs
   `LANCER_PAIRING_CODE` set manually. The user must run two commands.
4. **No LAN-direct path.** Everything goes through the relay, even
   same-LAN pairs.
5. **QR direction is confused.** Both phone-shows-QR and host-shows-QR
   exist but neither is the clear primary path.

### Smallest change to get to viable

**Phase 0 (must-ship):**
1. Deploy `relay.conduit.dev` (follow `DEPLOY.md` — GCP `e2-micro` or
   Fly.io). This is a hard blocker — nothing works without it.
2. Merge `lancerd pair` + `lancerd relay` into one command. The
   `lancerd pair` command should print the QR and immediately start
   the relay WebSocket session, so the user runs one command and waits.
3. Swap the default direction in `BridgePairingView`: show the scanner
   first (waiting for host QR), with a "show QR for host" button as
   fallback. The host is always the first thing configured (install +
   `lancerd pair`), so the phone should wait to scan.
4. Publish a signed `lancerd` binary + `install.sh` at a real URL.

**Phase 1 (high priority):**
5. Encode a `lanURL` in the QR payload. When phone and daemon detect
   they're on the same LAN (IP match, mDNS, or direct TCP connect),
   skip the relay and connect directly.
6. Add rate-limiting for the typed-code fallback in
   `websocket_relay.go` (defend brute-force).
7. Make codes single-use + short-TTL (5 min) — `websocket_relay.go`
   already has `CreatedAt`, enforce expiry.

**Phase 2 (nice to have):**
8. Add mDNS auto-discovery for same-LAN pairs (no QR needed — the
   phone discovers `lancerd` on the network automatically).
9. iCloud sync of paired hosts so re-pairing on a new phone is
   unnecessary.
10. Fleet/team mode: Tailscale-style pre-auth keys + device approval
    for multi-host setups.

### Specific file references

| File | What it needs |
|---|---|
| `BridgePairingView.swift:114-159` | Flip default from show-QR to scan-QR. Keep show-QR as fallback button. |
| `BridgePairingView.swift:351-355` | Add optional `lanURL` field to `QRPairingPayload`. |
| `relay_install_helper.go:69-150` | Merge `printRelayInstructions` with the relay connect loop — print QR, THEN connect. |
| `relay_install_helper.go:31-37` | Add `lanURL` to `qrPairingPayload`. |
| `main.go:53-54` | Make `lancerd pair` run `printRelayInstructions()` + `runRelay()` in sequence (or make `pair` the entry point and have it do both). |
| `main.go:68-93` | `runRelay()` needs to accept the code from `pair` instead of only reading `LANCER_PAIRING_CODE`. |
| `RelaySettings.swift:11` | `defaultURLString` resolves to nothing. Must deploy the relay at that URL. |
| `install.sh:45-47` | `DOWNLOAD_BASE` resolves to nothing. Must publish binaries. |
| `websocket_relay.go:35-41` | Add code expiry check (`CreatedAt + 5min > now`). |
| `E2ERelayClient.swift:148-155` | Add direct-connect try-before-relay logic. |
| `websocket_relay.go:150-155` | Add `LANCER_PAIRING_CODE` as a one-time-use gate (delete pair after both sides connect). |

---

## 6. Prioritized recommendation

1. **Deploy the relay and ship binaries.** Without these, the entire
   onboarding is dead code. This is the hardest item (ops work) but
   the only real blocker. (P0)
2. **Merge `pair` + `relay` into one command.** One command prints QR
   and waits. The user runs `curl ... | sh && lancerd pair` and
   does nothing else on the host. (P0)
3. **Flip the QR direction to host-prints → phone-scans.** The phone
   opens a camera viewfinder by default, with a typed-code fallback.
   The "show QR on phone" path becomes the secondary option for
   headless hosts. (P1)
4. **Add LAN-direct negotiation.** Encode optional `lanURL` in the QR
   so same-network pairs bypass the relay. No relay dependency for
   local use. (P1)
5. **Harden the relay.** Code expiry, single-use, rate-limits on the
   typed-code path. (P2)
6. **Add mDNS auto-discovery.** The phone discovers `lancerd` on the
   LAN without scanning anything. (P3)

---

## 7. Bottom line

**Keep the architecture, fix the ops, flip the QR direction.** The
blind relay + X25519 ECDH + ChaCha20-Poly1305 is the right design —
it matches the Warp/Jarvis mobile pairing pattern, is more secure
than device-code OAuth, and the code is already written. The gaps are
operational (no relay deployed, no binaries published) and UX (the QR
direction is backwards, pairing is a two-command flow). The smallest
path to a working product is: deploy `relay.conduit.dev`, ship signed
binaries, merge `pair`+`relay` into one command, and make the phone
scan the host's QR by default. Add LAN-direct + mDNS in the next pass
to eliminate the single-point-of-failure dependency on the relay.

---

## Sources

- [Tailscale — Auth keys](https://tailscale.com/docs/features/access-control/auth-keys)
- [Tailscale — Device approval](https://tailscale.com/kb/1099/device-approval)
- [Tailscale — Ephemeral nodes](https://tailscale.com/docs/features/ephemeral-nodes)
- [headscale — Registration (preauthkeys)](https://juanfont.github.io/headscale/0.28.0/ref/registration/)
- [VS Code — Developing with Remote Tunnels](https://code.visualstudio.com/docs/remote/tunnels)
- [VS Code — Remote, even better (device-code login)](https://code.visualstudio.com/blogs/2022/12/07/remote-even-better)
- [Cloudflare — Locally-managed tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)
- [Cloudflare — Tunnel tokens](https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens)
- [ngrok — Agent docs](https://ngrok.com/docs/agent)
- [Termius — E2E encryption overview](https://docs.termius.com/security/encryption-overview.md)
- [Warp — Easier login / QR request #5093](https://github.com/warpdotdev/Warp/issues/5093)
- [Warp/Jarvis — Mobile pairing pattern (QR + blind E2E relay)](https://www.mintlify.com/dyoburon/jarvis/networking/mobile-pairing)
- [Omnara — Product page](https://omnara.com)
- [CC Pocket — Google Play](https://play.google.com/store/apps/details?id=com.k9i.ccpocket)
- [CC Pocket — GitHub](https://github.com/K9i-0/ccpocket)
- [RFC 8628 — OAuth 2.0 Device Authorization Grant](https://www.rfc-editor.org/rfc/rfc8628.html)
- [CSA — Device-code phishing: 37× surge, 340+ M365 orgs](https://labs.cloudsecurityalliance.org/research/csa-research-note-oauth-device-code-phishing-surge-20260405/)
