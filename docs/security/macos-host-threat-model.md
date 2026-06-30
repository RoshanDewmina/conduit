# macOS Host Threat Model — Lancer for Mac

**Status:** extends `docs/legal/SECURITY_ARCHITECTURE.md`. **Last updated:** 2026-06-21.

This document covers **only the new attack surface introduced by `Lancer.app`** (the macOS
menu-bar/management front-end, plan: `~/.claude/plans/you-are-working-on-curried-pixel.md`). It
does not restate pairing/relay/session-key crypto already specified in
`docs/legal/SECURITY_ARCHITECTURE.md` §2–§4 and `daemon/push-backend/PAIRING_PROTOCOL.md` — read
those first. Internal code keeps `Conduit*`/`conduitd`/`dev.conduit.*` identifiers; "Lancer" is
user-facing only, per `AGENTS.md`.

**Architecture recap (from the plan):** `Lancer.app` is a stateless client. The host service
(`conduitd`, soon `lancerd` — the rename is in flight on this branch, see Code-state note below)
is unchanged in role: it still owns sessions, PTYs, adapters, the relay socket, device identity,
pairing keys, provider credentials, policy, approvals, and audit. Lancer.app adds an install/pair/
diagnose UI on top, talking to the daemon over the existing local Unix-domain socket. Quitting or
crashing Lancer.app must never stop the daemon or any agent it is running.

**Code-state note:** this repo is mid-rebrand. Go source still uses `conduitd`/`~/.conduit`/
`dev.conduit.conduitd` in some files (`daemon/conduitd/install.go`, `relaypair.go`) and
`lancerd`/`~/.lancer`/`lancer-hook.sh` in others (`daemon/conduitd/paths.go`,
`hook_install.go`). This document describes the **security properties**, which hold under either
name; file/path examples below cite the name actually used in the cited file as of this writing.

---

## 1. Local IPC socket (`~/.conduit/conduitd.sock` → `~/.lancer/lancerd.sock`)

### 1.1 Current state (verified against code)

The resident daemon (`daemon/conduitd/resident.go: (*resident).listen`) binds a Unix-domain socket
at `socketPath()` (`daemon/conduitd/paths.go`) inside a `0700` directory (`lancerDir()` /
`conduitDir()`, same function, two names depending on file). On accept, `handleConnection` reads
one first message and classifies it by shape only:

- `{"op":"attach"}` (length-prefixed JSON, `framing.go: attachHello`) → `serveAttach` — the
  full bidirectional control channel (dispatch agents, approvals, policy changes).
- An unframed shim-spawn payload (`shim.go: isShimSpawn`) → PTY spawn path.
- Anything else unframed → `handleHookWithNotify` — the **PreToolUse hook** path (see §1.4).

**There is currently no peer-credential check, no per-connection auth token, and no protocol
version field anywhere in this handshake.** `attachHello` carries only `{"op":"attach"}` — no
token, no version. Today's only access control is the filesystem: socket file inherits directory
permissions, and only the owning UID can normally open a Unix-domain socket path under a `0700`
directory. That is the entire current trust boundary, and Lancer.app's arrival doesn't change it
on its own — but a GUI app raises the value of compromising it (a second, advertisable local
client now routinely connects), and this document specifies the hardening the plan requires before
shipping it (`docs/plans/macos-host-implementation.md` Phase C: "IPC auth/version-mismatch handling
end-to-end").

### 1.2 Asset / threat / mitigation

| Asset | Threat | Mitigation (required before Lancer.app ships) | Fail-closed behavior |
|---|---|---|---|
| The `attach` control channel (dispatch agents, read approval/policy state, change policy) | A malicious **same-UID** process (malware, a compromised dependency in another app run as the same user) connects to the socket and issues RPCs Lancer.app itself would issue | Per-user auth token file `~/.conduit/ipc-token` (mode `0600`, random ≥32 bytes, generated on first daemon start like `relay-pairing.json` already is) presented in the `hello` handshake; daemon rejects the connection if the token is absent or wrong | Reject connection (no partial trust); do not downgrade to a read-only mode — close the socket |
| The `attach` control channel | A **different-UID** local process (multi-user Mac, another account) connects | `SO_PEERCRED`/`LOCAL_PEERCRED` check (Linux: `SO_PEERCRED` via `syscall.GetsockoptUcred`; macOS: `LOCAL_PEERCRED` via `getsockopt`, `golang.org/x/sys/unix`) — reject any peer whose UID ≠ the daemon's own UID, **before** even reading the auth token | Reject connection at accept time; log to audit (UID attempted, no payload contents) |
| Protocol compatibility | Lancer.app (new) and `conduitd`/`lancerd` (old, un-upgraded) talk past each other — old daemon doesn't understand a new RPC shape, or a downgrade attack tricks the app into a weaker handshake | Versioned `hello` RPC: client sends `{"op":"hello","protocolVersion":N}` first; daemon replies `{"protocolVersion":N,"serviceVersion":"..."}` or an explicit version-mismatch error. Reject (don't best-effort-parse) any version it doesn't recognize | Fail closed: mismatched/missing version → reject before any other RPC is processed; surface "update required" in the UI, not a silent degraded mode |
| The hook path (`handleHookWithNotify`) | Same-UID malware impersonates the Claude/Codex PreToolUse hook to inject a fake "approved" signal, or to flood the approval queue | **Out of scope for the peer-cred/token gate above** — see §1.4, this is a known open question, not a solved one | N/A — flag explicitly, don't claim it's covered |

