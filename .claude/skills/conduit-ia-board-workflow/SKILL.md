---
name: conduit-ia-board-workflow
description: Use when editing, reviewing, or verifying Conduit IA/design-board work, especially requests to simplify the app, preserve the same design, make prototypes interactive, put new designs at the top of the board, or fix designs that are not visible in the rendered board.
---

# Conduit IA Board Workflow

## Overview

Use this skill for Conduit board and IA prototype work. The deliverable is visible rendered behavior, not just source edits.

## Active IA Direction

Load `references/board-map.md` for paths and verification details.

- **Canonical IA (shipped, 2026-06-18):** a sidebar/drawer shell with **New Chat** as the default first surface and durable chat **threads** in the sidebar. Inbox, Fleet, and Settings hang off the sidebar (`SidebarDestination`); the old `Inbox/Fleet/Control/Settings` tab bar is **deprecated** — do not reintroduce a tab bar or a `Control`/`Activity` root.
- Verify any board/IA claim against `Packages/ConduitKit/Sources/AppFeature/AppRoot.swift` + `ConduitSidebarView.swift` + `SidebarShellState.swift` — code wins over the prototype/board.
- Chat/recent-thread work is first-class. Activity/history folds into Recent Threads, Needs Attention, and deeper audit/history details — never a root surface.
- Labels should be plain English and tester-friendly.

## Workflow

1. Confirm whether the target is the repo migration board or the exported Downloads board.
2. Make the requested prototype visible near the top when the user asks to see it.
3. Preserve the existing visual system unless the user asks for a redesign.
4. Verify after hydration with a browser/DOM check or screenshot.
5. Check responsive visibility on desktop and mobile widths when layout changed.

## Completion Standard

Report the exact file touched, the visible labels that prove the new section rendered, and how you verified it.

