---
name: lancer-dead-view-sweep
description: Use when cleaning up old/dead design Swift views or stale design assets — distinguishing the views the running app actually uses from orphaned old-design files safe to delete. Use when the owner says "delete the old designs/swift files, keep what the app uses now," or asks to find dead views, unreferenced screens, or stale screenshots/archived docs.
---

# Lancer Dead-View Sweep

## Overview

Separate **live views** (reachable from the running app) from **orphaned old-design Swift files**
and the stale assets that reference them — then delete the dead set on a single confirmation.
This is the 2026-06-24 task where the owner had to repeat "no, I mean the *old design* swift
files — keep the views the app shows now." Reachability makes "old vs current" objective instead
of a guess.

**Why this skill exists:** "which files are the old design?" is mechanical underneath — a view the
app can't reach is dead. Computing reachability removes the back-and-forth.

## Hard rules

- **Never auto-delete.** Produce the candidate list with evidence, get ONE confirmation, then delete.
- **Reference = used.** A view whose type name appears in any non-test, non-preview source file
  other than its own definition is live. A view reachable only via a debug/deep-link seam
  (`LANCER_DESTINATION` in `AppRoot.swift`) is still **live**. (The old mock-gallery view
  harness was deleted 2026-06-24 — don't expect a gallery.)
- **Respect `git status`** — other agents' in-flight files are not "dead." Check before flagging.
- This is the repo's own "no dead code / delete cleanly" rule (`agent-contract.md` §3) made executable.

## Workflow

1. **Build the reachable set.** Root: `AppRoot.swift` (sidebar / New Chat shell) plus the
   `LANCER_DESTINATION` deep-link cases in it. A view is *referenced* if its type name appears in
   another source file via `NavigationLink`, `.sheet`, `.fullScreenCover`, a route enum case, or a
   plain initializer call.

2. **Find candidates.** For each `struct <Name>: View` in `Packages/LancerKit/Sources`:
   `rg -l '\b<Name>\b' Packages/LancerKit/Sources --glob '!**/*Tests*'` — if the only hit is the
   file that defines it (and `#Preview` providers), it has **0 external references** → candidate.
   Also scan `docs/_archive/` and any `screenshots/` dirs for assets naming a candidate view.

3. **Filter false positives:**
   - Preview providers / `#Preview` blocks do not count as references.
   - A view used only via the gallery is **kept** (it's reachable).
   - Anything modified in `git status` is **kept** (in-flight work).

4. **Present the kill list** — one line per file: path · `0 external refs` · last-touched. Group
   Swift views, archived docs, and stale screenshots separately. Ask for one confirmation.

5. **Delete** the confirmed set, then run `$lancer-verification-gate` (swift build + app-target
   build) to prove nothing live referenced them. A build break means the reachability scan missed
   a reference — restore that file and fix the scan, don't force the delete.

## Done when

The confirmed dead set is deleted, the verification gate is green, and you've reported the count
deleted plus anything you *kept* despite zero refs (and why — in-flight, gallery-only).
