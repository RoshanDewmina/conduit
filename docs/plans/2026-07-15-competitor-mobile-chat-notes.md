# Competitor mobile chat notes — 2026-07-15 night

Evidence: screen-recording frames under `/tmp/lancer-competitor-frames/{18,17,20}`
(ffmpeg `fps=1/2` from owner Downloads), tonight’s Lancer/device assets under
`~/.cursor/projects/.../assets/`, Orca clone `research-repos/orca` (**MIT**, Lovecast Inc.),
and existing port map `docs/product/2026-07-09-chat-ui-port-map.md` (paths below re-verified —
tool-fold/summary live under `src/renderer/.../native-chat/`, not `src/shared/`).

**App ID from branding (frames only):**

| Folder | Source video | Identity |
|---|---|---|
| `18/` | `ScreenRecording_…18.MP4` (~60s) | **Claude** early (greeting, sidebar “Claude”, “Chat with Claude”, “Sonnet 5 High”); mid/late frames switch to **Cursor**-style agent chat (workspace subtitle `conduit`, “Ran N commands” chips, Bash detail sheets) |
| `17/` | `ScreenRecording_…17-34-08_1.MP4` (~19s) | **Codex** (“Ask Codex”, home title “Remote”, machine `Roshans-MacBook-Air.local`) |
| `20/` | `ScreenRecording_…20.MP4` (~41s) | **Cursor** (Workspaces home, “Plan, ask, build…”, PR/diff review, Git/Repos filters) |

Tonight Lancer assets confirm: Workspaces+Agents home (`Screenshot_…10.27.54_PM`), reconnect failure
chat (`IMG_2551`), attachment-as-raw-path (`IMG_2540`). Claude consumer chat (`IMG_2545`) and Gemini
(`IMG_2547`) are additional consumer-chat references, not coding-agent peers.

---

## 1. Claude (folder `18` early + `IMG_2545`)

### Chat layout
- Empty home: centered serif greeting (“Good evening, Roshan”) + brand glyph; vast negative space (`18/frame_0002`, `0005`).
- Active chat: **user = right grey bubble**; **assistant = full-bleed** (serif on light, sans on dark) (`IMG_2545`).
- Sidebar: Chats / Projects / Artifacts / Code / Dispatch + Recents + bottom “New chat” (`18/frame_0008`).

### Tool / process rendering
- Consumer Claude: collapsible **“Thinking…”** row with clock + chevron; no Bash wall (`IMG_2545`).
- (Mid-recording Cursor frames — see §3 — show the coding-agent chip pattern, not Claude consumer.)

### Approvals / permissions
- Not visible in Claude-branded frames. Usage limit card above composer (“95% of weekly limit” + Upgrade) (`IMG_2545`).

### Composer
- Floating bar: `+` · **model chip “Sonnet 5 High”** · mic · voice-waveform (`18/frame_0005`).
- In-thread: “Reply to Claude” + same model chip (`IMG_2545`).

### Navigation / home
- Drawer-first; Recents titles single-line truncated; search FAB on list (`18/frame_0008`).

### Port to Lancer
- Keep user-bubble / assistant-full-bleed (Lancer already close — `IMG_2540`).
- Put **model/agent chip inside composer** (Claude’s “Sonnet 5 High”), not only in a prior picker.
- Collapsible thinking row — Lancer already has `ThinkingRow`; ensure observed transcripts don’t dump thinking as prose.

---

## 2. Codex (folder `17`)

### Chat layout
- User right bubble; assistant full-bleed left (`17/frame_0003`, `0009`).
- Header: truncated title + subtitle `repo · machine` (`command-ce… · Roshans-Ma…`).

