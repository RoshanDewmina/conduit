# ADR: Lancer for Mac — Host Service & Local IPC Architecture

> Companion: `docs/architecture/runtime-ownership-map.md` (item-by-item ownership). Source plan:
> `~/.claude/plans/you-are-working-on-curried-pixel.md`.
>
> **Path note:** this branch (`rebrand/lancer`) has already renamed the Go daemon module to
> `lancer/lancerd`, binary `lancerd`, state dir `~/.lancer`, socket `~/.lancer/lancerd.sock`,
> LaunchAgent label `dev.lancer.lancerd` (verified in `daemon/conduitd/paths.go`, `install.go`,
> `doctor.go` — the source directory is still named `daemon/conduitd/` but the package, binary, and
> on-disk paths are `lancer*`). `runtime-ownership-map.md` was written against the pre-rebrand
> paths (`~/.conduit`, `conduitd.sock`) and is currently stale relative to the working tree; this
> ADR uses verified current paths and should be treated as the correction. The Swift side
> (`Packages/ConduitKit/Sources/ConduitCore/ConduitDProtocol.swift`) has **not** been renamed —
> per the plan, "Lancer" stays a user-facing label only; internal Swift identifiers remain `Conduit*`.

## 1. Context

Lancer (user-facing name; internal code/bundle IDs stay `Conduit`/`dev.conduit.*` on the Swift side,
`lancer/lancerd` on the now-rebranded Go side) is an iPhone control plane for coding agents (Claude
Code, Codex, OpenCode, Kimi) running on the user's own Mac or servers. The phone steers and approves
work; the heavy lifting — spawning agent processes, owning PTYs, holding the policy/approval engine,
talking to the E2E relay — already happens in a Go background daemon (`lancerd`, source at
`daemon/conduitd/`).

Today the only way to install, pair, and diagnose the host side is the `lancerd` CLI itself
(`lancerd install`, `lancerd pair`, `lancerd doctor`) — there is no GUI. We want **`Lancer.app`**: a
native macOS menu-bar + management front-end that makes install, pairing, agent/device visibility,
and diagnostics easy.

**The core requirement that shapes every option below: don't replace the reliable background
runtime that already exists.** `lancerd` today:

- Installs itself as a per-user LaunchAgent (`installLaunchd`, `daemon/conduitd/install.go:84-114`)
  at `~/Library/LaunchAgents/dev.lancer.lancerd.plist` with `RunAtLoad` + `KeepAlive` (so launchd
  restarts it on crash and at login) — confirmed in the plist template at `install.go:89-104`.
- Binds exactly one Unix socket, `~/.lancer/lancerd.sock` (`paths.go:9,32-38`), and the bind itself
  (`net.Listen("unix", sockPath)`, `resident.go:64-68`) is the single-instance guarantee: a second
  `lancerd daemon` invocation fails to bind and exits — no separate lock file.
