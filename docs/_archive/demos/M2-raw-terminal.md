# M2 — Real Terminal Demo

## Prerequisites
- M1 complete: host added, Ed25519 key in `~/.ssh/authorized_keys`, TOFU accepted.
- Remote: `vim`, `tmux`, `htop` installed (`brew install` / `apt install`).
- iOS Simulator: iPhone 17 Pro, Xcode 26.

## Steps

### 1. Connect to host
Open app → Workspaces → tap host → Face ID → host-key confirm (if not yet trusted) → Session view.

### 2. TUI escalation — vim
In the composer, type `vim test.md` and tap Send (↑).

**Expected:**
- BlockRenderer sends `\x1b[?1049h` → SessionViewModel detects `pendingTUIEscalation`.
- `SessionView` swaps `BlockScrollView` for `RawTerminalView` (SwiftTerm).
- Keyboard accessory rail shows: **Esc · Tab · Ctrl · ← ↑ ↓ → · | · ; · / · $ · &&**
- Type `iHello, Lancer!` → text appears in the SwiftTerm canvas.
- Press **Esc** (accessory rail) → normal mode.
- Type `:wq` → vim exits.

**Expected after exit:**
- `\x1b[?1049l` detected → SessionViewModel de-escalates back to Block mode.
- A synthetic Block labelled `vim test.md` appears in the scroll view (exit chip green `0`).

### 3. TUI escalation — tmux
Type `tmux new -s scratch` → send.

**Expected:** SwiftTerm takes over; tmux status bar visible at bottom.

Press **Ctrl** (sticky, turns blue) then `b`, then `d` to detach.

**Expected:** Returns to Block mode with a synthetic block for `tmux new -s scratch`.

### 4. Resize
Rotate device to landscape → `RawTerminalView` calls `PTYBridge.resize(cols:rows:)` → remote `stty size` returns the new dimensions.

### 5. Regression — Block mode still works
Type `echo hello` → Block mode renders stdout, exit chip green `0`.

## Pass criteria
- [ ] TUI programs take over the screen reliably; no frozen UI.
- [ ] Keyboard accessory shows correct preset in raw mode.
- [ ] Alt-screen exit returns cleanly to Block mode.
- [ ] No crash on rapid escalation/de-escalation cycles.
- [ ] `swift test` still passes (no M1–M2 regression).
