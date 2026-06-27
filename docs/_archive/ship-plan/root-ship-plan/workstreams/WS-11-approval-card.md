# WS-11 — Inbox approval-card redesign  (post-launch; near-ship — confirmed device bug)

> Depends on WS-0. Localized UI fix to a bug seen on a real device. No backend. Pull earlier than other post-launch items if time allows.

## ⚠️ VERIFY FIRST
Commit `858b688` is titled "…approval-card header…". Check whether this bug is already fixed before redoing it; if partially fixed, finish/verify rather than rewrite.

## Context
Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/LancerKit && swift build`. Read `CLAUDE.md` "Visual verification". Component: `DesignSystem/Components/ChatComponents.swift` → `DSApprovalCard`.

**Confirmed bug (audit + device screenshot):** in `DSApprovalCard` (~L204–212) the action sentence is an `HStack(spacing:4)` of `agentName` (semibold) + "wants to {action} on" + `hostLabel`, but `hostLabel` overrides to `dsMonoPt(12)` + `t.text3`, so it visually **detaches from the sentence and wraps awkwardly** (no `fixedSize`/`lineLimit`) — the "floating path label" on device.

## Tasks
1. Redesign the header so the agent action reads as one coherent unit: a sentence line ("Claude Code wants to run a command") with the host/path on its **own labeled metadata row** (mono, with a host glyph) — not mid-sentence in a different font/color.
2. Add `fixedSize(horizontal:false, vertical:true)` + sensible `lineLimit` so it wraps cleanly at large Dynamic Type.
3. Keep the risk badges, the `DSQuoteBlock` command, and the DENY / ALLOW ALWAYS / APPROVE buttons. Hierarchy = who → what → where → command → actions.

## How to verify
Gallery routes `inbox-typed` and `review`, light + dark, at default and `accessibility3`.

## Acceptance
- Path never floats mid-sentence; clean wrap at AX3; clear who→what→where→command→actions hierarchy. Build + suite green; light+dark+AX3 screenshots.

## Report Template (fill in, return)
```
## WS-11 Report
### Already fixed by 858b688? <y/n — what state>
### Redesign: <sentence + metadata row approach; fixedSize/lineLimit added?>
### Kept: risk badges <y> command quote <y> DENY/ALLOW ALWAYS/APPROVE <y>
### Screenshots: <inbox-typed + review, light/dark/AX3 paths>
### Build/Suite: <green/red> · Files changed: <list> · Deviations/risks:
```