- Speaks a length-prefixed JSON-RPC framing over that socket — 4-byte big-endian `uint32` length
  prefix, payload, 16 MiB cap (`maxFrameBytes`, `server.go:20`; `framing.go`) — for the `attach`
  client (today: the CLI's interactive session / the relay router), plus an **unframed**,
  newline-JSON request/response variant used by the PreToolUse hook script (`hook.go:57-74`,
  `installClaudeHook`/`hook_install.go`).
- Runs entirely as the logged-in user, non-root, and persists all state under `~/.lancer/`
  (sessions, policy, secrets, audit log, relay pairing, queue) — never in a system location.
- Has an existing headless path on Linux via a `systemd --user` unit (`installSystemd`,
  `install.go:116-144`) with `Restart=always`. Any Mac-only architectural choice that can't be
  mirrored on Linux breaks symmetry the product depends on (the same `lancerd` binary runs on a
  homelab box with no GUI at all).

Today the Unix socket has **no version handshake, no peer-credential check, and no auth token** —
any local process that can open the socket can speak the full protocol (`attachHello` is just
`{"op":"attach"}`, `framing.go:36-47`; `resident.handleConnection`, `resident.go:91-110`, performs
no credential check before parsing the first message). That gap is real but orthogonal to the
*architecture* choice below — it is closed by hardening the existing socket, not by picking a
different transport (see §4, Decision).

## 2. Options evaluated

1. **GUI app owns the runtime.** `Lancer.app` itself spawns and owns agent processes, PTYs, the
   policy engine, and the relay client in-process (Swift). No daemon.
2. **App-bundled per-user LaunchAgent.** Keep a background service, but make it a *new* Swift
   process (`LancerHostService`) bundled inside `Lancer.app`, installed as its own LaunchAgent.
3. **Login-item helper app.** A lightweight Swift helper registered via `SMLoginItemSetEnabled` /
   `SMAppService.loginItem`, launched at login alongside `Lancer.app`, holding the runtime.
4. **App-bundled XPC service.** A Swift XPC service (`SMAppService.agent` with an XPC
   `MachServices` entry, or a classic `NSXPCConnection`-vended helper) inside `Lancer.app`'s bundle,
   talking Mach IPC instead of a socket.
5. **System LaunchDaemon (root).** Install the host service as a root `LaunchDaemon`
   (`/Library/LaunchDaemons/`), running before login, independent of any logged-in user.
6. **Keep the current daemon installed independently.** Treat `Lancer.app` as a pure UI shell with
   *no* lifecycle responsibility — the user still runs `lancerd install` from a terminal; the app
   only attaches to whatever is already running.
7. **Hybrid: portable Host Service managed by the Mac app (CHOSEN).** Keep `lancerd` exactly as it
   is — unchanged in role, unchanged language, unchanged platform story (macOS LaunchAgent +
   `systemd --user` on Linux). `Lancer.app` becomes a native SwiftUI **manager + client**: it
   installs/starts/stops/restarts `lancerd`'s LaunchAgent (via `SMAppService`, the current Apple-
   recommended registration API, falling back to direct `launchctl`/plist management of the
   existing plist when `SMAppService` is unavailable), and talks to it over the **existing** Unix
   socket — hardened with a versioned handshake, a peer-UID check, and a per-user token. This
   option is **already substantially realized**: the daemon side of the contract (LaunchAgent,
   single socket, JSON-RPC framing, non-root, `~/.lancer/` state, Linux parity) exists today and
   needs no redesign, only the IPC-hardening addition.

## 3. Comparison

Legend: ✅ strong · ⚠️ partial / needs extra work · ❌ fails / violates a hard constraint.

