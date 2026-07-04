# PR #15 — Siri Phase 1 manual voice matrix

Date: 2026-07-04  
Branch: `cursor/siri-primary-ios26-foundation-bc7c` (PR #15)  
Runner: _owner (physical iPhone, real voice — not simulator HID)_  
Device: _fill UDID / iOS version_

## Preconditions

- [ ] Build installed from PR #15 branch (`gh pr checkout 15`)
- [ ] Relay paired and at least one machine online
- [ ] At least one pending approval available for deny test (approve is **not** voice-triggerable)

## Phrase matrix

| # | Phrase said (exact) | Expected | Pass/Fail | Actual behavior | Notes |
|---|---------------------|----------|-----------|-----------------|-------|
| 1 | "Search Lancer for …" | Opens search / finds thread | | | |
| 2 | "Open conversation …" / continue via voice | Opens correct thread | | | |
| 3 | "Open machine …" | Opens machine / fleet context | | | |
| 4 | "Deny approval in Lancer" | Denies pending approval | | | |
| 5 | "Pause run in Lancer" (single run) | Pauses active run | | | |
| 6 | "Stop run in Lancer" (single run) | Stops active run | | | |
| 7 | Pause/stop with **multiple** active runs | Correct run targeted or disambiguation | | | |
| 8 | Action while machine **offline** | Clear failure, no crash | | | |
| 9 | Audit `Lancer/LancerAppShortcuts.swift` | **No** voice-approve shortcut exists | | | Code review |

## Voice-approve audit

Confirm no shortcut or intent exposes approve-by-voice:

- [ ] `LancerAppShortcuts.swift` — no Approve phrase
- [ ] App Shortcuts provider — deny only for approvals

## Gate

- [ ] All matrix rows pass
- [ ] `gh pr ready 15` → CI green → `gh pr merge 15 --merge --delete-branch`

## Sign-off

Owner: _______________  Date: _______________