### Tool / bash / terminal
- **No “Bash: …” markdown.** Status as thin grey chevron rows: `Worked for 1min 28s >` (`17/frame_0003`).
- Diff / change chips: file path + `+N -M` color; floating “24 files +2.1K -141” (`17/frame_0003`, `0005`).
- Artifact blocks labeled **“Plain text”** + copy — monospace in a rounded card (`17/frame_0009`).
- Context pill above composer: `24 files` / `chat` / `claude` / `code instance` (`17/frame_0009`).

### Approvals
- Not shown in this short recording.

### Composer
- “Ask Codex” · `+` · mic · speaker; scroll-to-bottom FAB (`17/frame_0003`).

### Navigation / home
- **“Remote”** home: green machine indicator + chronological thread groups (Today / N days ago) (`17/frame_0001`).
- Bottom: Search Chats + pink **Chat** CTA.
- Files sheet: Modified / All Files toggle + bottom “Search files” (`17/frame_0007`).

### Port to Lancer
- Replace tool-as-markdown with **duration/activity row** (“Worked Xm Ys”) — Lancer has `TurnActivitySummary`; wire it on observed path too.
- Floating **files-changed** chip (Codex “24 files +2.1K”) over composer — high leverage for desktop-session review.
- Home: machine-alive indicator + date-grouped thread list (Codex Remote) vs Lancer’s Workspaces+Agents split.

---

## 3. Cursor (folder `20` + mid/late `18`)

### Chat layout
- Full-bleed agent prose; user bubbles; workspace subtitle in nav (`18/frame_0010`, `0022`).
- Workspaces home + persistent “Plan, ask, build…” composer (`20/frame_0001`; Lancer tonight screenshot mirrors this shell).

### Tool / bash / terminal (highest steal value)
- Collapsed one-liners with chevron: `Ran 2 commands, used a tool >`, `Ran 4 commands >` (+ red warning when a command failed) (`18/frame_0010`).
- Natural-language aggregates: `Edited a file +0 -6 >`, `Read a file, edited a file, ran a command +1 -5 >` (`18/frame_0030`).
- Tap → **bottom sheet** with stepper icons (eye/pencil/terminal), truncated mid-path filenames, per-row `+N -M` (`18/frame_0010`, `0030`).
- Single Bash drill-in: title “Bash”, labeled Command block + Output block — **not** “Bash Bash:” (`18/frame_0015`, `0012`).
- PR review: full-bleed diffs, “N unmodified lines” collapse, `+added -removed · N Files` header (`20/frame_0012`, `0020`).

### Approvals
- Not in Cursor-branded frames. (Light-mode “Needs your approval” card in `18/frame_0025` looks like a separate agent UI — treat as pattern only: **inline approval card in-thread**, orange attention dot.)

### Composer
- Shell-level `safeAreaInset` composer (recording itself describes detaching from sheet) (`18/frame_0020` prose).
- Home + thread share floating pill; scroll-to-bottom FAB.

### Navigation
- Workspaces → All Repos Recents with diff stats (`20/frame_0010`).
- Repos / Git visibility toggles (`20/frame_0005`, `0008`).

### Port to Lancer
- **P0:** observed transcript must emit **ToolCallChip** groups (Cursor “Ran N commands”), not `ChatMarkdownBody` walls — Lancer already has `ToolCallChipView` / `TurnTranscriptAssembler` for live/event path; observed path bypasses them.
- Bottom-sheet expand for chip groups (Cursor) before inventing a full BlockRenderer for observed SSH.
- Diff stats on chips + floating review pill (`20/frame_0020` “Review +2,768 −7,447”).

---

## 4. Orca codebase (MIT — portable with attribution)

License: `research-repos/orca/LICENSE` — MIT, Copyright (c) 2026 Lovecast Inc.