| Criterion | (1) GUI owns runtime | (2) Bundled LaunchAgent (new Swift svc) | (3) Login-item helper | (4) Bundled XPC | (5) Root LaunchDaemon | (6) Independent daemon, no app lifecycle | (7) Hybrid: chosen |
|---|---|---|---|---|---|---|---|
| Survives UI quit/crash | ❌ runtime dies with the app | ✅ | ✅ | ✅ (XPC service is launchd-managed too) | ✅ | ✅ (already true today) | ✅ (already true today) |
| Long PTY/agent sessions across UI lifecycle | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Relay persistence (E2E phone link stays up) | ❌ dies on quit | ✅ but **duplicate** relay-owning process vs. `lancerd` unless `lancerd` is deleted, which throws away a working implementation | ✅ same duplication problem | ✅ same duplication problem | ✅ but see least-privilege | ✅ | ✅ — relay ownership stays exactly where it is |
| User-home / CLI access (spawn `claude`/`codex`/etc., read repo files) | ✅ runs as user | ✅ | ✅ | ⚠️ XPC services historically run with a constrained, sandboxed-by-default environment; reaching arbitrary `$HOME` paths and inheriting the user's shell PATH for CLI discovery is more friction than a plain process | ❌ root daemon spawning user CLIs as root is a privilege/ownership mismatch (files end up root-owned, breaks `gh`/agent CLI auth stored under the user) | ✅ (unchanged) | ✅ (unchanged) |
| Least privilege | ⚠️ app process now needs every entitlement the runtime needs | ⚠️ same privilege surface, just relocated into a second binary | ⚠️ same | ⚠️ same, plus Mach service registration surface | ❌ root for a feature that needs none | ✅ | ✅ |
| No-root | ✅ | ✅ | ✅ | ✅ | ❌ violates explicitly | ✅ | ✅ |
| Secure local IPC | N/A (in-process, no IPC) | needs same hardening work as (7) | needs same hardening work | Mach IPC has OS-level sender-validation primitives, but **a Go process cannot vend or consume `NSXPCConnection`/`MachServices` natively** — would require a Swift sidecar shim purely to bridge XPC↔socket, adding a process for no security benefit over hardening the socket directly | needs same hardening work | none today (gap is real, independent of this decision) | needs hardening (handshake + peer-UID + token) — **planned, scoped, additive** |
| Updates / version compatibility | one binary, no skew possible, but loses everything else | two binaries to keep in lockstep across every release | two binaries to keep in lockstep | two-to-three binaries (app, XPC service, possible bridge) to keep in lockstep | one daemon binary, but a root-owned update path is higher blast-radius | unconstrained skew (user controls daemon version independently) — same risk as (7) but with worse UX | same skew risk as (6), mitigated by a version handshake (`{protocolVersion, serviceVersion}`) the app can detect and warn on |
| Sleep/wake recovery | app must re-establish everything it owned | launchd `KeepAlive` already covers this for the daemon process; new Swift service inherits it | `SMAppService.loginItem` has weaker wake guarantees than an `agent` service | XPC service activation-on-demand handles this differently (lazy-launch on connection, not always-resident) — workable but a behavior change from "always running" | covered, but irrelevant since rejected on (5) | already proven (existing `lancerd` behavior) | already proven |
| Network changes (Wi-Fi/VPN flap) | app-local handling only | duplicated logic if two processes both watch network state | duplicated | duplicated | duplicated, and now privileged | `lancerd`'s relay client already handles reconnect | unchanged — `lancerd`'s relay client already handles reconnect |
| Multiple users on one Mac | per-user runtime each time app runs (fragile) | per-user if LaunchAgent, but doubles every other row's problems | per-user | per-user | ❌ one root daemon, ambiguous per-user session ownership | ✅ already per-user (`~/Library/LaunchAgents`, `~/.lancer`) | ✅ already per-user |
| Headless Linux + macOS parity | ❌ Swift/AppKit-only, no Linux story at all | ❌ same — a new Swift service is macOS-only, so Linux needs a second, divergent implementation maintained forever | ❌ same | ❌ same, and XPC is Apple-only, doubling the divergence | ❌ same, plus root | ✅ `lancerd` already runs identically (`systemd --user`) | ✅ `lancerd` already runs identically |
| Existing-state migration | ❌ nothing to migrate *to* without first throwing away `~/.lancer/` state and re-implementing it in Swift | ⚠️ requires a one-time migration of `~/.lancer/` (sessions, secrets, audit, policy, relay keys) into whatever the new Swift service expects | ⚠️ same | ⚠️ same | ⚠️ same, plus a privilege-escalation migration | ✅ nothing to migrate — same daemon, same `~/.lancer/` | ✅ nothing to migrate |
| Debuggability | single process, but now conflates UI bugs with runtime bugs | two independent log streams/binaries to correlate | two | three (app/XPC/bridge) with Mach IPC being harder to inspect than a plain socket | two, plus needing root to inspect/restart | `lancerd doctor` already exists and is comprehensive (`daemon/conduitd/doctor.go:71-87`: version, state-dir, binary, policy, socket reachability, agent CLIs, python3, hook wiring, audit log, queue, OS/arch, relay pairing, shim wrapper) | same `doctor` reused as-is, surfaced in the app's Diagnostics pane |
| Uninstall | trivial (one app) but loses session continuity entirely while running | must remove two LaunchAgents/binaries cleanly | must remove login item + binary | must remove app + XPC service registration | requires `sudo` to unload/remove — worse UX, and a forgotten root daemon is a lingering attack surface | already a single, well-understood removal (`launchctl unload` + delete plist + binary + `~/.lancer/`) | same single, well-understood removal, orchestrated by the app instead of manual `launchctl` |
| Distribution / notarization | simplest (one bundle) but the wrong tradeoff given every row above | app + helper both need signing/notarization, embedded-helper validation rules (`SMAppService` is strict about helper-tool bundling and code-signing match) add real Phase-C risk | same embedded-helper signing rules apply, with weaker lifecycle guarantees in exchange for no benefit | same signing rules, plus XPC service bundling rules (`MachServices` keys, sandbox profile) — more moving parts to get through notarization | a privileged installer (root daemon) typically needs a separate signed pkg/installer flow — meaningfully more distribution work | simplest from the app's side (nothing to bundle) but worse first-run UX (terminal step required) | one app bundle to notarize; the daemon binary it manages already exists and is unaffected by the app's signing |
| Maintenance cost | rewrite + maintain a second runtime forever | maintain two runtimes (Swift duplicate of working Go logic) forever, plus Linux divergence | maintain two runtimes, weaker lifecycle | maintain up to three components | maintain a privileged component most users don't need | maintain only the UI, but ships a worse product (no GUI install/lifecycle) | maintain only the UI + a small, additive IPC-hardening patch to the existing daemon |

