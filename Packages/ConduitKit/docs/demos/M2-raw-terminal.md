# M2 — Real Terminal (Raw PTY)

Status: in progress
Created: 2026-05-24

## Goal
When a TUI program takes over the screen, SessionView swaps in RawTerminalView
bound to a live PTY channel. Exiting alt-screen returns to Block mode.

## Demo Script
1. Connect to remote host (M1 flow).
2. Type `vim test.md` → SwiftTerm takes over, keyboard rail shows Esc / hjkl.
3. Edit, `:wq` → returns to Block mode with a synthetic "vim test.md" block.
4. Type `tmux new -s scratch` → SwiftTerm again; detach (`C-b d`) → back to Block mode.
