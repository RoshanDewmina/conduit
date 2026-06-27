# WS-12 — Interactive onboarding + tutorials  (post-launch)

> Depends on WS-0. Coordinate with WS-0's triage of the uncommitted `OnboardingView` edits.

## ⚠️ VERIFY FIRST
There are **+410 uncommitted lines** of `OnboardingFeature/OnboardingView.swift` changes (triaged in WS-0). These may already advance this workstream substantially — read the current state (and WS-0's decision log) before planning.

## Context
Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/LancerKit && swift build`. Read `CLAUDE.md` "Visual verification". Lancer is BYO-host / BYO-key / no-account.

**Confirmed state:** onboarding is a single static `OnboardingView` screen + an optional `ProvisioningWizard` (5 steps), gated by `@AppStorage("onboardingSeen")`. No interactive walkthrough, no resume, **no replay**.

## Tasks
1. Replace/extend the static screen with an interactive, **skippable, replayable** walkthrough covering the core topics: BYO-host/no-account model, add a host, SSH keys + TOFU, connect & Warp-style blocks, the approval Inbox, autonomy presets, tmux/persistence, provisioning a VM.
2. Drive completion via `@AppStorage("onboardingSeen")` but add a **"Replay tour"** entry in Settings; resume mid-tour if interrupted.
3. Use the design system (PixelBox, DSButton, DS fonts); honor Dynamic Type (the `*Pt` helpers scale).

## How to verify
Gallery `onboarding` route, light + dark, default + `accessibility3`.

## Acceptance
- First-run teaches the core topics interactively; skip works; tour replayable from Settings; no clipping at AX3. Build + suite green; light+dark screenshots.

## Report Template (fill in, return)
```
## WS-12 Report
### Starting state (incl. the +410 uncommitted edits): <what existed>
### Walkthrough: <topics covered; skippable? replayable from Settings? resume?>
### DS + Dynamic Type: <conformance; AX3 clipping?>
### Screenshots: <onboarding route, light/dark>
### Build/Suite: <green/red> · Files changed: <list> · Deviations/risks:
```
