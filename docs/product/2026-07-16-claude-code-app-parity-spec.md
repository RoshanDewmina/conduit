# Claude Code app → Lancer chat parity spec (owner directive 2026-07-16)

**Source:** owner screen recordings of the SAME session (`b9bb3038…`, "Physical iPhone dogfood
walkthrough") in both apps, 2026-07-16 20:36 (Claude Code app, 56 frames) vs 20:37 (Lancer,
26 frames). Owner directive: *"compare each, frame by frame and then copy its design and
features 1:1."* Frames archived in session scratchpad `cmp/{lancer,ccode}`.

**Baseline note:** the Lancer recording predates the `fix/thread-ux-polish` deploy — pr-link
JSON and stale chips shown there are already fixed (#154/#155). Gaps below are what REMAINS.

## Reference behaviors (Claude Code app, frame citations)

| # | Behavior | Frames | Lancer today |
|---|---|---|---|
| CC-1 | **Auto-follow scroll**: transcript follows streaming output smoothly while user is at bottom | whole video | Broken for within-turn growth — `scrollToTailIfFollowing` only fires on turn-COUNT change (`LiveThreadView` onChange), so live-followed/streamed text never scrolls |
| CC-2 | **Aggregated tool chips**: consecutive tool calls collapse into one row — "Ran 4 commands ›", "Ran a command, ran a command" never repeats; row expands | f45, f55 | One "Ran a command +0 −0" chip PER call; WT-B stuck-Running state |
| CC-3 | **Per-turn summary row**: "Used 6 tools, ran 2 commands, edited a… **+17 −2** ›" with real counts + diff stats, tappable | f03, f15 | "Worked 0s · Edited 12 files · +394 −61" — wrong duration (0s), not tappable |
| CC-4 | **Thought process rows**: each thinking block renders as collapsed "🕐 Thought process ›"; tap opens a full-height sheet with the reasoning text | f03, f45 (sheet) | "Thinking… ›" row exists; no expansion sheet, different styling |
| CC-5 | **Typography**: assistant prose in a serif face, larger leading, minimal chrome; user message in plain gray rounded block; monospace only for code/commands | all | Sans-serif everywhere, tighter leading |
| CC-6 | **Approval sheet**: "🔒 Bash wants to run:" bottom sheet — monospace command preview box, stacked buttons: black **Allow once**, secondary **Always allow this session**, Deny below | f03, f30 | Inline Command card with Deny/Approve pills + risk tag |
| CC-7 | **Live activity indicator**: pulsing orange spark/dot at transcript tail while the agent works; "Running ›" label on the active tool | f03, f30, f55 | Static spinner rows |
| CC-8 | **Mid-run composer**: placeholder "Queue for after this turn…", mode pill "‹/› Accept edits" (per-chat permission mode), mic button, **stop (■) button** | f55 | "Add feedback…" placeholder exists; no stop button in composer; mode pill is the dead autonomy pill (WT-A) |
| CC-9 | Scroll-to-bottom circular arrow pill | f15 | Already present (parity) |
| CC-10 | **Attachments render inline**: images as rounded thumbnails in the user bubble (tap → full screen), videos with a playable preview | owner screenshot 21:15 (generic PNG file icon in Lancer) | Generic file-type icon only |

## Verification workflow (owner directive: "thorough tests that our frontend looks exactly the same")

Repeatable parity gate, run per lane merge and before any deploy claim:

1. **Reference corpus**: the CC frames archived from the 20:36 recording are the ground truth
   (per-CC-item frame citations above).
2. **Sim drive**: on a Simurgh-leased sim, seed/drive the SAME conversation shape (send → tool
   chips → thinking rows → summary row → attachment message), screenshot each CC-item surface
   via XcodeBuildMCP/`simurgh exec` XCUITest.
3. **Side-by-side verdict**: one verdict row per CC-item — PASS only when the Lancer screenshot
   matches the reference frame's structure (element presence, grouping, states); typography
   items also owner-eyeballed on device (`ui` risk class).
4. Results land in `docs/test-runs/<date>-cc-parity/VERDICTS.md` with screenshot pairs.
   No lane is "done" on builder say-so — the verifier is never the author.

## Lanes (disjoint write-sets)

- **P-A (DONE inline by orchestrator)** — CC-1 follow-scroll: add within-turn-growth trigger.
- **P-CHIPS** — CC-2 + CC-3 + WT-B: aggregate consecutive tool events into one expandable
  row with counts; per-turn summary row with real duration + tappable; terminal-state fix so
  chips never claim Running after turn exit. Write-set: `AppFeature/Chat/` transcript
  card/chip components (new files ok) + `LiveThreadView` chip call sites.
- **P-THINK** — CC-4: collapsed Thought process row + expansion sheet. Write-set: thinking
  row component + sheet (new file), `LiveThreadView` call site. AFTER P-CHIPS merges (shared
  hub file).
- **P-TYPE** — CC-5: serif assistant prose (`.fontDesign(.serif)` / New York), leading,
  bubble styling per frames. Write-set: `DesignSystem` text styles + chat bubble components.
  AFTER P-THINK.
- **P-APPROVE** — CC-6: approval card → CC-style bottom sheet with Always-allow-this-session
  (wire to existing approveAlways). SENSITIVE (approval surface) → Sonnet/Fable implements.
- **P-COMPOSER** — CC-8: stop button (Emergency-stop-for-this-run), queue placeholder is
  parity already, mode pill becomes real per-chat permission mode = WT-A wiring (its own lane).

## Priority

Tonight: P-A (done) + P-CHIPS dispatch. Next session: P-THINK → P-TYPE → P-APPROVE → P-COMPOSER/WT-A.