| Pattern | File:line (verified) | Port to Lancer |
|---|---|---|
| Fold tool-only messages under preceding assistant | `src/renderer/src/components/native-chat/native-chat-tool-fold.ts:28-39` | Observed `SessionMessage` stream: keep tools out of prose; attach to current turn (same fold rule) |
| Split prose vs tools for render | `native-chat-tool-fold.ts:44-58` | `assistantText` = prose only; chips = tools |
| One-line run summary `"Bash git status · Edit app.tsx"` | `native-chat-tool-summary.ts:43-58` | Already mirrored in `TurnTranscriptAssembler.groupedChipTitle` (comment cites Orca) |
| Cap tool result preview | port-map / assembler `detailByteCap = 4096` | Keep; apply to observed `resultText` |
| Setup-hook trust by content hash | `mobile/src/tasks/setup-hook-trust.ts:8-37` | Approvals: content-hash + repo/machine scope (Lancer already content-hashes; missing **home Inbox surface**) |
| Mobile session = PTY-first | `mobile/app/h/[hostId]/session/[worktreeId].tsx` (large; terminal-centric) | Lancer SSH path uses BlockRenderer; **observed Claude transcript path does not** — intentional gap until P1 |

Orca mobile is primarily a **remote terminal + worktree** client, not a bubble chat peer. Steal fold/summary algorithms (already partially ported); do not copy terminal-webview UI wholesale for Claude JSONL review.

---

## 5. Lancer gaps confirmed tonight

1. **“Bash Bash:”** — daemon `claudeToolUseSummary` → `Text = "Bash: …"` + `ToolName = "Bash"` (`claude_transcript_adapter.go:255-262,320-336`); iOS `LiveThreadTranscript` prepends `toolName+"\n"` (`LiveThreadTranscript.swift:120-130`); no events/artifacts → `ChatMarkdownBody` (`LiveThreadView.swift:576-592`).
2. **Approvals machine-scoped** in `LiveThreadView` only; Workspaces home has no Inbox (orchestrator-state + `20`/`Screenshot` home frames show no approval entry).
3. **BlockRenderer** for live SSH; observed transcript path is markdown-only.

---

## 6. Recreation plan — P0 → P2

### P0 — Observed chat render (this change)
**Write-set:** `LiveThreadTranscript.swift`, `SessionMessage` (decode `toolUseId`/`inputJson` if present), `ShellLiveBridge.swift`, `LiveThreadView.swift` (merge observed artifacts), `LiveThreadTranscriptTests.swift`.
**Do:** (1) stop double-label; (2) prose-only `assistantText`; (3) map `toolCall`/`toolResult` → `ChatArtifact.kind == .tool` → existing `ToolCallChipView`.
**Don’t:** Inbox/push redesign; BlockRenderer for observed.
**Accept:** Adopt Claude session with Bash tools → chips (or single “Ran N commands” group), no “Bash Bash:” substring; `swift build` + transcript tests green.

### P1 — Approvals discoverability
**Write-set:** Workspaces home “Needs attention” / Inbox entry; keep machine-scoped decide in-thread; push resend when unpaired (daemon `e2e_router`).
**Accept:** Pending approval visible from Workspaces without opening the live thread; unpaired push does not silently vanish without UI signal.

### P1b — Activity + files chip
**Write-set:** Wire `TurnActivitySummary` on observed turns; floating files/diff chip (Codex/Cursor).
**Accept:** Completed observed turn shows “Worked Xm”; multi-file edit shows aggregated `+N -M`.

### P2 — Expand sheet + terminal depth
**Write-set:** Chip tap → bottom sheet (Cursor stepper); optional BlockRenderer bridge for observed bash output when PTY available.
**Accept:** Tap chip → Command/Output detail without leaving thread; long logs not inline.

---

## Top 5 steal-worthy patterns (owner digest)

1. Cursor/Codex **collapsed tool summary chips** with chevron + bottom-sheet detail (never dump Bash markdown).
2. Codex **“Worked for …”** activity row separating status from prose.
3. Cursor **diff stats on chips** (`+N -M`) and floating Review pill.
4. Claude **model chip in composer** + thinking collapse.
5. Codex Remote **machine-alive + date-grouped thread home** (approvals/attention belong here too).
