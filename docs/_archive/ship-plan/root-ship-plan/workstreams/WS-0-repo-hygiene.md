# WS-0 — Repo hygiene & branch cleanup  (run FIRST)

> Foundation. Everyone else branches off the clean tree you produce. Not a 17-point item — a precondition.

## Context
Lancer iOS app repo at `/Users/roshansilva/Documents/command-center`, branch `feat/warp-style-agent-blocks`. Build: `cd Packages/LancerKit && swift build`. Tests: `cd Packages/LancerKit && swift test` (Swift Testing, `@Test`). Read `CLAUDE.md` first. A `.gitignore` already exists (~602 bytes) — **extend** it, don't clobber it.

Current mess:
- **Tracked edits (uncommitted):** `KeysFeature/KeysView.swift` (+20), `OnboardingFeature/OnboardingView.swift` (+410), `SecurityKit/KeyStore.swift` (+27), `SettingsFeature/SettingsView.swift` (+2).
- **Untracked Swift (WS-3 owns these — do NOT delete or commit):** `KeysFeature/KeyImportView.swift`, `SecurityKit/OpenSSHKeyParser.swift`.
- **Noise to ignore:** agent dotfiles `.agents/ .claude/ .codebuddy/ .commandcode/ .continue/ .crush/ .dmux/ .factory/ .goose/ .hermes/ .junie/ .kiro/ .kode/ .mcpjam/ .mux/ .neovate/ .openhands/ .pi/ .pochi/ .qoder/ .qwen/ .roo/ .trae/ .zencoder/`; `build/`; `.DS_Store`; and the committed-by-accident Linux binary `daemon/push-backend/push-backend-linux`. Decide `animations/` and `skills-lock.json` — ignore if tooling artifacts; if `animations/` holds assets the app ships, surface it and ask.

## Tasks
1. **Extend `.gitignore`** to cover every item above (dotfiles, `build/`, `**/.DS_Store`, the Linux binary). Use a glob for the agent dotfiles where sensible. If `push-backend-linux` is already tracked, `git rm --cached` it.
2. **Triage the 4 tracked edits** — read each diff; decide keep+commit (logical, complete), finish-minimally, or `git stash` (half-baked). The +410 `OnboardingView` change is large — judge whether it's coherent or mid-flight. Log a decision + reason per file.
3. **Confirm the build is green WITH the untracked key files present** — SwiftPM compiles all `.swift` in a target dir, so `KeyImportView.swift`/`OpenSSHKeyParser.swift` are already being built. If they have compile errors, do NOT implement the feature (that's WS-3) — just report the exact errors as the starting state, or make them compile as inert stubs without changing intent. Note this clearly for WS-3.
4. **Reach a clean, explained `git status`** with small, well-described commits. Do not squash unrelated changes. **Never `git add -A`** — stage specific paths.

## Constraints
- Do not commit any binary or dotfile. Do not commit `ship-plan/` (leave it for the owner to decide).
- Don't touch the untracked key feature files except to confirm/stub compilation.

## Acceptance
- `git status` clean or only intentional, explained entries; noise gone from it.
- `.gitignore` covers all listed noise. · Build green (with key files present). · `swift test` green, count noted.
- Per-file decision log for the 4 tracked edits + key-file compile status for WS-3.

## Report Template (fill in, return)
```
## WS-0 Report
### Build: <green/red + tail if red>   Tests: <count, pass/fail>
### .gitignore additions: <list>   ·  push-backend-linux: <untracked-ignored / git rm --cached>
### Tracked-edit decisions:
- KeysView.swift: <keep+commit/finish/stash> — why
- OnboardingView.swift (+410): ...
- KeyStore.swift: ...
- SettingsView.swift: ...
### animations/ + skills-lock.json: <decision>
### Untracked key files compile? <yes/no + errors for WS-3>
### Final `git status --short`: <paste>   ·  New commits: <git log --oneline>
### Deviations/risks:
```