### 1.3 Why peer-credential check, not just the token

A `0600` token file stops a different-UID attacker from ever reading the token, but a same-UID
attacker can read `~/.conduit/ipc-token` exactly as Lancer.app does (same UID, same file
permissions) — token alone does not raise the bar against same-UID malware that's just reading
the same files Lancer.app reads. `SO_PEERCRED`/`LOCAL_PEERCRED` is therefore the more meaningful
mitigation for the different-UID case (multi-user Macs — rare but in scope per the test matrix's
"multi-user" line), while the token is the meaningful mitigation against **off-socket** discovery
(e.g., a process that finds the socket path but was never given the token via some other channel).
Both are required; neither alone is sufficient. The daemon must check peer UID first (cheap,
syscall-level, rejects before reading attacker-controlled bytes) then the token (handshake-level).

### 1.4 Open question: hooks are a separate, unauthenticated path today

`handleHookWithNotify` (`daemon/conduitd/server.go:1088`) is reached by the **same socket** but via
the unframed branch in `resident.go: handleConnection` — it is not behind `isAttachHello`, so it
inherits no auth from §1.1's planned token/peer-cred work unless that work explicitly also gates
this branch. The hook script (`docs/conduit-hook.sh` / `claudeHookScript` in `hook_install.go`)
only runs when `${LANCER_GATE}`/`${CONDUIT_GATE}` is set, scoping it to Lancer-launched runs — but
that env-var gate is a **convention enforced by the hook script itself**, not by the daemon. Any
same-UID process that sets the env var and replicates the hook's stdin JSON shape can submit
approval-relevant events through this path today, with or without Lancer.app.

