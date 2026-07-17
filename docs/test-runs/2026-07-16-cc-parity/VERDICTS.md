# CC parity verdicts — 2026-07-16

Spec: `docs/product/2026-07-16-claude-code-app-parity-spec.md` (CC-1..CC-10).
Harness: `LancerUITests/CCParityScreenshots.swift`, run via `scripts/cc-parity-run.sh`
on a Simurgh-leased `iPhone 17 Pro` simulator.

Reference frames from the Claude Code app recording (`cmp/ccode/*`) are **not** in this
repo — they live in the session scratchpad that produced the spec. This doc records the
Lancer-side screenshot + an honest reachability note per item; a human (or a session with
the archived frames) fills in the Verdict column.

**Reachability caveat (read before verdicting):** this harness has no live daemon/relay
connection, and no DEBUG seam seeds a persisted conversation transcript. `CC-2/3/4`
(aggregated tool chips, per-turn summary, thinking rows) only exist in the app after a real
agent turn completes tool calls — that state is not reachable offline. Those rows are
verified elsewhere by inspection of `AppFeature/Chat/ToolCallChipView.swift`,
`TurnActivitySummaryRow.swift`, `ThinkingRow.swift`, not by this harness. This harness
captures the richest reachable DEBUG-seam surface instead (an approval-driven live thread:
real user-prompt bubble + "Couldn't get a reply" no-machine card + seeded Command approval
card + follow-up composer) and says so plainly rather than fabricating a match.

| # | Behavior | Reference (frame citation) | Lancer screenshot | Reachability | Verdict |
|---|---|---|---|---|---|
| CC-1 | Auto-follow scroll | whole video | `lancer/cc-1-follow.png` | Partial — captures `ThreadDetailView` empty state (no seeded transcript exists to scroll); follow-scroll behavior itself is not exercisable by this harness | |
| CC-2 | Aggregated tool chips ("Ran 4 commands ›") | f45, f55 | `lancer/cc-2-chips.png` | Gap — no tool-chip content reachable offline; screenshot shows the no-connected-machine fallback instead | |
| CC-3 | Per-turn summary row (real duration/diff stats, tappable) | f03, f15 | `lancer/cc-3-summary.png` | Gap — no turn-complete summary reachable offline; same fallback screenshot as CC-2 | |
| CC-4 | Thought process rows + expansion sheet | f03, f45 (sheet) | `lancer/cc-4-thinking.png` | Gap — no thinking-block content reachable offline; same fallback screenshot | |
| CC-5 | Typography (serif assistant prose, plain gray user bubble, monospace only for code) | all | `lancer/cc-5-typography.png` | Partial — real user-bubble typography is on screen; no assistant prose renders (no live reply), so serif-face parity is not verified by this screenshot | |
| CC-6 | Approval sheet ("🔒 Bash wants to run:" bottom sheet) | f03, f30 | not captured (out of this harness's required item list) | — | — |
| CC-7 | Live activity indicator (pulsing dot, "Running ›") | f03, f30, f55 | not captured (out of this harness's required item list) | — | — |
| CC-8 | Mid-run composer (queue placeholder, mode pill, mic, stop button) | f55 | `lancer/cc-8-composer.png` | Partial — follow-up composer + permission-mode pill are real; mid-run "Queue for after this turn..." placeholder and stop (■) button only render during an in-flight run, unreachable offline | |
| CC-9 | Scroll-to-bottom pill | f15 | not captured (owner already marked parity in the spec) | — | — |
| CC-10 | Inline attachment thumbnails | owner screenshot 21:15 | not captured (separate harness: `AttachmentPreviewUITests.swift`, `docs/test-runs/2026-07-14-attachment-preview-thumbnail-and-file-card.png`) | — | — |

## How to re-run

```bash
scripts/cc-parity-run.sh
```

Acquires its own Simurgh lease, runs `CCParityScreenshots` through `simurgh exec`, copies
the `.xcresult` and extracted PNGs into `docs/test-runs/2026-07-16-cc-parity/lancer/`, and
releases the lease on exit (including on failure, via `trap`).

**2026-07-16 ~21:50 note (orchestrator):** the first end-to-end run completed (xcodebuild-test.log retained) but the session died before attachment extraction; the Simurgh lease Results dir was reclaimed, so the PNGs are unrecoverable — re-run `scripts/cc-parity-run.sh` to regenerate. Structural follow-up: add a `LANCER_SEED_TRANSCRIPT` DEBUG seam that seeds a persisted conversation (tool chips + thinking + summary + attachments) so CC-2/3/4/10 become offline-verifiable — without it this harness can only reach approval-card surfaces.
