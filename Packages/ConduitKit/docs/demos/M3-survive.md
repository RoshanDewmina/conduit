# M3 — Survive (Reconnect & Continuity)

Status: in progress
Created: 2026-05-24

## Goal
Sessions survive Wi-Fi ↔ cellular handoffs and ~10s backgrounds without
user-visible breakage. tmux is the durability backbone.

## Demo Script
1. Connect to remote host, run `top` in raw mode.
2. Toggle airplane mode for 10s → "suspended" badge appears.
3. Disable airplane → reconnect within 5s, same `top` view continues.
4. Background app for 30s → reopen → session attaches to same tmux,
   last 2000 bytes replay above prompt.
