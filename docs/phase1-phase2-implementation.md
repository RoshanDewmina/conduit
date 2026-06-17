# Phase 1 + Phase 2 Implementation — iOS 26 / Swift 6.2

Updated: 2026-05-27 (caveats verified)

## Overview

This document covers the implementation of Phase 0 (platform upgrade), Phase 1 (make SSH work end-to-end), and Phase 2 (session survival) for Conduit — the mobile cmux.

Prior to this work, Conduit had a well-architected codebase (~8,600 lines, 80+ files) but was functionally at early M1. SSH shell opening was stubbed, sessions were never auto-connected, and reconnection logic was unimplemented.

## Research Conducted

Before implementation, we studied four competing/related projects:

### Warp (fully open-source, Rust, AGPL)
- Block model confirmed as the core UX innovation — each command+output is a discrete, selectable, copyable unit
- Agent Mode uses approval-based command execution — maps to Conduit's inbox concept
- Warp Drive offers parameterized workflows in YAML — inspiration for snippets
- **No mobile Warp app exists** — Conduit fills this gap

### Termius (main mobile SSH competitor)
- Space-bar drag for arrow keys — best mobile terminal gesture innovation
- Extended keyboard sidebar with 4 tabs (snippets, history, keys, themes)
- Snippets **lack parameterized variables** — opportunity for Conduit to ship first
- **#1 user complaint is subscription fatigue** ($120/year)
- Background limit is iOS-level (20-30s) — Termius recommends tmux

### cmux (native macOS agent terminal)
- Not a tmux wrapper — standalone GUI app built on Ghostty's renderer
- No session persistence — sessions end when app closes
- Notification rings on tabs for agent attention — good mobile inspiration
- cmux is local-only; Conduit is the mobile equivalent for remote work

### Blink Shell (session resilience gold standard)
- Mosh first-class support — sessions survive network switches, sleep/wake, IP roaming
- One-time purchase (no subscription) — users prefer this model
- Key competitor to match or exceed for mobile SSH resilience

### Mosh (Mobile Shell)
- UDP-based SSP protocol, survives IP changes and sleep/wake
- Predictive local echo reduces perceived latency
- Stretch goal for Phase 2 — requires server-side `mosh-server`

## What Changed

### Phase 0: Platform Upgrade

**Files modified:**
- `Packages/ConduitKit/Package.swift` — swift-tools-version 6.0 → 6.2, `.iOS(.v17)` → `.iOS(.v26)`, `.macOS(.v14)` → `.macOS(.v15)`
- `project.yml` — All deployment targets 17.0 → 26.0, SWIFT_VERSION 6.0 → 6.2

**What this enables:**
- Citadel's PTY/terminal API (requires iOS 18+) is now always available
- Swift 6.2's MainActor-by-default simplifies concurrency
- iOS 26 `BGContinuedProcessingTask` for better background keepalive (future)
- Liquid Glass design language for UI chrome (future)
- Removed `StrictConcurrency` and `ExistentialAny` upcoming feature flags (both default in Swift 6.2)

### Phase 1: Make SSH Work End-to-End

**SSHShell.swift** — Implemented PTY shell channel opening:
- `SSHShell.open(session:width:height:)` no longer throws `.unsupportedPlatform`
- Creates shell via `SSHSession.requestShellChannel()`, stores NIO Channel, feeds byte stream
- Made `byteContinuation` internal (was private) so the factory can pass it to the session
- Removed all iOS 17 compatibility TODOs (no longer relevant on iOS 26)

**SSHSession.swift** — Added shell channel + connection timeout:
- Added `requestShellChannel(width:height:dataContinuation:)` method
  - Uses Citadel's `withTerminal(term:width:height:)` API
  - Data pump runs in background Task via `withCheckedThrowingContinuation`
  - Channel is returned for send/resize, closure stays alive pumping data
- Added 15-second connection timeout using task-group racing pattern
  - `withThrowingTimeout(_:operation:)` races the operation against `Task.sleep`
  - Throws `ConduitError.timeout` if connect hangs
- Added `import NIOSSH` for PTY request types

