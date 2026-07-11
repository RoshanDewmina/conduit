# Phone dogfood results — multi-turn + persistence (M2)

**Date:** 2026-07-09  
**Branch / tip:** `feat/chat-overhaul-w0a` @ `d4db7da721b7cc08163825116dce3ebf8b498347`  
**Device:** Roshan’s iPhone `557A7877-F729-5031-9606-0E04F2B67822`  
**Relay code:** `025359` (do not rotate)  
**Evidence dir:** `docs/test-runs/2026-07-09-phone-dogfood/`

## Preflight

| Check | Result |
|-------|--------|
| lancerd running | PASS (pid 770) |
| relay `/health` | 200 |
| Workspaces Connected | PASS (M1) |
| No `REPLACING` mid-run | pending during M2 |

## B2 — Multi-turn

| Step | Result | Notes / screenshot |
|------|--------|--------------------|
| Turn 1 streams; Working… clears | **PASS** (after cwd fix) | `conv_61ce5064…` cwd `/Users/roshansilva/Documents/command-center`; host event `output`=`hello from turn 1`; status `exited` exit 0. Screenshot `01-turn1-hello-pass.png`. Earlier fail `conv_67361e8` was bare cwd ENOENT. |
| UI flicker “no response” ↔ text | **root-caused + fix installed** | `transcriptModel.reload()` dropped live overlay while GRDB lagged; showed “No output recorded…”. Fixed: reload preserves overlay; keep live response until persist catches up. |
| Turn 2 same conversationID | **PASS** | Same `conv_61ce5064…`; turns 1+2 both `exited`; screenshot `02-turn2-same-thread-pass.png` |
| Markdown / text visible | PASS (plain text) | |

**conversationID (Turn 1+2 PASS):** `conv_61ce5064-e290-4cd7-969b-cac4c27533dd`  
**runId Turn 1:** `9bed4a14-d3a0-4fa2-9a8c-90d554f8a3da`  
**runId Turn 2:** `b625644e-4b1…`

## B3 — Persistence

| Step | Result | Notes / screenshot |
|------|--------|--------------------|
| Force-quit → relaunch → both turns present | **FAIL → root-caused** | `03-forcequit-empty-starting.png` — empty "Starting…" while host still had turns 1+2. `onOpenThread` only read local GRDB (often empty after reinstall) and never fetched host ledger. Fix: refreshConversation on thread open + bindTranscript awaits it. |
| Turn 3 continues same thread | pending | Prompt: `Say turn 3` |

## B4 — Host-ledger discovery

| Step | Result | Notes |
|------|--------|-------|
| Workspaces pull-to-refresh shows thread | pending | |

## Verdict

**M2:** pending
