# WS-10 QA Report — 2026-05-31

Branch `feat/warp-style-agent-blocks` @ `b58b2aa`. Unit tests **253/253 pass**; sim build
`BUILD SUCCEEDED`. Run scope below. Screenshots in `/tmp/ws10-qa/`.

## Environment
- **Simulator:** iPhone 17 Pro (booted), Lancer `dev.lancer.mobile`, light + dark.
- **Real host:** `127.0.0.1` (this Mac), macOS Remote Login, `/bin/zsh` 5.9, **428-line interactive `~/.zshrc`** (zle / bracketed-paste / zstyle present).
- **Real device:** Roshan's iPhone (iPhone 17, iPhone18,3) connected but **not driven** — interactive items (Face ID, push taps, purchases, Live Activity, network handoff) require the owner physically at the device.

## Results (automatable subset — run for real)

| # | Item | Result | Evidence |
|---|------|--------|----------|
| 1 | Onboarding walkthrough (8-step paged) | ✅ PASS | `08-onboarding.png` — "1/8", PixelBox, Attach/Survive/Approve/Review rows, page dots, Next. Clean, DS fonts. |
| 5 | **Live real-host blocks (zsh)** | 🔴 **FAIL** | `03/04/05-*.png` — see Critical failure below. |
| — | Block UI layer (`blocks` gallery) | ✅ PASS | `06-blocks-gallery.png` — DSBlockCard, RUN›COMMAND, `$` bar, `✓ exit 0`/`✗ exit 1` chips, ANSI colors. Rendering is healthy. |
| 6 | Tmux restore picker (live) | ✅ PASS (UI) | `04-*.png` — themed dark sheet, mono names, ATTACH/Skip. Full reconnect not exercisable (blocked by #5). |
| 9/10 | Settings/layout, review composite, light+dark | ✅ PASS | `01-review-light.png`, `02-review-dark.png` — session rows, PixelAvatars, fixed-geometry PixelBox + unread badge slot, inbox card. No clipping. |
| 10 | Dynamic Type @ AX5 | ✅ WORKS | `07b-review-AX5.png` — text scales up (shipped `*Pt` fix functional). *Minor:* gallery **mock** header clips horizontally at AX5 — debug harness only, not a shipping screen. |

## 🔴 Critical failure — live shell-integration injection leaks on zsh (owning WS: WS-2 terminal)
**Symptom:** On a live SSH session to a real zsh host, the Lancer shell-integration bootstrap
(`__lancer_preexec`/`__lancer_prompt_command`/the `if [ -n "${ZSH_VERSION-}" ]…fi` block) is
**echoed into the terminal as raw text** and zsh is left stuck at continuation prompts
(`then>`, `function quote>`). No clean OSC-133 block forms; the post-clear prompt never lands.

**Reproduction (consistent):**
- Reproduces **with and without** a connect-time auto-command.
- Reproduces **with and without** stale tmux sessions on the host (cleared the 5 May-30 leftovers; still fails).
- Block **UI rendering is fine** (static `blocks` gallery renders perfectly) → the defect is in the
  **live injection path**, not rendering.

**Likely cause / where to look:**
- `SessionViewModel.swift:842` sends the multi-line POSIX bootstrap as one `shell.send(script + "\n")`
  into an interactive zsh. On this host's heavy `~/.zshrc` (zle + bracketed-paste), the multi-line
  `if…then…fi` does not parse atomically → continuation prompts; the follow-up `\033[2J\033[H` clear
  (`:846`) is then absorbed as continuation input instead of clearing.
- The injection block was **last modified in `dafa6ba`** ("production-readiness batch", added the
  ghost-block suppressor) — **after** the May-30 run that PASSED on this same host (`b0374cb`). So this
  is a **post-May-30 regression** in the injection path, not a pre-existing limitation.
- Candidate fixes to investigate: wrap the injection in bracketed-paste markers / send it as a single
  `eval "$(printf …)"` or a temp-file `source`, or disable zle/bracketed-paste for the injection window;
  confirm the probe→script→clear timing still settles before `unifiedIntegrationReady`.

## Not run — needs the owner at the physical device
Biometric gate · push-notification approve-from-lock-screen (WS-5) · StoreKit sandbox purchase + Stripe
test-card checkout (WS-4/WS-6) · real Wi-Fi↔cellular reconnect/handoff (WS-1) · Live Activity / Dynamic
Island backgrounded (WS-7) · landscape on device · key import paste+file+passphrase on device (WS-3, also
covered by 253 green unit tests incl. encrypted-key parse).

## Go / No-Go for TestFlight beta
**NO-GO** until the live-session injection regression (#5) is fixed and re-verified on a real zsh host.
This is the app's core feature (Warp-style blocks over SSH) and it is currently broken on an
interactive-zsh host. Everything else verified clean. Once #5 is fixed, the remaining gate is the
owner-run device pass (push, billing sandbox, reconnect/handoff, Live Activity).

## Deviations / risks
- Cleared 5 stale tmux sessions on `127.0.0.1` (May-30 QA leftovers: idle prompts + 1 idle LancerKit
  Claude TUI) to reset the QA host. No active work lost.
- Dynamic Type/clipping cherry-pick (`b58b2aa`, recovered from worktree `c2a6f02`) is in this build;
  builds + 253 tests green.

---

## ADDENDUM — 2026-05-31 (later): P0 RESOLVED & re-verified → status flips to conditional GO

The injection regression (#5) was fixed (`031bf56`, ship-hardening batch) and **independently
re-verified on the real zsh host**. Verdict on the core blocker: **PASS**.

**Fix:** `ShellIntegrationScript.bootstrapForPOSIXShellsOneLine()` base64-encodes the whole bootstrap
into a single newline-free `eval "$(printf %s '<b64>' | base64 --decode)"` line; `SessionViewModel`
injects it after a `\r` ZLE-flush. No embedded newlines reach zsh's line editor, so the
continuation-prompt leak is gone.

**Verification (live, against `127.0.0.1` with the 428-line interactive `~/.zshrc`):**
- `ls` block → `✓ exit 0`, 1.07s, **output present** (no-output symptom gone); no `then>`/`function
  quote>` prompts; no echoed `__lancer_*` text; no rogue raw-terminal escalation. (`/tmp/ws10-verify-ls2.png`)
- DNS fast-fail: bad host → "Can't find host …" in ~2s, not the old 15s hang. (`/tmp/ws10-verify-dns.png`)
- Onboarding A (4-slide, animated demo + working macOS/Windows/Linux SSH tabs + inline API-key) and
  B (5-slide) both render; Premium Free-vs-Pro comparison screen renders; PixelBox neon halo added.
- bash 5.3: one-line eval mechanism check PASS. **fish: NOT installed on this host → untested.**

**Build-break caught during verification:** the hardening batch compiled under SPM (`swift build`/
`swift test`, Swift-5 concurrency) but **failed the Xcode app build** — `memoryWarningObserver` referenced
from the nonisolated `deinit` under strict concurrency. Fixed in **`523aedd`**
(`@ObservationIgnored nonisolated(unsafe)`, mirrors `PurchaseManager.transactionListener`). Lesson: the
Xcode app build (not just SPM) must be part of the done-check.

**Remaining gate:** owner-run device pass (push, billing sandbox, reconnect/handoff, Live Activity,
landscape) + fish-host injection + memory plateau under a long session. Minor: `OnboardingView.startAtStep`
is a dead (unused) parameter.