**AppRoot.swift** — Fixed the missing connect call:
- `startSession()` now calls `await vm.connect()` after setting up the SessionViewModel
- Previously, sessions were created but never auto-connected (the view's `.task` was the only path)
- ScenePhaseObserver is now initialized inside `startSession()` with proper weak captures
- Background callback posts "Session suspended" notification

**SessionView.swift** — UI improvements:
- Added manual Terminal/Blocks toggle button in toolbar
  - "Terminal" button (when connected, not raw) → `escalateToRaw()`
  - "Blocks" button (when raw) → `deescalate()`
- Added reconnection banner with progress indicator and cancel button
- Added red sidebar indicator for failed command blocks (Warp error pattern)
  - 3px red bar on left edge of block
  - Subtle red background tint (`Color.red.opacity(0.05)`)

### Phase 2: Session Survival

**SessionViewModel.swift** — Reconnection + tmux:
- Implemented `handleSceneActive()` — checks SSH connection, triggers reconnect if lost
- Implemented `attemptReconnect()` — uses cached credentials, reattaches tmux
- Implemented `enableTmux(sessionName:)` for runtime tmux configuration
- `connect()` now auto-attaches to tmux when `host.tmuxSessionName` is set
- Added `reconnectEngine` property for network-aware reconnection

**HostEditorView.swift** — tmux configuration:
- Added `tmuxSessionName` text field in new "Session" form section
- Passes tmux name through to Host model on save
- Explanatory footnote about what tmux session names do

**Notifications.swift** — Background notification:
- Added `postSessionSuspended(hostName:)` method
- Posts local notification when background task expires and session is suspended

## Architecture Notes

### Shell Channel Lifecycle

```
SSHShell.open(session:width:height:)
  ├── Creates SSHShell actor (owns byte stream + continuation)
  ├── Calls session.requestShellChannel(width:height:dataContinuation:)
  │   ├── withCheckedThrowingContinuation { ... }
  │   │   ├── Task {
  │   │   │   client.withTerminal(term:width:height:) { channel, inbound in
  │   │   │     continuation.resume(returning: channel)  ← returns channel
  │   │   │     for await buffer in inbound {             ← pumps data
  │   │   │       dataContinuation.yield(bytes)
  │   │   │     }
  │   │   │     dataContinuation.finish()
  │   │   │   }
  │   │   └── }
  │   └── returns Channel
  └── shell.storeChannel(channel) → ready for send/resize/close
```

### Reconnection Flow

```
App goes to background → ScenePhaseObserver.onBackground
  └── Posts "Session suspended" notification

App returns to foreground → ScenePhaseObserver.onBecomeActive
  └── SessionViewModel.handleSceneActive()
      ├── Check: is SSH still connected?
      ├── If no → attemptReconnect()
      │   ├── sshSession.attemptReconnect() (uses cached credentials)
      │   ├── If tmux configured → TmuxClient.attachOrCreate(name:)
      │   └── Status → .connected, refresh CWD
      └── If yes → no-op
```

### Connection Timeout

```
SSHSession.connect(credential:hostKeyStore:)
  └── withThrowingTimeout(.seconds(15)) {
        SSHClient.connect(host:port:authenticationMethod:hostKeyValidator:reconnect:)
      }
      ├── Task 1: actual connect
      └── Task 2: sleep(15s) then throw .timeout
      → whichever finishes first wins, other is cancelled
```

## Known Caveats (verified 2026-05-27)

1. **Citadel API name**: `requestShellChannel` uses `client.withTerminal(term:width:height:)`. If the actual Citadel 0.9.x method has a different name (e.g., `withPTY`, `openShell`, `requestShell`), you'll get a compile error localized to `SSHSession.swift:requestShellChannel`. The fix is adjusting the method name to match. (The current code builds, so the name is correct as of this commit.)

2. **Mosh not yet implemented**: Marked as a stretch goal. Blink Shell's main advantage is Mosh support. Adding this would require integrating a Mosh client library or building the protocol from scratch.

3. **BGContinuedProcessingTask not yet used**: iOS 26's improved background API is noted in the plan but not implemented. Repo-wide grep shows zero references in `Packages/ConduitKit/Sources`. Current behaviour: `ScenePhaseObserver` + `SessionViewModel.handleSceneActive()` reconnects on resume; `Notifications.postSessionSuspended` fires when the standard background task expires. Adopting `BGContinuedProcessingTask` would extend background runtime past the ~30s standard cap for users who don't run tmux. Tracked in `docs/_archive/current-state-audit.md` → "Background-keepalive status".

4. **Liquid Glass partially adopted**: `DesignSystem/Atoms.swift` ships `conduitGlassChrome(cornerRadius:interactive:)`, which calls `.glassEffect(...)` on iOS 26 with a `.ultraThinMaterial` fallback. Four call sites use it today (raw-mode keyboard rail + composer in `SessionFeature/SessionView`; top + bottom ribbons in `AppFeature/SessionShellView`). Seven secondary-chrome surfaces still use raw `.background(.bar/.thinMaterial/.regularMaterial)` and should migrate — see `docs/_archive/current-state-audit.md` → "Liquid Glass adoption status" for the file/line list.

## Testing Checklist

### Phase 1 — SSH
- [ ] Connect to real host with password auth
- [ ] Connect with Ed25519 key auth
- [ ] Run `ls`, `git status` → blocks appear with copy actions
- [ ] Run `vim` → raw terminal mode works
- [ ] Run `htop` → auto-escalation to raw mode
- [ ] Exit vim → returns to block mode
- [ ] Toolbar Terminal/Blocks toggle works
- [ ] Kill Wi-Fi → error state shows with clear message
- [ ] Connect to unreachable host → times out in ~15s
- [ ] Failed command shows red sidebar indicator

### Phase 2 — Survival
- [ ] Set tmux session name on host → verify attach-or-create
- [ ] Toggle airplane mode → reconnects when restored
- [ ] Lock phone 30s, unlock → session resumes via tmux
- [ ] Force-kill app, reopen → reattaches to same tmux session
- [ ] Wi-Fi → cellular switch → reconnects without losing output
- [ ] "Session suspended" notification appears after background expiry
- [ ] Reconnection banner shows with cancel button
