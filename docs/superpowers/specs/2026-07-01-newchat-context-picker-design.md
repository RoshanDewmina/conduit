# New Chat context picker — consolidate Machine/Agent/Model — design

Date: 2026-07-01
Status: approved (design); implementation in progress

## Problem

New Chat's composer has three separate entry points for configuring a run: a Machine
picker (`showMachinePicker`), an Agent picker (`showAgentPicker`), and a Model `Menu`
buried inside the "Run settings" options drawer (`optionsPanel`). That's three taps
across two different sheets to do one job — pick where and how a run executes — and
the composer row itself shows the agent + machine as two separate chips plus a
generic "…" options button.

There's also a real, reported UX bug: `agentPickerRow`'s tap action does
`guard !agent.isOffline else { return }` — an offline agent's row renders exactly like
a tappable row (same background, same "chevron"-less list style) but silently no-ops
on tap. The owner reported "I can't click on the Claude Code button", which is this
guard firing on an offline-marked Claude Code agent with no visible explanation.

## Decision (from brainstorm — reviewed 3 interactive prototypes, picked Variant B)

`docs/lancer-ui-prototype/app/chat-context/{a,b,c}/page.tsx` prototyped three variants
of a consolidated context picker. **Variant B ("one combined sheet")** was chosen:
one pill in the composer opens a single sheet with **Machine**, **Workspace**, and
**Model** as three always-visible sections in a scroll view (not a stepped/paginated
flow) — each section has a mono-uppercase label header, then a vertical list of rows
(icon + label + sub-label + checkmark on the selected row).

### Agreed design

1. **Replace three entry points with one sheet.** `showAgentPicker`, `showMachinePicker`,
   and the Model `Menu` in `optionsPanel` are removed. A single `showContextPicker: Bool`
   drives one sheet (`contextPickerContent`) with three sections, all visible at once:
   Machine → Workspace → Model, matching `chat-context/b/page.tsx`'s layout.
2. **Selecting a Machine resets Workspace** to that machine's default cwd (carries over
   today's `machinePickerContent` behavior: `selectedCwd = ""` on machine change). It
   also resets the selected model, since models are vendor-specific and a stale model id
   from a different vendor is meaningless once the machine (and its default agent) changes.
3. **Budget cap stays where it is today** — not folded into the new context sheet. It
   remains behind a small "Options" affordance, now budget-only since Model moved out.
   The former "Run settings" drawer (which held Machine/Agent/Workspace pills + the
   Model menu + budget field) shrinks to just the budget field + Done.
4. **Composer row**: the agent+machine chip and the "…" options button collapse into
   ONE pill showing `"<machine> · <workspace-last-path-component> · <model-short-label>"`
   on a single line, opening `showContextPicker`. A separate small budget-only button
   remains alongside it (point 3). If the combined pill string doesn't fit, the
   **workspace segment drops first** (via `ViewThatFits` falling back to
   `"<machine> · <model>"`) — same truncation-priority pattern as `LancerHomeView`'s
   `approvalSubtitle` (which drops the host segment first at large Dynamic Type), applied
   here to available width rather than type size.
5. **Resume-last-selection**: the last-used machine / workspace / model are persisted via
   three `@AppStorage` keys (`lancer.newChat.lastMachine`, `lancer.newChat.lastWorkspace`,
   `lancer.newChat.lastModel`) and restored on next New Chat entry instead of always
   defaulting to "first online agent". If the persisted machine/agent no longer exists or
   has gone offline, fall back to today's default-picking logic — no crash, no empty state.
6. **Fix the offline-agent no-op bug.** In the new sheet, Machine rows are disabled
   (dimmed, `.disabled(true)`) when every agent on that machine is offline; Model rows
   are disabled per-agent when that agent is offline. No more silently-inert-but-looks-
   tappable rows.

## Architecture

- `contextPickerContent`: `ScrollView` with three `contextSection`s (Machine, Workspace,
  Model) built from data that already exists in `NewChatTabView` — `groupedAgents`,
  `projectDirs`, `ModelCatalog.models(for:)` — plus a shared `contextRow` helper (icon,
  label, sub-label, selected checkmark, disabled dimming).
- **Model section** is scoped to the currently-selected machine (mirrors today's
  `agentPickerContent` scoping) and sub-grouped by agent/vendor, since
  `ModelCatalog.models(for:)` is vendor-specific. Each agent's group has an "Auto (agent
  default)" row plus one row per model. Selecting a Model row sets **both** the agent
  (`selectedAgentID`) and the model (`selectedModel`) — this is how Model absorbs the old
  Agent picker's job instead of duplicating it as a fourth section.
- **Workspace section** keeps the existing `projectDirs` quick-pick list and the
  "type a custom path" `TextField` + "Use" button from today's `workspacePickerContent` —
  same functionality, moved in-place. Rows no longer auto-dismiss the sheet on tap (all
  three sections are editable in one sitting); an explicit "Done" button at the bottom
  closes the sheet, matching the prototype.
- `ModelCatalog.vendor(forModelID:)` (new, small reverse lookup) lets the restore logic
  recover which vendor a persisted model id belongs to, without needing a fourth
  persisted "agent" key.

## Out of scope

- Any daemon (`daemon/lancerd/`) or relay protocol change — purely a client-side sheet
  consolidation; all data (`agents`, `groupedAgents`, `ModelCatalog.models(for:)`,
  `projectDirs`) already exists and is already fetched by the current code.
- Folding the budget cap into the new context sheet (point 3) — it stays a separate,
  smaller "Options" affordance.
- `docs/lancer-ui-prototype/` — reference only, not modified further.

## Testing / verification plan

1. `cd Packages/LancerKit && swift build` — zero errors.
2. XcodeBuildMCP app-target build (`Lancer` scheme, `iPhone 17 Pro` simulator, Debug) —
   zero errors. This is required because plain `swift build` skips `#if os(iOS)` code
   and this view is iOS-only.
3. Not device-installed or launched as part of this change — the owner is actively
   testing other things live on a paired physical iPhone; verification here is build-only,
   left for the owner to exercise on-device.
