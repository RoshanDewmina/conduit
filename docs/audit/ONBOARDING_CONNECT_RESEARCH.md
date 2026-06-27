# Lancer — Onboarding & Connect Research

> How does a **phone-first** user connect a new host to Lancer with the least friction and the most security?
> Research + design recommendation. **No production code in this doc.**
> Date: 2026-06-15. Branch context: `codex/uiux-audit`.

## TL;DR

- **Primary recommendation:** ship the **QR-bound pair-code over the E2E relay**, driven by a real `curl … | sh` installer. The installer prints a QR (and the 4-digit/6-digit code as fallback); the phone scans it; the host's `lancerd` dials the blind relay and a Curve25519 ECDH + AES-GCM channel binds the two. **No private key leaves the phone, no inbound ports, works on any network, needs no computer at the keyboard** beyond pasting one install line.
- **Power-user fallback:** the existing **BYO SSH + `lancerd serve`** path (today's default), with inline key-gen + one-tap `ssh-copy-id` already scaffolded in `AddHostView`. SSH stays the install-free escape hatch for people who already have key access.
- **Why this over plain device-code (RFC 8628):** the OAuth device-code flow is the most familiar pattern but is **actively being weaponized** (a 37.5× surge in device-code phishing in early 2026; one campaign hit 340+ M365 orgs). Its core weakness — a short code that means nothing about *which* device it authorizes — is exactly what Lancer must avoid for an agent that can run `rm -rf`. QR binds the code to a *channel* and a *public key*, defeating the remote-phishing class outright.

Nearly all of the recommended path **already exists in the repo** (relay, crypto, daemon client, pairing views). The missing pieces are **infra/ops** (deploy the relay, build a release pipeline), not architecture.

---

## 1. Candidate comparison

Criteria: **Convenience** (taps; needs a computer?) · **Security** (key custody, MITM/TOFU, code phishing, replay) · **Infra** (relay/DNS/release pipeline) · **Offline/LAN** · **Fit** with Lancer's SSH + `lancerd` (+ relay) model.

| Mechanism | Convenience | Security | Infra required | Offline / LAN | Fit with Lancer |
|---|---|---|---|---|---|
| **1. QR-code pairing** (host serves/prints a QR; phone scans) | **Best.** Scan = host+code+pubkey+relay in one capture. No typing, no computer-at-keyboard beyond pasting the install line. | **Strong.** QR carries the host's public key → channel binding; scanning is physical-proximity or trusted-screen → defeats remote code phishing. Replay killed by ephemeral code + one-shot pairing. | Needs the installer to render a QR (trivial) + a relay if off-LAN. | QR can encode a **LAN URL** for an offline same-network pair; falls back to relay otherwise. | **Excellent** — wraps the existing relay/crypto; only adds QR encode/scan + a real `lancerd pair`. |
| **2. OAuth device-code (RFC 8628)** (phone shows short code; host claims it) | High, familiar. But requires the host to have a browser/poller and the user to type a code somewhere. | **Weakest of the modern options.** The code authorizes "a device" with no binding to *which* — the exact property phishers abuse (37.5× surge in 2026). Needs an auth server + rate-limiting + explicit "does this code match?" confirmation. | Needs an **authorization server** + identity (GitHub/OIDC) Lancer doesn't have today. | Poor — assumes an IdP reachable from both ends. | **Poor** — Lancer has no account system; introduces an IdP dependency and the phishable pattern. |
| **3. Relay pair-code** (current scaffold; typed 6-digit over E2E relay) | Medium. Two ends type the same code; typing 6 digits on a phone is the friction. | **Strong crypto** (X25519 ECDH + AES-GCM, blind relay) **but** a *typed* code is brute-forceable without rate-limit and is human-shareable (phishable). | **Already built.** Needs `relay.conduit.dev` deployed. | Relay-only today (no LAN path). | **Native** — this IS Lancer's model; QR (option 1) is the security/UX upgrade on top. |
| **4. `curl … \| sh` installer that prints QR/pair-code** | High once you can paste one line on the host. | Inherits whatever the printed artifact is (make it a QR, option 1). `curl\|sh` itself is a supply-chain trust decision — must be HTTPS + pinned + ideally checksummed. | Needs a **release pipeline** (build/sign/publish `lancerd`) + a domain. This is the big missing op. | Installer runs locally; pairing then uses relay or LAN. | **Excellent** — it's the delivery vehicle for options 1/3; the FEATURE_TEST_PLAN target board already mocks this. |
| **5. Tailscale-style pre-auth / ephemeral keys + device approval** | High for fleets; one `up --authkey`. | **Very strong** (WireGuard identity, device-approval gate, key expiry). | Heavy: a coordination/control plane (or **headscale** self-host) + the tailnet concept. | Excellent (mesh, NAT traversal, MagicDNS). | **Overkill / wrong layer.** Lancer isn't a VPN; would mean adopting Tailscale as a dependency. Good *inspiration* (ephemeral + approval), not the mechanism. |
| **6. Deep-link / universal-link "magic link"** | Highest taps-wise (tap a link → app opens paired). | **Risky alone.** Links are trivially forwardable/phishable; needs the same pubkey binding QR gives, plus link integrity. iOS universal links need an associated-domains file. | Needs a domain + AASA file + the link to carry a bound token. | Poor (link delivery assumes a channel). | **Complementary** — use as the *scan target* a QR encodes, not as the standalone primitive. |

**Verdict:** Options **1 + 4** (QR printed by a real installer, over the existing relay) dominate. Option 3 is the same path minus the QR upgrade. Options 2/5/6 are either the wrong dependency or a phishing liability when used alone.

---

## 2. How comparable tools actually do it

### Tailscale — pre-authorized & ephemeral auth keys + device approval
`tailscale up --auth-key <key>` registers a node non-interactively. Keys can be **pre-approved** (auto-authorize when tailnet device-approval is on), **ephemeral** (auto-removed when the node goes offline), and **tagged** (auto-organize). The recommended pattern: servers use a *pre-approved* key so they join without a human re-approving; end-user devices go through the **device approval** gate. The lesson for Lancer: separate "a credential that lets a host *attempt* to join" from "a human deciding this device is allowed" — a clean model for a future fleet/team tier. ([Auth keys](https://tailscale.com/docs/features/access-control/auth-keys), [Ephemeral nodes](https://tailscale.com/docs/features/ephemeral-nodes), [Device approval](https://tailscale.com/kb/1099/device-approval)). **headscale** mirrors this for self-host: `headscale preauthkeys create --user x [--reusable] [--expiration 720h]` then `tailscale up --login-server <url> --authkey <key>` ([headscale registration](https://juanfont.github.io/headscale/0.28.0/ref/registration/)).

### VS Code Remote Tunnels — GitHub device-code login
`code tunnel` authenticates the *host* by sending the user to `https://github.com/login/device` to enter an `XXXX-XXXX` code; the client then connects via a `vscode.dev` link. It leans entirely on GitHub as the IdP and the device-code grant. Convenient because Microsoft/GitHub already *is* everyone's account — Lancer has no such account, which is exactly why this pattern doesn't transplant cleanly ([Developing with Remote Tunnels](https://code.visualstudio.com/docs/remote/tunnels), [Remote, even better](https://code.visualstudio.com/blogs/2022/12/07/remote-even-better)).

### Cloudflare Tunnel (`cloudflared`) — token-as-installer
A remotely-managed (named) tunnel runs from a single token: `sudo cloudflared service install <TOKEN>`. The dashboard literally hands you the **one-line install command with the token embedded** — copy, paste on the host, done; no inbound ports. Quick Tunnels need no token at all for throwaway use. This is the gold standard for the *delivery* UX: the secret and the install are fused into one copy-paste line ([Create a locally-managed tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/), [Tunnel tokens](https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens)). **ngrok** is the same shape: `ngrok config add-authtoken <TOKEN>` then expose ([ngrok agent](https://ngrok.com/docs/agent)).

### Termius — encrypted cloud vault sync (not pairing)
Termius Premium **Cloud Sync** syncs hosts, key pairs, identities, and snippets across macOS/Windows/Linux/iOS/Android with end-to-end encryption, and "real-time sync adds hosts on one device that appear on another in seconds … with WebSocket fallback." It solves *a different problem* (move your existing SSH config between your own devices), not "bootstrap trust with a brand-new host," but it's the bar for the **cross-device sync** Lancer already has via iCloud ([Termius](https://termius.com/)).

### Warp / "Jarvis"-style mobile pairing — QR + blind E2E relay (the model Lancer already has)
The mobile-pairing pattern documented for terminal companions: "pair a mobile device with a desktop instance … using **QR codes** for connection setup and **end-to-end encryption** … a secure encrypted WebSocket connection … through a **relay server**, with all PTY data encrypted with **AES-256-GCM** before leaving the desktop, while the **relay sees only ciphertext**." This is **byte-for-byte Lancer's existing scaffold** (`E2ERelayClient` + `websocket_relay.go` + `PairingCrypto`) — strong external validation that the architecture is right; Lancer is just missing the QR layer and the deployed relay ([Warp login QR request #5093](https://github.com/warpdotdev/Warp/issues/5093), [mobile device pairing pattern](https://www.mintlify.com/dyoburon/jarvis/networking/mobile-pairing)).

### OAuth 2.0 Device Authorization Grant (RFC 8628) — and why to be careful
RFC 8628 itself warns: clients "MUST still display the `user_code` … as **remote phishing mitigation**," and the server "SHOULD … ask [the user] to verify that it matches the `user_code` being displayed on the device." That mitigation is advisory and routinely skipped — and attackers have industrialized the gap: a **37.5× increase** in device-code phishing pages by April 2026, "a single campaign compromised over 340 Microsoft 365 organizations," via a PhaaS kit. The structural flaw: "the user code arrives through an untrusted channel … the victim sees a legitimate domain and performs genuine authentication — nothing appears suspicious." For an app that authorizes an agent to run shell commands, a flow whose failure mode is "user approved the *attacker's* device" is unacceptable as the primary path ([RFC 8628](https://www.rfc-editor.org/rfc/rfc8628.html), [CSA: device-code phishing surge](https://labs.cloudsecurityalliance.org/research/csa-research-note-oauth-device-code-phishing-surge-20260405/)).

**Synthesis:** Cloudflare's token-in-one-line *delivery* + Warp/Jarvis's QR-bound E2E-relay *pairing* + Tailscale's pre-auth/approval *governance* = the blueprint. Lancer already has the middle piece built.

---

## 3. Recommendation

### Primary: QR-bound pair-code over the E2E relay, delivered by a real installer

The phone is the **source of trust**: it generates the Curve25519 keypair and the ephemeral pairing code (already `PairingCrypto.generatePairingCode()` / `generateKeyPair()`), encodes them into a QR, and shows the install line. The host runs `curl … | sh` then `lancerd pair`, which **reads the QR** (or accepts the typed code), dials `wss://relay.conduit.dev`, and completes ECDH. The relay is **blind** (`websocket_relay.go` forwards ciphertext it cannot read). The phone's SSH private key never enters this flow at all — relay pairing doesn't use SSH.

Why it wins on every axis:
- **Convenience:** one paste on the host + one scan on the phone. No SSH key authorization dance (the Finding #1/#4 "signup-killer"), no inbound ports, works behind NAT/CGNAT on cellular.
- **Security:** the QR binds the code to the host's intent *and* carries/exchanges public keys, so a forwarded code is useless without the matching channel — this is precisely the remote-phishing defense device-code lacks. Codes are ephemeral and single-use (replay-dead). TOFU still applies to any SSH fallback.
- **Infra:** the *code* exists; the *ops* don't. Need: deploy the relay, stand up a `curl|sh` release pipeline, add QR encode/scan.
- **Offline/LAN:** the QR can encode a **LAN URL** so a same-network pair never touches the relay.

### Power-user fallback: BYO SSH + `lancerd serve`

Keep today's path for people who already have key access or self-host with no relay. `AddHostView` already has paste-to-parse, inline Ed25519 key-gen, and a one-tap `ssh-copy-id` one-liner — finish Finding #4 by surfacing it *in the connect flow*, not Settings. TOFU host-key prompt stays mandatory (Phase-1 invariant). This is the "advanced · connect a remote host over SSH" link already present in `BridgePairingView`.

---

## 4. End-to-end UX flow (recommended path)

1. **Welcome** (`OnboardingView` screen 1) → "get started".
2. **Pair the bridge** (replaces `screen2SSH`'s emphasis; promotes `BridgePairingView`):
   - Big copy-able install line: `curl -fsSL conduit.dev/install.sh | sh && lancerd pair` with a **Copy** button (reuse the existing copy affordance).
   - A **QR code** rendered from `{ relayURL, pairingCode, phonePublicKey, lanURL? }` (today `BridgePairingView` shows a *decorative* grid — swap for a real `CIQRCodeGenerator` payload).
   - Live status card: `waiting for bridge…` → `paired` (already wired to `pairingState`; back it with the real `E2ERelayClient` instead of the 1-second fake `startPairingListener`).
   - Small footer link: **"advanced · connect over SSH"** → falls through to `AddHostView` (already the `onUseSSH` callback).
3. **Host runs the line.** Installer drops `lancerd`, runs `lancerd install` (systemd user unit + wires the Claude `PreToolUse` hook — see Finding #10), then `lancerd pair` **scans the QR shown on the phone** (camera) *or* prompts to type the code. `relay_install_helper.go` already prints a code box; upgrade it to also render a terminal QR.
4. **Pairing completes.** Relay emits `peer_joined` with each side's public key → both derive the AES-GCM session key (`deriveSessionKey`). Phone flips to **paired**.
5. **Approval policy** (`OnboardingView` screen 3, unchanged) → Caution / Balanced / Bypass preset.
6. **Done → monitoring board** (per Finding #5, land on the overview/inbox, *not* the block terminal). First approval card can be the demo teaser already in `InboxViewModel`.

Total user actions: paste once on the host, scan once on the phone, pick a preset. No computer required beyond the host's own shell; no SSH key authorization.

---

## 5. Implementation sketch (reuse vs build)

**Reuse as-is (already in repo):**
- `Packages/LancerKit/Sources/SecurityKit/PairingCrypto.swift` — X25519 ECDH, AES-GCM, code gen. Crypto core, done.
- `Packages/LancerKit/Sources/SSHTransport/E2ERelayClient.swift` — phone-side relay client (connect, ECDH `deriveSessionKey`, reconnect, keepalive). Wire it to the UI instead of the placeholder.
- `daemon/lancerd/e2e_client.go`, `daemon/lancerd/e2e_router.go` — host-side relay client + approval routing (`approvalPending` / `approvalResponse`). Done.
- `daemon/push-backend/websocket_relay.go` — the **blind relay hub** (code-keyed pairing, `peer_joined`, buffer, ping/pong). Done; just needs deploying.
- `daemon/lancerd/install.sh` — installer skeleton (binary copy, stale-binary guard, hook install).
- `Packages/LancerKit/Sources/WorkspacesFeature/AddHostView.swift` — the SSH fallback incl. inline key-gen + `ssh-copy-id`. Surface in the connect flow.

**Build / change:**
1. **Real QR in `BridgePairingView`** (`OnboardingFeature`): replace the decorative `pairingCodeGrid` and the fake 1-second `startPairingListener()` with (a) a `CoreImage` `CIQRCodeGenerator` of the pairing payload and (b) a real `E2ERelayClient` driven from `AppRoot` (today `AppRoot` hardcodes `relay.conduit.dev` + code `000000` — make these the *generated* code + a configurable URL).
2. **`lancerd pair` subcommand** + QR **scan/parse** on the host: extend `relay_install_helper.go` to render a terminal QR and accept a pasted/scanned payload; the camera-scan UX lives on the phone (the phone shows the QR, the host already has the code). Add a **LAN-direct** branch so same-network pairs skip the relay.
3. **Deploy the relay** (`relay.conduit.dev`): `push-backend` has `fly.toml` + Dockerfile; stand it up, get TLS/DNS. (Finding #2 Task #6.)
4. **Release pipeline for `lancerd`** so `curl conduit.dev/install.sh | sh` resolves and fetches a **signed, checksummed** binary for linux/macOS × arm64/amd64. (Finding #2 Task #5.) Pin TLS; publish a SHA-256.
5. **Code hardening:** rate-limit pairing attempts per code in `websocket_relay.go` (defend the typed-code fallback); make codes single-use + short-TTL; add an explicit "you're pairing host `X`" confirmation on the phone before the channel goes live.
6. **Governance hooks (Finding #10):** ensure `lancerd install` merges `PreToolUse` into `~/.claude/settings.json` idempotently and that the hook **fast-auto-approves when no phone is attached** (don't stall the host's own `claude` runs).

---

## 6. Open questions / risks

- **`curl | sh` trust:** acceptable industry-wide (Cloudflare, ngrok, Tailscale all do it), but Lancer must serve over pinned HTTPS, publish checksums, and ideally offer a "download + inspect" path. Signing story (notarization on macOS) is unsolved.
- **Relay availability = onboarding availability.** If `relay.conduit.dev` is down, *new* pairing breaks. Need the **LAN-direct** path and a self-host relay option (the relay is already self-hostable Go) so Lancer isn't a single point of failure.
- **Typed-code fallback is still phishable** if a user reads the code to an attacker. QR-first + rate-limiting + the "pairing host X" confirmation mitigate; consider dropping the typed path on untrusted networks.
- **What does relay pairing replace vs. SSH?** Relay carries `lancerd` RPC (approvals/status) but the FEATURE_TEST_PLAN's interactive **block terminal** is an SSH PTY. Decide whether paired-only hosts get terminal access (tunnel a PTY frame type over the relay) or whether the terminal stays SSH-only — affects whether SSH is truly optional.
- **Multi-host / fleet:** one code = one host. A Tailscale-style **reusable pre-auth key + device-approval** model is the natural extension for teams; out of scope for v1 but the relay's code-keyed design should leave room for it.
- **Camera permission UX:** scanning the QR needs a camera-permission prompt at exactly the right moment; have a manual-code path for users who decline.
- **iCloud-sync interaction:** paired hosts should sync across the user's devices like SSH hosts do — confirm the relay session key / re-pair story across devices (re-pair vs. share the derived key).

---

## Sources

- [Tailscale — Auth keys](https://tailscale.com/docs/features/access-control/auth-keys) · [Ephemeral nodes](https://tailscale.com/docs/features/ephemeral-nodes) · [Device approval](https://tailscale.com/kb/1099/device-approval)
- [headscale — Registration methods (preauthkeys)](https://juanfont.github.io/headscale/0.28.0/ref/registration/)
- [VS Code — Developing with Remote Tunnels](https://code.visualstudio.com/docs/remote/tunnels) · [Remote, even better (device-code login)](https://code.visualstudio.com/blogs/2022/12/07/remote-even-better)
- [Cloudflare — Create a locally-managed tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/) · [Tunnel tokens](https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens)
- [ngrok — Agent docs](https://ngrok.com/docs/agent)
- [Termius — Modern SSH client (Cloud Sync)](https://termius.com/)
- [Warp — easier login / QR request #5093](https://github.com/warpdotdev/Warp/issues/5093) · [Mobile device pairing pattern (QR + blind E2E relay)](https://www.mintlify.com/dyoburon/jarvis/networking/mobile-pairing)
- [RFC 8628 — OAuth 2.0 Device Authorization Grant](https://www.rfc-editor.org/rfc/rfc8628.html)
- [CSA — OAuth Device Code Phishing: 37× surge](https://labs.cloudsecurityalliance.org/research/csa-research-note-oauth-device-code-phishing-surge-20260405/) · [CSA — device-code phishing hits 340+ M365 orgs](https://labs.cloudsecurityalliance.org/research/csa-research-note-oauth-device-code-phishing-m365-20260325-c/)
- [GitHub Codespaces — Quickstart](https://docs.github.com/en/codespaces/quickstart)
