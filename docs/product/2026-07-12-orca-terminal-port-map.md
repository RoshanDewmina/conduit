# Orca terminal → Lancer port map (2026-07-12)

**Last updated: 2026-07-15.**

Owner ask: "look at how Orca handles the terminal feature, then add full terminal support."
Method per AGENTS.md borrow-don't-reinvent (precedent: 2026-07-09 chat-ui port map).
Source: local clone `research-repos/orca` (MIT — portable with attribution comments;
React Native/Electron, so port protocols + state machines, re-implement UI in SwiftUI).

## Scope note (owner decision needed → given 2026-07-12)

This REVERSES the 2026-06-30 "no interactive terminal in V1" deferral. Lancer already has a
working SSH unified-PTY **block** terminal (SessionFeature/TerminalEngine, OSC-133 blocks,
alt-screen TUIs, tmux resume) that is merely unwired from the Cursor-shell nav. Orca has NO
block UI and NO tmux — Lancer is ahead on the rendering layer. What Orca has that Lancer
doesn't is (a) a **phone-usable interactive terminal** and (b) a **daemon-owned session layer**
that makes multi-client attach cheap.

## What Orca does (file:line evidence, from the 2026-07-12 research pass)

- **Custom detached PTY daemon, not tmux**: node-pty inside a detached/unref'd daemon that
  outlives the app (`src/main/daemon/daemon-init.ts:297-306,417,720`); create-or-attach with
  tombstones (`terminal-host.ts:81-84`); auto-respawn adapter (`daemon-pty-adapter.ts:933-990`);
  DEGRADED MODE keeps live sessions when PTY health checks fail (`daemon-init.ts:265`).
- **Server-side headless xterm mirror** (`@xterm/headless` + SerializeAddon,
  `headless-emulator.ts:1-40`, snapshot at `session.ts:275`): reconnecting clients get an O(1)
  serialized screen+scrollback snapshot instead of a raw-byte replay — this is what makes
  phone+desktop multi-attach cheap.
- **Self-compacting binary history log** (5MB → snapshot checkpoint, `history-manager.ts:25-30`)
  → cold restore of terminal contents across daemon restarts.
- **Mobile terminal is first-class and interactive**: xterm.js in a react-native WebView
  (`mobile/src/terminal/TerminalWebView.tsx`), E2EE WebSocket RPC (`rpc-client.ts:146,342,388-440`),
  `terminal.subscribe` with viewport + binary output frames. Direct raw-keystroke input is the
  DEFAULT (`mobile-terminal-direct-input-default.md`), with an accessory modifier bar
  (arrows/ctrl/esc/tab), dictation→PTY routing, IME mirroring, TUI mouse/wheel routing,
  tap-to-open file paths, selection-copy with haptics.
- **The agent's terminal IS the user's PTY** — Claude/Codex/opencode run as foreground
  processes in the pane PTY; "take over" = just type (foreground detection via OSC-133 +
  process recognition, `pane-foreground-agent-tracker.ts`). No ownership lock; shared by design.
- **Safety**: paste-ownership proven by raw-PTY-write spies across panes
  (`terminal-paste-ownership.spec.ts`); OSC-52 clipboard reads gated with a blocked toast.
- NOT features: no block UI, no tmux, no terminal→artifact extraction (that spec is a
  rendering-glitch repro).

## Port plan (phased; each phase independently shippable)

**Phase 1 — re-wire what exists.** Entry points in the Workspaces shell: Machine detail →
"Terminal" + thread ⋯ menu → "Open terminal at this cwd". Lancer's existing SSH block terminal
as-is. Gate: open terminal on the paired machine from the phone, run vim/htop, survive
app background. (This alone is "full terminal support" v0 — it worked in 2026-06 builds.)

> **Status 2026-07-16:** Phase 1 **shipped** on `cursor/desktop-history-and-terminal-3510`
> as a slim SwiftTerm surface (`LiveTerminalView`/`LiveTerminalModel`) — not the deleted
> block `SessionView` — with Trusted Machines → MachineDetail → Open Terminal, thread ⋯
> "Open terminal at this cwd", AppRoot fullScreenCover, TOFU + password sheet, and
> `SSHHostSetupSheet` when no Host is saved. Phase 2/3 still open.

**Phase 2 — daemon-owned terminal sessions (the real Orca lesson).** Move PTY ownership from
the phone-held SSH session into `lancerd` (it already survives disconnects for agent runs):
`terminal.create/attach/input/resize` RPCs over the existing E2E relay; daemon keeps a
serialized-screen mirror for O(1) attach snapshots (port headless-emulator concept — Go side
can use a vt10x-style emulator) + a self-compacting output log. Phone and Mac attach to the
same session; reconnect is instant. This also gives "type into the agent's PTY" (take-over)
for locally-launched agents.

**Phase 3 — mobile input UX kit.** Accessory key bar (esc/ctrl/tab/arrows), direct-input
default with buffered fallback, dictation routing, tap-to-open paths (route into thread/file
context), paste-ownership + OSC-52 gating. Port the DESIGN; SwiftUI implementation.

Risk class: Phase 1 ui · Phase 2 sensitive (relay protocol + daemon RPC surface — Sonnet/Fable
implementation + full-diff review per ENGINEERING_PROCESS) · Phase 3 ui.

## Decision record

- 2026-07-12 owner: "i want full terminal support" — scope reversal accepted; phases above.
- Recommended sequencing vs other asks: context/artifact uploads (#26, readiness-audit #1)
  first, then terminal Phase 1, then Phase 2/3 as their own lanes.
