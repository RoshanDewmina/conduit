# WS-15 — Competitive feature spikes  (post-launch)

> Each item is a **flagged prototype**, not a finished feature. Verify each in the gallery. Build the highest-ROI ones first; stop when value-per-effort drops. These are the §6 BUILD items where Lancer can pull ahead of shipped mobile competitors.

## Context
Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/LancerKit && swift build`. Read `CLAUDE.md`, `docs/agent-contract.md`. Each prototype goes behind a feature flag and is verified in the gallery before any rollout.

## Tasks (prioritized — impact↑/effort↓ first)
1. **Shortcut / extra-key bar above the keyboard** — Esc/Tab/Ctrl/arrows + Approve/Reject + paste-image + snippet chips. The `.tmuxPrefix`/`ShortcutKey` enum exists but several cases have no handler — wire the bar to real key emission over the unified PTY (no second PTY). *(high/med)*
2. **Screenshot / file-into-prompt one-tap loop in the composer** — surface image/file attach directly in the session composer, not buried in Files. *(high/med)*
3. **Typed approval actions + autonomy presets** — model approvals as typed actions (RunCommand / EditFiles / CallMCP / AskQuestion); add per-capability autonomy presets (auto-approve reads / always-ask writes); add an **AskUserQuestion** Inbox card. *(high/low–med)*
4. **APNs push-on-approval / run-complete + artifact chips** — distinct from the foreground Live Activity; completion notifications carry artifact chips (Open PR / Open Plan / View screenshots). Builds on WS-5's push backend. *(high/med)*

## Constraints
- Each behind a flag; default off until reviewed. · Single unified PTY — never spawn a second `SSHShell`. · Keep TOFU + Keychain invariants. · These are spikes — prefer a working vertical slice over breadth.

## Acceptance
- Each attempted item: a flagged, gallery-verifiable prototype with a short demo note + screenshot, and an honest "ready to productionize? / what's left" assessment. Build + suite green. Log which items you did NOT get to.

## Report Template (fill in, return)
```
## WS-15 Report
### Items prototyped: <which of 1–4; flag names>
### (1) shortcut bar: <state + screenshot> · (2) file-into-prompt: <state>
### (3) typed approvals + autonomy presets + AskUserQuestion card: <state>
### (4) push-on-approval + artifact chips: <state>
### Not reached: <list>  · Invariants: single-PTY <held?> TOFU/Keychain <held?>
### Build/Suite: <green/red> · Files changed: <list> · Deviations/risks:
```
