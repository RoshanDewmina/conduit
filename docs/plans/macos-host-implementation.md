# Lancer for Mac — Implementation Plan

> Living engineering doc. Source design: `~/.claude/plans/you-are-working-on-curried-pixel.md`
> (architecture decisions + staged phases). This file is the polished, execution-ready version:
> ordered tasks, acceptance criteria, research checklist, test matrix, verification gates.
> Update this file as Phase A/B/C land — it is the authoritative plan, not a snapshot.

## 0. Ground truth (verified against current code, 2026-06-21)

The rebrand from "Conduit" → "Lancer" is **already complete** in the artifacts this plan touches.
Use these names, not the ones in the original design note:

| Item | Actual current value |
|---|---|
| Daemon binary | `lancerd` (package dir is still `daemon/conduitd/`, binary name is `lancerd`) |
| State dir | `~/.lancer/` (`daemon/conduitd/paths.go:lancerDir()`, override via `LANCER_STATE_DIR`) |
| Socket | `~/.lancer/lancerd.sock` (`paths.go:socketFileName = "lancerd.sock"`) |
| LaunchAgent | `~/Library/LaunchAgents/dev.lancer.lancerd.plist`, label `dev.lancer.lancerd`, `RunAtLoad`+`KeepAlive` (`install.go:installLaunchd`) |
| Swift package | directory `Packages/ConduitKit/`, but `Package.swift` declares `name: "LancerKit"`; core engine product is `LancerCore` (target dir still `Sources/ConduitCore/`) |
| iOS app / project.yml | `name: Lancer`, bundle prefix `dev.lancer`, app target `Lancer`, XcodeGen-driven |
| Pairing | `lancerd pair` (no separate "QR" subcommand) generates an X25519 keypair + pairing code, prints a `qrPairingPayload{V, Relay, Code, Pub}` to stderr (`relay_install_helper.go:printRelayInstructions`) |
| Doctor | `lancerd doctor` → `collectDoctorResults` runs ~14 named checks (`checkResidentDaemon`, `checkRelayPairing`, `checkHooks`, `checkAuditLog`, `checkAgentCLIs`, `checkOSArch`, etc.) in `doctor.go` |
| Concurrency model today | One stdio `attach` client per `lancerd serve` process (relays length-prefixed JSON-RPC over stdin/stdout ↔ the resident daemon's Unix socket) **plus** unlimited concurrent raw hook connections via `handleHook` on the same socket listener. There is no existing peer-cred or token check on the socket — any local process that can open `~/.lancer/lancerd.sock` can dial it today. |

**Implication for this plan:** all file paths, identifiers, and plist content below use the
*current* names (`lancerd`, `~/.lancer/`, `dev.lancer.lancerd`, `LancerCore`). Do not reintroduce
`conduitd`/`~/.conduit/`/`dev.conduit.conduitd` — those are stale.

---

## 1. Architecture

```
                          ┌─────────────────────────────────────────────┐
                          │              Lancer.app (macOS)              │
                          │  SwiftUI · macOS 15+ deployment target ·     │
                          │  built with macOS 27 / Xcode 27 toolchain    │
                          │                                               │
                          │  MenuBarExtra ──┐                            │
                          │  Window/Settings ├─ HostControlKit client ───┼──┐
                          │  scenes          │  (handshake, auth, RPC)   │  │
                          └───────────────────────────────────────────────┘  │
                                   │ manages lifecycle via                   │
                                   │ SMAppService.agent (preferred)           │ hardened
                                   │ falls back to launchctl bootstrap        │ JSON-RPC
                                   ▼ of the existing plist                    │ over
                          ~/Library/LaunchAgents/                            │ Unix
                          dev.lancer.lancerd.plist                           │ socket
                          (RunAtLoad + KeepAlive, unchanged)                 │
                                   │                                         │
                                   ▼                                         ▼
                          ┌─────────────────────────────────────────────────────┐
                          │                  lancerd (Go, unchanged role)        │
                          │  ~/.lancer/lancerd.sock  (hello handshake + peer-UID │
                          │  check + ~/.lancer/ipc-token, 0600)                  │
                          │  owns: sessions, PTYs, agent adapters, policy,       │
                          │  approvals, audit, secrets, device identity,         │
                          │  pairing keys, provider usage                        │
                          └─────────────────────────────────────────────────────┘
                                   │
                                   ▼
                          E2E relay (blind, ChaCha20-Poly1305, unchanged)
                                   │
                                   ▼
                              iPhone (Lancer iOS app)
```

**Invariants:**
- The phone connects to `lancerd` (directly or via the relay) — **never** to Lancer.app. Lancer.app
  has no listening socket of its own and no relay/Push role.
- Lancer.app is a **stateless client**: on every launch it reconstructs UI state by querying
  `lancerd` over the socket. It never becomes a second source of truth for sessions, policy,
  secrets, or device identity.
- Quitting or crashing Lancer.app **never** stops `lancerd`. `SMAppService`/launchd owns the
  daemon's lifecycle independent of the UI process.
- `lancerd`'s role does not change. This plan adds an **auth/versioning layer** to the existing
  socket and (if needed) a way to serve multiple concurrent control clients — it does not rewrite
  the daemon's ownership model.

---

## 2. Code structure

### 2.1 `HostControlKit` — new Swift package target (`Packages/ConduitKit/`)

Thin macOS-side client of the hardened socket protocol. Lives alongside `LancerCore` in the same
package (`Package.swift` already declares `.macOS(.v15)` for the whole package — confirmed in
§0). New product + target:

```swift
.library(name: "HostControlKit", targets: ["HostControlKit"]),
...
.target(
    name: "HostControlKit",
    dependencies: ["LancerCore"],   // reuses ConduitDProtocol.swift framing + models
    swiftSettings: swiftSettings
),
```

Scope — **only** what Phase A/B need, nothing speculative:
- `HostConnection` — owns the `Socket`/`NWConnection` (or raw POSIX socket) to
  `~/.lancer/lancerd.sock`, using `DaemonFraming.frame`/`unframe` from
  `Sources/ConduitCore/ConduitDProtocol.swift` for the 4-byte length-prefixed JSON framing already
  used by `lancerd serve`'s attach relay.
- `HostHandshake` — sends the new `hello` RPC (see §2.2), validates `protocolVersion` compat,
  reads/writes the `~/.lancer/ipc-token` file for per-user auth.
- `HostControlClient` — request/response RPC calls (`agent.doctor`, `agent.host.health`,
  `agent.status`, `agent.policy.get`, future Devices/Security calls) + a subscribe-to-events stream
  for the Overview pane (reusing `DaemonEvent.decode`/`DaemonRPCResponse.decode` already defined
  in `ConduitDProtocol.swift` — do not duplicate those decoders).
- `LaunchAgentController` — wraps `SMAppService.agent(plistName:)` registration/status/unregister,
  with a fallback path that shells `launchctl bootstrap`/`launchctl print` against the *existing*
  `dev.lancer.lancerd.plist` when `SMAppService` reports `.notFound` (e.g., a standalone CLI
  install that predates Lancer.app).

This is the **only substantial new Swift code** in Phase A. Everything else (design tokens,
engines) is reused as-is per the locked decision in the design note.

### 2.2 `lancerd` (Go) — additive, versioned changes

All changes are additive RPCs/checks on the existing socket; no existing RPC's wire shape changes.

1. **`hello` handshake RPC.**
   - Request: `{"method":"hello","id":...,"params":{"clientName":"Lancer.app","clientVersion":"…"}}`.
   - Response: `{"result":{"protocolVersion":<int>,"serviceVersion":"<lancerd build version>"}}`.
   - `protocolVersion` is a new monotonically-increasing int constant in the daemon (start at `1`);
     `HostControlKit` refuses to proceed (surfaces "update Lancer.app" / "update lancerd" in UI) on
     a version it doesn't recognize, rather than guessing wire shape.
   - Add the mirror `HelloResult: Codable` to `ConduitDProtocol.swift` next to the existing
     `DaemonRPCResponse` cases (extend the `decode` switch, do not branch elsewhere).

2. **Peer-credential check + per-user token.**
   - On `net.Listen("unix", sockPath)`, after `Accept()`, read the peer credential via
     `golang.org/x/sys/unix.GetsockoptUcred(fd, SOL_SOCKET, SO_PEERCRED)` (Linux) — macOS has no
     `SO_PEERCRED`; use `LOCAL_PEERCRED` (`unix.GetsockoptXucred` / `LOCAL_PEERCRED` via the
     `xucred` struct) instead. Wrap both behind a small `peerUID(conn) (uid int, ok bool)` helper
     with a `//go:build darwin` and `//go:build linux` pair so the daemon keeps building headless
     on Linux (AGENTS.md requirement) — reject the connection only when peer UID is resolvable and
     mismatches `os.Getuid()`; if peer-cred is unavailable on a platform, fall back to token-only
     auth rather than failing closed on every connection (document this explicitly — it is a
     conscious degradation, not a bug).
   - Per-user token: on first daemon start, write `~/.lancer/ipc-token` (random 32 bytes,
     base64url, mode `0600`) if absent. Non-hook clients (i.e., anything that isn't the existing
     bare `handleHook` PreToolUse path, which must keep working unauthenticated for the agent-CLI
     hook scripts already deployed) must present this token in `hello.params.token` or be
     rejected with a typed error the UI can render ("Lancer.app needs to be paired with this
     Mac's lancerd — reinstall or run `lancerd doctor`").
   - This must not break `docs/conduit-hook.sh` or the agent-CLI PreToolUse hook path
     (`installClaudeHook`/`handleHook`) — those stay on the existing unauthenticated raw-JSON
     framing on the same socket, distinguished by the existing `readFirstMessage`/`framed` check
     in `runServeLegacy`'s accept loop. Hook traffic and control traffic are different message
     shapes on the same socket; the auth gate applies only to framed JSON-RPC `hello`/methods, not
     to the unframed hook JSON.

3. **Concurrent control clients without breaking single-`attach`.**
   - Current model: one stdio `attach` relay per `lancerd serve` invocation (used by the SSH
     control path), unlimited concurrent hook connections. Lancer.app needs to be a *second*,
     independent, long-lived control client (for the menu-bar's live health/status) without
     stealing the existing `attach` slot the SSH/phone-relay path relies on.
   - **Recommended approach: per-request connections**, not a new persistent "second attach". Each
     `HostControlClient` call from `HostControlKit` opens a short-lived connection, sends `hello` +
     one RPC, reads one response, closes. This requires zero change to the existing single-attach
     invariant — it reuses the same `handleHookWithNotify`-adjacent accept loop, just for framed
     RPC instead of unframed hook JSON, gated by the new `hello`/token check in (2).
   - **For the menu-bar's live status** (needs server-push, not poll): add one *narrow* persistent
     subscribe channel — a `hello{ "subscribe": true }` connection that the daemon treats as a
     read-only event tap (mirrors `DaemonEvent` broadcasts already emitted for the phone relay,
     e.g. `agent.status`, `agent.host.health` on change) and **never** accepts RPC requests on. This
     is additive and architecturally distinct from the mutating `attach` stdio relay — it cannot
     deadlock or contend with it. Avoid building a generic multiplexed channel; this one-purpose
     read-only tap is the minimum that satisfies "live health in the menu bar" (YAGNI per
     AGENTS.md §3).
   - Acceptance: with Lancer.app's menu bar subscribed AND a phone attached via relay AND an SSH
     `lancerd serve` attach all running concurrently, none of the three observably blocks or starves
     another (verified in Phase C's test matrix).

### 2.3 `LancerMac` — new app target

**Decision deferred to Phase A scaffolding**, per the design note — choose between:
- (a) a new `application`/macOS target block in the existing `project.yml` (XcodeGen), sharing the
  `LancerKit` package dependency the iOS `Lancer` target already uses, or
- (b) a sibling Xcode project/package driven independently.

Default to (a) unless XcodeGen's per-target platform handling proves awkward for a `MenuBarExtra`
+ `Settings` scene combo target — *check this empirically* before committing; don't decide on
paper. Either way: new target depends on `HostControlKit` + `DesignSystem` (+ whatever subset of
existing Features the Overview/Diagnostics/Devices/Security panes reuse — start with none and add
only on real need, since most Features are iOS-shaped UI, not engines).

### 2.4 Explicitly deferred (do not build in this plan's scope)

Swift `LancerHostService` / `LancerHostCore` / `LancerHostProtocol` / `LancerSecurity` (the role is
already covered by `lancerd` + reused `LancerKit` engines) · `lancerctl` CLI (no proven gap over
`lancerd doctor`/`lancerd pair`) · Sparkle/auto-update (ship a manual signed-update path first) ·
Mac terminal / file browser / full approval inbox / full transcripts · Mac App Store / sandboxed
build.

---

## 3. Phases

### Phase A — Vertical slice (first reviewable build)

Goal: a Mac can install, pair, and see live daemon health from a native UI, with zero regression
to the existing CLI/iOS flows.

**Tasks:**
1. Decide + scaffold `LancerMac` target per §2.3; wire `LancerKit`'s `DesignSystem` tokens; confirm
   light/dark render with no content yet (empty window + menu-bar icon).
2. Add `HostControlKit` package target (§2.1) with `HostConnection` + `DaemonFraming` reuse; unit
   test framing round-trip independent of a live daemon.
3. Implement `hello` RPC in `lancerd` (§2.2.1) + mirror types in `ConduitDProtocol.swift`; `go test
   ./...` covers version-match / version-mismatch / malformed-hello.
4. Implement peer-UID check + `~/.lancer/ipc-token` (§2.2.2), darwin-only `LOCAL_PEERCRED` path
   first (this is the Mac app's platform); confirm the existing hook path
   (`docs/conduit-hook.sh`, `handleHook`) is unaffected by running the daemon's existing test
   suite plus a manual `lancerd agent-hook` smoke call.
5. `LaunchAgentController`: `SMAppService.agent` registration against the **existing**
   `dev.lancer.lancerd.plist`/binary (don't have the app write a new plist — adopt the one
   `lancerd install` already writes, matching the design note's "detect existing standalone
   install, don't clobber `~/.lancer/`"). Cover: not-installed → install offered; installed via CLI
   → adopted; installed via `SMAppService` → status/start/stop/restart all work.
6. Menu-bar (`MenuBarExtra`): health dot (subscribe-tap from §2.2.3), direct/relay status, active
   session count, needs-attention count, and actions: Open Management, Pair, Pause All, Emergency
   Stop, Diagnostics, Quit UI. **Quit UI must not call any stop-service path** — wire it to
   `NSApplication.terminate` only; "stop service" is a separate confirmed action elsewhere.
7. Management window — **Overview** pane (daemon version/protocolVersion, install state, relay/
   direct/push health individually, last-seen phone) and **Diagnostics** pane (run `lancerd doctor`
   via RPC if exposed, else shell it; render the same checks `doctor.go` already defines;
   restart/reinstall/uninstall service buttons; export redacted bundle reusing whatever audit-export
   RPC already exists — `agent.audit.export` per `server.go`).
8. Pairing reuse: drive `lancerd pair`'s existing `qrPairingPayload` (relay, code, pub key) and
   render it as a QR + 6-digit fallback in-app, instead of a terminal-printed QR. Do not reimplement
   the X25519/keypair logic — call the daemon for it (add a thin RPC wrapper around
   `generatePairingCode`/`generateKeyPair` if no RPC equivalent exists yet; check before assuming).

**Acceptance (Phase A "done"):**
- Fresh Mac with no prior install: Lancer.app installs the LaunchAgent, daemon starts, menu bar
  shows healthy state, Overview/Diagnostics panes populate from real `lancerd doctor`/`hello` data.
- Mac with a pre-existing CLI-only `lancerd` install: Lancer.app detects it via `SMAppService`
  status / plist presence, adopts it, does **not** touch `~/.lancer/` contents.
- Pair via in-app QR succeeds against a real iPhone running the current Lancer iOS app (no iOS
  changes needed — relay/pairing wire format is unchanged).
- Quit Lancer.app (`⌘Q` and force-quit) while an agent session is active on the phone: session
  continues uninterrupted (phone↔daemon path never routed through the Mac app).
- `cd Packages/ConduitKit && swift build && swift test` green; `XcodeBuildMCP build_macos` green for
  `LancerMac`; `go test ./...` green from `daemon/conduitd`; existing iOS `Lancer` app-target build
  unaffected.

### Phase B — Setup, discovery, remaining panes

**Tasks:**
1. Full first-run flow: welcome → readiness check (existing `checkOSArch`/`checkAgentCLIs`-style
   checks surfaced one by one) → agent discovery → existing-daemon migration prompt (if Phase A's
   adoption path detects a CLI-only install) → install → permissions (Full Disk Access if needed
   for workspace roots outside sandboxable paths — confirm during Apple-doc research, §4) →
   workspace roots picker → machine name → pairing QR → mutual verification phrase (reuse whatever
   the iOS app already shows here — check `OnboardingFeature`) → direct connectivity test → relay
   test → push test → E2E control test (dispatch a trivial no-op through to confirm round-trip) →
   done. Each step shows its **real** pass/fail, not a static checklist.
2. **Agents & Workspaces pane**: detected CLI versions/auth/adapter health via `agent.status` +
   `agent.doctor`-equivalent (`checkAgentCLIs`); list/add/remove workspace roots; default shell;
   manual re-scan action. Cross-check against `vendor-cli-adapter-audit` skill expectations before
   wiring — adapter detection drifts (see `.claude/rules/go-daemon.md`).
3. **Devices pane**: paired devices, fingerprint, paired-at/last-seen, revoke, pair-another, rotate
   identity. Wire to whatever device-binding/revoke RPCs already exist server-side
   (`lancer.device.register`, `lancer.device.register.apns`/`.activity` in `server.go`) — extend
   only if a revoke/list RPC is genuinely missing, don't assume.
4. **Security pane**: effective autonomy/policy summary (`agent.policy.get`), secret-storage health
   (`agent.secret.list`), relay/E2E explanation (static copy + live relay-paired status), audit
   state (`agent.audit.tail`/`agent.audit.verify`), explicit typed-confirmation for any sensitive
   change (mirrors the IBKR-style "never automate a destructive action" posture this user already
   holds elsewhere — applies here as "never silently rotate keys or revoke a device").

**Acceptance:** a brand-new Mac can go from "never installed" to "paired + agents discovered +
workspace configured + security reviewed" entirely inside Lancer.app, with each first-run step
showing a real (not simulated) result. Devices/Security panes reflect live daemon state, not cached
UI state, after a daemon restart.

### Phase C — Hardening, tests, distribution

**Tasks:**
1. IPC auth/version-mismatch handling end-to-end: stale Lancer.app vs. newer `lancerd` and vice
   versa both produce a specific, actionable UI message (not a generic error). Duplicate-service
   prevention: launching a second Lancer.app instance reuses the running one's window
   (`NSApplication` single-instance) rather than creating a second LaunchAgent manager.
2. Full automated test matrix (§5).
3. Developer-ID signing + Hardened Runtime + notarization runbook (write as a runnable checklist:
   `codesign --options runtime`, entitlements needed for Unix-socket + `~/.lancer/` access,
   `xcrun notarytool submit`, `xcrun stapler staple`, verify with `spctl -a -vv`). **No Sparkle** —
   document the manual signed-update path (new signed `.dmg`/`.zip`, user re-downloads); evaluate
   Sparkle's helper-update model against the SMAppService-managed LaunchAgent before adopting later.
4. Light/dark labelled screenshots of every meaningful state (menu bar idle/active/needs-attention,
   Overview, Diagnostics pass/fail, first-run steps, Devices, Security) via `XcodeBuildMCP screenshot`.
5. Update `CLAUDE.md` + `ARCHITECTURE.md` (§0.1 current-state snapshot gains a Lancer.app row;
   §4.1 navigation doc gains a one-line pointer to this plan for the Mac surface). Remove/archive
   superseded docs only after `grep -r` confirms no remaining references.

**Acceptance:** full test matrix green; signed+notarized build passes `spctl` Gatekeeper assessment
on a clean Mac with no prior trust; screenshots captured for both appearances; docs updated.

---

## 4. Apple-doc research checklist (primary sources via `apple-docs` MCP — do before writing the
   corresponding code, not after)

- `MenuBarExtra` — style options (`.window` vs `.menu`), `MenuBarExtraStyle`, content sizing.
- `Settings` / `Window` scenes in a `MenuBarExtra`-primary app (how to present a non-Settings
  management window from a menu-bar-only app; `openWindow(id:)` patterns).
- `SMAppService` — `.agent(plistName:)` registration, `register()`/`unregister()`,
  `status` enum (`.notRegistered`/`.enabled`/`.requiresApproval`/`.notFound`), and specifically
  **adopting a plist the app did not itself install** (the CLI-installed
  `dev.lancer.lancerd.plist` case) — confirm whether `SMAppService` requires the plist to live in
  the app bundle's `Contents/Library/LaunchAgents/` or can manage an arbitrary external plist path;
  this directly decides whether Phase A's "adopt existing install" is even possible via
  `SMAppService` or must fall back to raw `launchctl`.
- Keychain Services on macOS — app-specific access groups, whether `HostControlKit`'s token
  read/write needs Keychain at all (current plan uses a plain `0600` file at `~/.lancer/ipc-token`,
  matching `lancerd`'s existing non-Keychain secret-handling pattern — confirm this is acceptable
  or whether Mac conventions push toward Keychain for this token specifically).
- Network framework / Bonjour + **Local Network privacy** — only relevant if any future direct
  (non-relay) discovery is added; confirm current direct-connect path (if any) already handles the
  macOS Local Network prompt, or whether it's iOS-only today.
- Developer-ID signing + Hardened Runtime + notarization — entitlement requirements for a
  non-sandboxed app reading `~/.lancer/` and connecting to a Unix-domain socket; `com.apple.security.*`
  exceptions if any sandboxing is attempted later.
- App Sandbox limits vs. Unix-socket/`~` access — confirm (likely) that Lancer.app **must ship
  non-sandboxed** to retain unrestricted `~/.lancer/lancerd.sock` + arbitrary workspace-root access;
  this is a go/no-go gate for any future Mac App Store distribution (already deferred per §2.4).
- Background/login-item lifecycle — `SMAppService` interaction with System Settings → Login Items;
  how the user manually disables/re-enables from System Settings and how Lancer.app should detect
  and reflect that out-of-band change.
- Sleep/wake via `NWPathMonitor` — how the menu-bar subscribe-tap connection (§2.2.3) should detect
  and recover from a sleep/wake cycle without the UI showing stale "healthy" status.

---

## 5. Test matrix (Phase C; tag each unit / integration / UI)

| Case | Tag |
|---|---|
| Install (fresh) | integration |
| Standalone-daemon migration (adopt existing CLI install) | integration |
| LaunchAgent register/remove via `SMAppService` | integration |
| Service start/stop/restart from Lancer.app | integration |
| **App quit while agent continues** | integration |
| **App crash while agent continues** | integration |
| Service crash + recover | integration |
| Machine restart/login | integration |
| Sleep/wake | integration |
| Network loss/reconnect | integration |
| Relay loss/reconnect | integration |
| Direct→relay fallback | integration |
| Pairing success/cancel/**replay-reject** | integration |
| Device revocation | integration |
| Key rotation | integration |
| Push round-trip | integration |
| Approval round-trip | integration |
| Emergency stop | UI + integration |
| **Duplicate-service prevention** | UI |
| **App/service protocol mismatch** (`hello` version skew, both directions) | unit + integration |
| Update-while-service-active | integration |
| Complete uninstall (`~/.lancer/` + LaunchAgent both gone) | integration |
| **No secrets in logs** (grep daemon + app logs for token/key patterns) | unit |
| **Existing iPhone flows intact** (regression) | integration |
| **Headless daemon still works** (Linux systemd path, no Mac app involved) | integration |
| `DaemonFraming` round-trip (`HostControlKit`) | unit |
| `hello` RPC decode (`ConduitDProtocol.swift` mirror types) | unit |
| Peer-UID check: same-UID accept / different-UID reject / unsupported-platform fallback | unit |
| Menu-bar health dot reflects live subscribe-tap events | UI |
| Three concurrent control surfaces (SSH attach + phone relay + Mac subscribe-tap) don't starve each other | integration |

---

## 6. Verification gates

| Layer | Command | Notes |
|---|---|---|
| ConduitKit / HostControlKit (Swift) | `cd Packages/ConduitKit && swift build && swift test` | Required after any `HostControlKit` or `ConduitDProtocol.swift` change. |
| `LancerMac` app target | `mcp__XcodeBuildMCP__build_macos` | **Required**, not optional — plain `swift build` skips `#if os(macOS)` app-target code; this is the only authoritative build for app-shell/menu-bar/window-scene changes. |
| `lancerd` (Go) | `cd daemon/conduitd && go build ./... && go vet ./... && go test ./...` | Matches CI (`.github/workflows/ci.yml`, Go 1.25), per `.claude/rules/go-daemon.md`. Run from `daemon/conduitd`, not repo root. |
| iOS regression | Existing `Lancer` app-target build/test path (XcodeBuildMCP, simulator) | Confirms socket/protocol changes haven't broken the phone-facing wire format. |

**Live acceptance (real device, not simulator-only — per the visual-verification lesson on this
project, always confirm on the real Mac + real iPhone, not just in CI):**
1. Pair via QR rendered in Lancer.app.
2. Control an agent session from the phone with Lancer.app **quit**.
3. Confirm quitting/crashing Lancer.app's UI process does not kill any session or the daemon.
4. Restart `lancerd` (via Lancer.app's restart action) mid-session; confirm no state corruption
   (`~/.lancer/` audit log, policy, queue all intact).
5. Revoke a phone from the Devices pane; confirm that phone immediately loses access.
6. Run full uninstall from Lancer.app; confirm `~/.lancer/` and
   `~/Library/LaunchAgents/dev.lancer.lancerd.plist` are both gone.
7. Regression: existing iOS app-target build, relay round-trip, and headless `lancerd daemon` on
   Linux (systemd path) all still pass with zero Mac-app involvement.

**Evidence discipline (per `CLAUDE.md`/`AGENTS.md`):** every phase's "done" claim must cite the
actual command run and its output (build result, test count, screenshot path) — "should work" is
not acceptance. State explicitly which of the gates above were run and what they returned.