## 4. Decision

**Adopt option 7.** Keep `lancerd` (source: `daemon/conduitd/`) as the Host Service, unchanged in
role, language, and platform story. `Lancer.app` is a native SwiftUI menu-bar + management
front-end that:

- Manages `lancerd`'s LaunchAgent lifecycle via `SMAppService` (the current Apple-recommended
  agent-registration API), falling back to direct management of the existing
  `~/Library/LaunchAgents/dev.lancer.lancerd.plist` (written today by `installLaunchd`,
  `install.go:84-114`) when `SMAppService` registration isn't viable.
- Talks to `lancerd` over the existing `~/.lancer/lancerd.sock`, using the existing length-prefixed
  JSON-RPC framing, **hardened with**: a version handshake RPC (`{protocolVersion, serviceVersion}`)
  so app and daemon can detect skew before assuming a shared API surface; a peer-credential check
  (`SO_PEERCRED`/`LOCAL_PEERCRED` equivalent — `getsockopt`/`getpeereid` on Unix-domain sockets) so
  the daemon can refuse connections from a different UID; and a per-user token file
  (`~/.lancer/ipc-token`, mode `0600`) gating non-hook control clients, so a connection alone isn't
  sufficient authorization. None of this requires a new transport — it's an additive patch to
  `resident.handleConnection` and the `attach` path.
- Adds no new always-running process, no new language runtime, no new platform-specific service.

This is not a green-field design — it is the **recognition that the Host-Service requirements the
spec cares about (survival on quit/crash, long-running PTYs, relay persistence, least privilege,
no-root, per-user isolation, Linux parity, existing-state continuity) are already met by `lancerd`
today.** The only real gap is IPC hardening, which is additive and orthogonal to every other row in
§3.

### Why each rejected option loses

**(1) GUI app owns the runtime.** Fails the one requirement stated up front: a SwiftUI app's
process model means quitting or crashing the UI kills every agent session, every PTY, and the relay
connection to the phone. This is the opposite of what a "mission control" product needs — the
entire value proposition is that the phone can disconnect and reconnect to *durable* work. It also
means rewriting, in Swift, everything `lancerd` already does correctly (dispatch, policy, approvals,
relay, audit) — a total rewrite of working, tested Go code for a strictly worse failure mode.

