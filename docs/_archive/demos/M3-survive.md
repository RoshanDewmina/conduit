# M3 — Survive (Reconnect & Continuity) Demo

## Prerequisites
- M1+M2 complete.
- Remote: `tmux` installed.
- Physical device or simulator with network controls available.

## Steps

### 1. Connect and start a long-running process
Connect to host (M1 flow). In Session, type `top` → send.
`top` escalates to raw/PTY mode (M2). You should see the live process table.

### 2. Simulate network loss — airplane mode
On physical device: toggle **Airplane Mode** for 10 seconds.
On simulator: **Network Link Conditioner** → set to 100% loss for 10 seconds.

**Expected:**
- Session status badge changes to **"Suspended"** within 2 s of detecting loss.
- The frozen SwiftTerm canvas remains visible (no crash).
- A local notification fires: "Connection to Dev Box lost".

### 3. Restore network
Disable Airplane Mode / Link Conditioner.

**Expected (within 5 s):**
- `AutoReconnectEngine` fires a reconnect attempt.
- SSHSession reconnects using cached credentials (no biometric re-prompt).
- `TmuxClient.attachOrCreate(name:)` attaches to the existing tmux session.
- Last 2000 bytes of `capture-pane` replay as a synthetic Block above the prompt.
- Session status badge returns to **"Connected"**.
- `top` is live again in SwiftTerm.

### 4. Background survival
Press the Home button (background the app) for ≥ 30 s.
Re-open Conduit.

**Expected:**
- `ScenePhaseObserver.onBecomeActive` fires → reconnect if needed.
- Same tmux session attaches; 2000-byte replay visible.

### 5. Verify tmux name persistence
Quit the app entirely (swipe away). Re-open.
Navigate to the host → connect.

**Expected:** The saved `tmuxSessionName` from `HostRepository` is used automatically, so the same tmux session is reattached without creating a new one.

## Pass criteria
- [ ] "Suspended" badge appears within 2 s of network loss.
- [ ] Reconnect completes within 5 s of network restore.
- [ ] No biometric re-prompt on auto-reconnect.
- [ ] 2000-byte pane replay visible on each reconnect.
- [ ] `swift test --filter AutoReconnectEngineTests` passes.