**This needs an explicit decision, not a default assumption:** either (a) extend the same
peer-credential check to the hook branch (cheap, no new behavior for legitimate hooks since
they're already same-UID by construction), or (b) explicitly document that hook-path trust is
process-tree-based (only a hook spawned by an agent CLI as a child of a session the daemon itself
started should be trusted) and accept the residual risk. Recommendation: do (a) — peer-cred is
free and closes a real gap — before Lancer.app ships, since the GUI's existence means more
same-UID code now routinely talks to this socket and the daemon's overall attack surface should
not have an unauthenticated side door next to a freshly-authenticated front door.

---

## 2. LaunchAgent install path

### 2.1 Current state (verified against code)

`daemon/conduitd/install.go: installLaunchd` writes `~/Library/LaunchAgents/dev.conduit.conduitd.plist`
(mode `0644`) pointing `ProgramArguments` at the binary just copied to `~/.conduit/bin/conduitd`
(mode `0755`, copied from `os.Executable()` with no signature check on either the source or the
installed copy). `RunAtLoad`+`KeepAlive` are set; there is **no root involved** — this is a
per-user LaunchAgent, not a LaunchDaemon, matching the plan's "no root" decision.

**Gap:** today, `runInstall` performs **no code-signature verification** of the binary before
copying it into `~/.conduit/bin/` or registering it for persistence. Anything that can write to
the source binary's path or substitute itself for `os.Executable()`'s return value gets
launchd-level persistence the next time `conduitd install` (or, post-Lancer, "reinstall service"
in the UI) runs.

### 2.2 Asset / threat / mitigation

| Asset | Threat | Mitigation | Fail-closed behavior |
|---|---|---|---|
| The installed daemon binary (`~/.conduit/bin/conduitd`) | Tampering — a malicious binary is substituted before/during install, achieving boot/login persistence via the LaunchAgent | Ship `conduitd`/`lancerd` and `Lancer.app` as **Developer-ID signed, Hardened-Runtime, notarized** binaries (per the plan's Phase C). Before Lancer.app (re)installs or restarts the LaunchAgent, verify the managed binary's code signature (`codesign --verify --deep`, or `SecStaticCodeCheckValidity` via Security.framework) and **Team ID matches the bundled app's own Team ID** | Refuse to install/restart on signature mismatch; surface the failure in the UI (Diagnostics pane), do not silently fall back to running the unsigned binary |
| The LaunchAgent plist itself | A local attacker edits `dev.conduit.conduitd.plist` to point at a different binary or inject extra `ProgramArguments` | Plist is per-user (`~/Library/LaunchAgents`, not `/Library/LaunchDaemons`) so this is bounded by the same-UID trust boundary already assumed for the user's own account; no additional Mac-specific mitigation beyond standard account hygiene. Lancer.app should re-write (not trust-and-reuse) the plist on every "reinstall service" action so a tampered plist self-heals on next explicit install | On detecting plist content that doesn't match what Lancer.app would have written, treat as "needs reinstall" in Diagnostics rather than silently launchctl-loading it as-is |
| `SMAppService` registration (if adopted per the plan's Phase A) | Apple's API itself enforces that the registered helper is signed consistently with the main app (same Team ID, embedded in the app bundle) — verify this against current Apple docs before relying on it as a substitute for the manual check above | Use `SMAppService.agent(plistName:)` as the **preferred** registration path (plan §"Lifecycle management"); fall back to manual `launchctl bootstrap` only when adopting a pre-existing standalone install | If `SMAppService` registration fails (e.g., user hasn't approved it in System Settings → Login Items), show the failure explicitly — never silently fall back to an unmanaged background process |

No root is required or used anywhere in this path — consistent with `AGENTS.md`'s "no root"
constraint and the plan's explicit decision to keep `conduitd` as the unchanged host service.

---

## 3. Secrets in the UI

### 3.1 Invariant

Lancer.app is a **stateless client** (plan, "Architecture (target)"): it reads runtime state —
including secret *health/metadata* (e.g., "Anthropic API key: configured, last validated 2h ago")
— from `conduitd` over IPC on each launch, and must **never persist secret values** itself (no
Keychain item written by Lancer.app containing a provider API key, SSH private key, or X25519
private key; no on-disk cache of decrypted secret material). The daemon remains the sole owner of
provider credentials, pairing keys, and device identity (`docs/architecture/runtime-ownership-map.md`
in the plan's deliverables list).

### 3.2 Verified: redaction already exists, for audit — confirm and extend to app logs

`daemon/conduitd/audit.go:236 redactSecrets` strips `api_key`/`token`/`secret`/`password`/
`authorization`-prefixed values, `Bearer ...` headers, `sk-...` (OpenAI-shaped), and `ghp_...`
(GitHub PAT-shaped) tokens from `AuditEntry.Command` before it's ever written to the audit log
(`audit.go:95`). This is confirmed in code and is the correct baseline.

**Requirement for Lancer.app:** any logging Lancer.app itself does (Console.app via `os_log`,
crash reports, a future "export diagnostics bundle" feature mentioned in the plan's Phase A
Diagnostics pane) must route through the **same redaction function** (or an equivalent applied
client-side) before anything derived from daemon responses is written to a log line. Concretely:
if a `doctor`/diagnostics RPC response ever includes a raw secret-shaped string (it shouldn't, per
§3.1, but defense in depth), the app's logging layer must not be the path that leaks it. The
"export redacted bundle" diagnostic feature in the plan's Phase A scope is named for exactly this
reason — the redaction is in the name, not optional.

| Asset | Threat | Mitigation | Fail-closed behavior |
|---|---|---|---|
| Provider API keys, SSH keys, X25519 pairing keys | Lancer.app reads secret material into memory for display and accidentally persists it (Keychain, UserDefaults, a cache file) or logs it | App reads only secret **metadata** (configured/not, last-validated timestamp, masked last-4) via IPC; never the raw value. No app-owned Keychain item for any daemon-owned secret | If a diagnostics RPC ever returns a raw value (daemon bug), the app should refuse to render/log it rather than displaying it — treat as a daemon-side defect to fix at the source, not something the app papers over |
| Diagnostics export ("export redacted bundle", plan Phase A) | Exported bundle (for support / bug reports) leaks secrets | Bundle generation passes every included log line through `redactSecrets`-equivalent logic; review the bundle's contents against the same `secretPatterns` list (`audit.go:229`) before adding any new field to it | Exporting fails closed if redaction can't be confirmed applied — don't ship a "best effort" export |

---

## 4. Pairing from the Mac

Lancer.app drives the **existing** pairing flow (plan: "Reuse existing pairing: drive `conduitd
pair` and render the QR + 6-digit code in the app... Manual-code fallback already exists.") — it
does not implement new crypto. **Correction to the plan's framing:** there is no QR path left to
reuse. Per `docs/V1_IMPLEMENTATION_PLAN.md`, the iOS app's QR/camera pairing entry was removed
app-wide (`OnboardingPairing.swift`, `BridgePairingView.swift`) in favor of code-only entry through
the relay — the flow `daemon/push-backend/PAIRING_PROTOCOL.md` specifies and
`SECURITY_ARCHITECTURE.md` §2 describes. Lancer.app should drive `lancerd pair` and render the
6-digit code; "manual-code" is the *only* path now, not a fallback. Confirmed against code:

| Property | Verified in | Status |
|---|---|---|
| Single-use 6-digit pairing code | `daemon/push-backend/PAIRING_PROTOCOL.md` §1 ("Daemon mints 6 **digits**"); relay channel keyed by `code`, one daemon+phone pair per code | Confirmed |
| X25519 ECDH key exchange | `daemon/conduitd/e2e_crypto.go: generateKeyPair`, `deriveSessionKey` (curve25519, HKDF-SHA256) | Confirmed |
| Replay resistance | `SECURITY_ARCHITECTURE.md` §2.2 (key pinning, unconfirmed-code expiry, per-IP rate limiting) and `PAIRING_PROTOCOL.md` §2 — the code is consumed by the relay's first daemon+phone join, and a captured code that's already completed a pairing cannot be replayed to join a new channel because the relay's pair-by-code state is single-shot per pairing session; once a role's key is pinned to the code, a later connection presenting a different key for that role is rejected outright | Confirmed for the mechanisms that exist; **not yet a Mac-specific addition** |
| Mutual verification phrase | **Not found in code.** No `verificationPhrase`/equivalent exists in `e2e_crypto.go`, `relaypair.go`, or the iOS pairing UI as of this writing | **Gap — new requirement for Lancer.app, not yet implemented anywhere** |
| Device revocation takes effect immediately | `daemon/push-backend/device_bindings.go: handleRevokeDevice` sets `RevokedAt` and **clears `CredentialHash`** in the same update — the device's credential hash is gone, so any subsequent request bearing the old credential fails the next `sameCapability` check immediately, not on a delay or TTL | Confirmed |

### 4.1 New requirement: mutual verification phrase

The plan calls for "pairing → **mutual verification phrase**" (Phase B, full first-run flow) as
a step the Mac displays that the user must confirm matches what the phone shows, before either
side is trusted. This does not exist yet on either platform and must be designed, not assumed:

- **Derivation:** derive a short, human-comparable phrase (e.g., 4–6 words, or a numeric/emoji
  short-auth-string in the style of Signal's safety numbers) from the **session key** (§4 of
  `PAIRING_PROTOCOL.md` — the HKDF output both sides already compute identically), not from any
  value transmitted over the relay. Both sides compute it locally from material only they hold
  post-ECDH; the relay never sees the phrase or its inputs.
- **Why it matters:** pairing has no QR step to provide out-of-band binding — the only thing tying
  the two ends together is "both used the same 6-digit code," plus the relay-side protections in
  `SECURITY_ARCHITECTURE.md` §2.2 (key pinning, unconfirmed-code expiry, per-IP rate limiting).
  Those guard against guessing or hijacking the code, but they do not *verify* that the X25519 keys
  each side received via `peer_joined` are the ones the other side actually sent. A verification
  phrase displayed on the Mac and confirmed on the phone (or vice versa) is the out-of-band check
  that those keys weren't substituted by a relay-side or network-path attacker who can see (but,
  per the relay's design, not decrypt) the `peer_joined` exchange.
- **Fail-closed:** pairing must not be considered complete (no credential persisted, no device
  marked trusted in `device_bindings.go`) until the human confirms the phrase matches. A mismatch
  must surface as a hard stop with re-pair instructions, not a warning the user can dismiss.

### 4.2 Revocation — cite the endpoint

`POST /v1/devices/{id}/revoke` (`daemon/push-backend/device_bindings.go:212 handleRevokeDevice`)
is the revocation endpoint the plan's Devices pane (Phase B) wires to. It requires
`requireAuthenticatedUser` and ownership match (`binding.UserID != user.ID` → 404, not 403 — avoids
confirming the ID exists to a non-owner). Revocation is immediate and irreversible (no "undo" —
`RevokedAt` is set and `CredentialHash` is zeroed in the same atomic store update); pairing again
requires a fresh pairing cycle (a new code), not a restore.

---

## 5. App Sandbox tension

**Flag, do not resolve here — verify against current Apple docs during implementation** (the
plan's own "Apple-doc research to do during implementation" section already calls this out).

The threat-relevant trade-off: `Lancer.app` needs to (a) connect to `~/.conduit/conduitd.sock` (or
`~/.lancer/lancerd.sock`) — a Unix-domain socket outside any sandbox container — and (b) read
`~/.conduit`/`~/.lancer` state for diagnostics. The macOS **App Sandbox** restricts both: sandboxed
apps get a container-relative home and need an explicit entitlement
(`com.apple.security.temporary-exception.files.absolute-path.read-write` or similar) to reach
paths outside the container, and Unix-domain-socket access to an arbitrary path is not a
first-class sandboxed capability the way it is for the app's own container socket.

| Option | Security posture | Cost |
|---|---|---|
| **Non-sandboxed, Developer-ID signed + Hardened Runtime + notarized** (what the plan implies by deferring Mac App Store/sandbox to "explicitly deferred") | No sandbox containment for Lancer.app itself; relies on Developer-ID signing + Hardened Runtime + the IPC hardening in §1 as the actual security boundary, same posture as `conduitd` already has | No Mac App Store distribution channel; direct-download/notarized-DMG only |
| Sandboxed + temporary-exception entitlements | Sandbox containment for the rest of the app; entitlement scope must be re-verified against current App Sandbox docs (Apple has tightened temporary-exception entitlement approval over time) — **do not assume this is still grantable for App Store review without checking current Apple documentation first** | Mac App Store eligible, but entitlement approval is not guaranteed and the app would still need broad filesystem reach, undermining most of the sandbox's value |

**Decision recorded by the plan:** non-sandboxed Developer-ID build, Mac App Store explicitly
deferred ("Mac App Store / sandbox build" — plan, "Explicitly deferred (YAGNI)"). This document
flags the resulting trade-off (full sandbox containment is not part of Lancer.app's threat
mitigations) so it's an explicit, recorded decision rather than a default. **Re-verify the current
entitlement/sandbox rules via the `apple-docs` MCP before this ships** — Apple's sandbox and
entitlement policies change across OS versions and this is exactly the kind of claim that must not
be answered from training-data memory (per `CLAUDE.md`'s "Doc lookup" rule).

---

## 6. Uninstall hygiene

### 6.1 Current state (verified against code)

`daemon/conduitd/install.go` has **no corresponding `runUninstall`** in the file as read. There is
no code today that removes the LaunchAgent plist, the installed binary, or `~/.conduit` contents.
Complete uninstall is currently a manual, undocumented process (`launchctl unload` the plist, `rm`
the plist, `rm -rf ~/.conduit`). **This is a gap the plan's Phase A "restart/reinstall/uninstall
service" Diagnostics-pane action must close**, and the test matrix explicitly requires
"complete uninstall" as a verified state.

### 6.2 What a complete uninstall must remove

| Item | Path | Rationale |
|---|---|---|
| LaunchAgent registration | `~/Library/LaunchAgents/dev.conduit.conduitd.plist` (or `SMAppService` unregister call if that registration path was used) | Stops auto-relaunch; `launchctl bootout`/unregister before deleting the plist so launchd doesn't re-read a half-removed entry |
| Installed binary | `~/.conduit/bin/conduitd` (or `~/.lancer/bin/lancerd`) | No orphaned executable left with launchd-adjacent privilege expectations |
| Pairing keys | `~/.conduit/relay-pairing.json` (X25519 private key, `relaypair.go:writeRelayPairing`, mode `0600`) | Private key material — must not survive uninstall, or a reinstall could silently resume trust the user thought they removed |
| Account-device credential | `~/.conduit/account-device.json` (`account_device_pairing.go:writeAccountDeviceCredential`, mode `0600`) | Same rationale — bound credential material |
| Audit log | wherever `audit.go` persists entries (same `~/.conduit` tree) | User data; remove unless the user explicitly chose "export before uninstall" in the Diagnostics flow |
| Approval queue (`queue.json`) | `~/.conduit/queue.json` (`paths.go: queuePath`) | Transient state, no reason to retain |
| Claude PreToolUse hook wiring | `~/.claude/hooks/conduit-hook.sh` (or `lancer-hook.sh`) and the merged entry in `~/.claude/settings.json` (`hook_install.go: mergeClaudeHookEntry`) | Leaving this wired after uninstall means a future `LANCER_GATE=1`/`CONDUIT_GATE=1` invocation calls a binary that's no longer there, or — worse — a *reinstalled* unrelated tool could trip the same env var. Uninstall must unmerge the hook entry, not just leave it dangling |

### 6.3 What is intentionally retained (and must be stated to the user, not silently kept)

- **Nothing by default.** Given the asset list above is entirely secrets/keys/audit/state owned by
  the daemon (no separate "Lancer.app preferences" store is described in the plan beyond UI
  prefs), the safe default is full removal. If a future revision adds Lancer.app-local UI
  preferences (window position, theme), those are the one category that may reasonably survive an
  uninstall that only removes the *service* — but the plan's "Lancer.app owns: UI preferences"
  split (runtime-ownership-map.md) means this is a separate, much lower-stakes deletion decision
  the uninstall flow should still offer (not bundle silently into "leave installed").
- **Recommendation:** the Diagnostics-pane uninstall action should present an explicit checklist
  (LaunchAgent, binary, keys/audit, hook wiring) rather than a single opaque "Uninstall" button, so
  the user can confirm an "export redacted audit bundle first" option (§3.2) before deletion if
  they want a record.

---

## Sources

- This repo: `docs/legal/SECURITY_ARCHITECTURE.md`, `daemon/push-backend/PAIRING_PROTOCOL.md`,
  `daemon/push-backend/websocket_relay.go`, `daemon/push-backend/relay_security.go`,
  `daemon/push-backend/device_bindings.go`, `daemon/conduitd/relaypair.go`,
  `daemon/conduitd/e2e_crypto.go`, `daemon/conduitd/account_device_pairing.go`,
  `daemon/conduitd/install.go`, `daemon/conduitd/resident.go`, `daemon/conduitd/paths.go`,
  `daemon/conduitd/framing.go`, `daemon/conduitd/audit.go`, `daemon/conduitd/hook_install.go`.
- Plan: `~/.claude/plans/you-are-working-on-curried-pixel.md`.
- Apple App Sandbox, Hardened Runtime, Developer ID, and notarization documentation —
  **verify current policy via the `apple-docs` MCP at implementation time**; not re-derived from
  training data here per `CLAUDE.md`'s doc-lookup rule.