**(2) App-bundled per-user LaunchAgent (new Swift service).** Solves survival, but at the cost of
maintaining a second, parallel implementation of everything `lancerd` already does — and that
duplicate would be macOS-only, immediately breaking the headless-Linux story the product depends on
(the same binary running on a homelab box via `systemd --user`, `install.go:116-144`). Every
existing `~/.lancer/` state (sessions, secrets, audit log hash chain, policy YAML, relay keypair)
would need a one-time migration into whatever format the new Swift service expects, for zero
functional gain over hardening the daemon that already owns that state correctly.

**(3) Login-item helper app.** Same duplication and Linux-divergence problems as (2), with a
*weaker* lifecycle guarantee: `SMLoginItemSetEnabled`/login-item registration is oriented around
"launch at login," not "always resident with `KeepAlive`-style crash recovery," so it's a regression
in survival semantics versus what `launchd`'s `RunAtLoad`+`KeepAlive` already gives `lancerd` today.

**(4) App-bundled XPC service.** XPC is a real local-IPC primitive with good sender-validation
properties, but `lancerd` is a Go process — Go cannot vend `NSXPCConnection`/`MachServices` natively.
Adopting XPC would force a Swift sidecar purely to bridge XPC↔Unix-socket, adding a fourth component
(app, XPC service, bridge, daemon) for a security property (peer validation) that a peer-credential
check on the existing socket gets for free, with zero new processes. XPC also does nothing for the
headless-Linux deployment — Mach services are Apple-only, so Linux would need an entirely separate
IPC story, permanently diverging from macOS instead of sharing one daemon and one protocol.

**(5) System LaunchDaemon (root).** Violates no-root and least-privilege outright. A root daemon
spawning user-owned CLI tools (`claude`, `codex`, `opencode`) as root corrupts file ownership in the
user's own repos and breaks every CLI's own user-scoped auth/config (e.g., `gh auth status`, doctor
check at `doctor.go`). It also requires a privileged installer flow for what is fundamentally a
per-user feature, and makes "forgot to uninstall" a standing root-level attack surface instead of a
per-user one. Nothing in the product needs pre-login or multi-user-shared behavior.

**(6) Keep the current daemon installed independently (no app lifecycle).** This is the status quo
minus the entire reason to build `Lancer.app`. It correctly avoids inventing a new runtime, but
abandons the actual goal — making install, pairing, and diagnostics a GUI experience instead of a
terminal chore. It's the right *runtime* answer and the wrong *product* answer; option 7 keeps its
runtime correctness and adds the missing management layer on top.

## 5. Consequences

**What we build:**
- `Lancer.app` (new SwiftUI app target) — `SMAppService`-based lifecycle management (install,
  start, stop, restart, detect/adopt an existing standalone `lancerd` install, uninstall) plus a
  menu-bar/management UI that renders state read through IPC.
- A thin new Swift package target (`HostControlKit` per the plan) implementing the *client* side of
  the hardened socket protocol, reusing `ConduitCore/ConduitDProtocol.swift`'s existing framing and
  models.
- Additive, versioned changes to `lancerd`: a `hello`/handshake RPC, a peer-UID check, a per-user
  token file, and — since the daemon's `attach` slot is currently single-client
  (`resident.serveAttach` rejects a second connection, `resident.go:132-139`) — either a lightweight
  multiplexed control channel or per-request connections so the Mac app can be a concurrent control
  client without locking out the existing attach use (e.g., the relay router or a CLI session).

**What we explicitly do not build:** a Swift `LancerHostService`/`LancerHostCore`; an XPC service or
XPC↔socket bridge; a root `LaunchDaemon`; any second implementation of session/PTY/policy/relay/audit
ownership. `lancerd` remains the single owner of all runtime state (full breakdown in
`runtime-ownership-map.md`); `Lancer.app` is a stateless client that reconstructs everything it shows
from `lancerd` on every launch and never caches runtime state as truth.

**Residual risk carried forward, not solved by this ADR:** the socket today has zero auth — this is
accepted as a known, scoped gap closed by the handshake/peer-UID/token work in Phase A/C of the
implementation plan, not by re-litigating the transport choice above.
