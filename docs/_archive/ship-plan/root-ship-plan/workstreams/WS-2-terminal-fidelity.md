# WS-2 — Terminal / block fidelity  (covers 17-pt #1, #3, #2/#5)

> Depends on WS-0. The blocks are the product's headline — be conservative, do not regress invariants.

## Context
Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/LancerKit && swift build`. **Read first:** `docs/block-terminal-implementation.md`, `docs/agent-contract.md` §5, `CLAUDE.md` "Block terminal". Pipeline: unified PTY → `PTYBridge` (OSC 133 A/B/C/D + OSC 7, alt-screen) → `SessionViewModel` → `BlockRenderer` → `ChatTranscriptView`/`ToolCardView`.

**Confirmed root causes (from the source audit — verify each in code first):**
- **#1 Empty space:** inline-TUI blocks are force-sized to `min(720, max(360, screenH*0.55))` at `ToolCardView.swift:69–78` (applied ~L248). A live handle on a short/idle block reserves ~360–720pt of blank space. Plain text output has no min-height.
- **#3 Long-output overwrite:** per-block SwiftTerm is `rows=2000, scrollback=0` at `BlockRenderer.swift:297`. Beyond 2000 lines the oldest rows are **silently overwritten** — no truncation UI, no per-block scroll.
- **#2/#5 Claude light-on-dark:** Lancer injects **no theme hint** (no `COLORFGBG`) in `ShellIntegrationScript.swift`; `TerminalTheme.current` is local-only (`AnsiSGRParser.swift:175–180`). Remote Claude Code can't detect the dark bg → draws light (the `/theme` workaround in the screenshots). **NOTE:** commit `858b688` is titled "COLORFGBG theme hint…" — **first check whether #2/#5 is already done.** If so, verify it end-to-end and close it; do not duplicate.

## Tasks
1. **#1** Remove the inline-TUI min-height floor for idle/short blocks — only reserve the large height when a live TUI handle is actually rendering content; otherwise size to content. Don't break vim/htop/claude full-height rendering when they ARE active.
2. **#3** Add scrollback (raise from 0) or a truncation affordance ("output truncated — N earlier lines dropped") so long output isn't silently lost. Mind memory for very long output.
3. **#2/#5** Verify the COLORFGBG theme hint from 858b688 actually reaches the remote and flips Claude/codex to dark; if missing or incomplete, inject `COLORFGBG` (+ tie to `TerminalTheme.current` so it tracks app light/dark). Confirm with a live `claude` block.
4. **Light hardening pass** while you're here: rapid consecutive commands, no-output commands, stderr-only, Ctrl-C mid-stream — each forms exactly one block with the right exit chip. Add `PTYBridge`/`TUIDetector` unit tests (these are SSH-free and unit-testable).

## Hard invariants — DO NOT REGRESS
- `.submitted`-only escalation in `SessionViewModel.onBlockBytes` — never escalate an idle `.promptEditing` prompt.
- Single unified PTY — no second `SSHShell`.
- Alt-screen escalate/de-escalate (`\e[?1049h/l`) for vim/htop/tmux still clean.

## How to verify
Live harness: `SIMCTL_CHILD_LANCER_GALLERY=session` + `LANCER_TEST_*` (CLAUDE.md has exact env + `LANCER_TEST_AUTOCMD='claude'`). Static visual: `SIMCTL_CHILD_LANCER_GALLERY=blocks`. Screenshot after ~11s; light + dark.

## Acceptance
- #1 no blank floor on idle/short blocks; #3 long output not silently lost; #2/#5 remote agent renders dark (verified live or via the 858b688 path). Invariants held. Build + suite green; new detector/bridge tests. Light+dark screenshots.

## Report Template (fill in, return)
```
## WS-2 Report
### #1 empty-space floor: <change + before/after screenshot>
### #3 long-output: <scrollback raised / truncation UI; memory note>
### #2/#5 theme hint: <already done in 858b688? verified? or what you added>
### Hardening: <cases checked> · New tests: <PTYBridge/TUIDetector>
### Invariants: submitted-escalation <held?> single-PTY <held?> alt-screen <held?>
### Build: <green/red> Suite: <count> · Screenshots: <paths light+dark>
### Files changed: <list> · Deviations/risks:
```
