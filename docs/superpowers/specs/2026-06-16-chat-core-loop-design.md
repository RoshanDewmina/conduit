# Chat in the Core Loop — Design Spec

Date: 2026-06-16
Status: Approved (direction) — building

## Problem

Conduit's core loop is host-centric: connect SSH host → land on Fleet → drill into a slot's
full-screen block terminal to reach the agent. The "chat with an agent" surface exists in code
(`SessionView` + `SessionFeature/Chat/*`) but is buried, unlabeled, and absent from the design
board. There is a `DispatchView` (one-shot "start a task" composer with agent + model pickers)
but it is fire-and-forget and streams to a separate `RunDetailView`. Net effect: a new user has
no obvious "start chatting with an agent" entry point, and the board we are designing has no
page for it.

## Decisions (owner-approved)

1. **Chat-first, but Fleet stays home.** The post-onboarding landing remains the **Fleet** tab.
   Fleet's `+` button is repointed from "new task / add host" to **New Chat**.
2. **New Chat absorbs Dispatch.** The composer reuses DispatchView's fields (agent, model, cwd,
   budget), minimized and defaulted, and opens an **interactive chat transcript** (`SessionView`)
   instead of a fire-and-forget run. DispatchView is not deleted — it is promoted into this path.
3. **Fast, minimal config.** Nothing is required up front beyond a host existing.
   - **Agent** — choosable, defaults to the user's default agent (Claude).
   - **Workspace (host + cwd)** — choosable, defaults to last-used / only host.
   - **Model** — deferred. Defaults to the agent default ("Auto"). Lives in the **chat header**,
     switchable mid-session (Cursor/Warp pattern).
   - **Budget** — deferred. Behind an "Options" disclosure; default none.
4. **Zero-config `+`.** When the user has exactly one host and a default agent, `+` opens the
   chat directly (cursor focused) — no composer sheet. The composer sheet appears only when there
   is a choice to make (multiple hosts/agents). Agent/workspace remain editable from the chat header.

## Research basis (2026)

- **Cursor**: new chat opens with Agent + "Auto" model pre-selected; model picker at top of the
  chat panel, switchable mid-session. Per-mode default model is a requested-but-unshipped feature.
- **Warp**: "default mode for new sessions" setting; model selector lives *inside* the agent
  conversation (Claude/GPT/Gemini/Auto), multi-model by design.
- **Omnara** (closest competitor, Claude Code + Codex mobile): control laptop agents from phone,
  monitor/steer/approve live, voice. Their relay sees code — Conduit's E2EE is a differentiator.
- **OpenCode Mobile / AirCodum**: connect to self-hosted agent, stream + diff + tool approval.
- **Universal lesson**: nobody gates a new chat behind a model picker. Default the model, expose
  it in-session.

## Core loop (target)

```
Onboarding → connect host / relay-pair → FLEET (home)
  └─ Fleet: hosts/sessions list + prominent [ + New chat ]
       └─ + → (1 host: open chat directly · N hosts: New Chat composer) → CHAT transcript
            └─ agent runs → approval needed
                 └─ Inbox / inline approval card → approve / deny
                      └─ routes back to daemon → agent continues ✓
  Activity = history/audit   Settings = agents, keys, budget defaults
```

The approval half is already closed in code. This work adds the missing front half (chat entry).

## Deliverables

### A. Design board (static `.dc.html`, in `~/Downloads/Conduit GitHub repo/`)
1. **New page** `Conduit New Chat.dc.html` — composer states:
   - *Fast/zero-config*: `+` → chat opens directly (show the transition).
   - *Composer*: prompt input (autofocused), Agent pill, Workspace pill, collapsed Options
     (Model, Budget), Send.
   - *In-chat header*: agent + model switcher, mid-session.
2. **Fold into the combined board** via the existing manifest + `build-board.py` (V1 group, after
   Onboarding/Pairing).
3. Minor notes for Fleet (`+` = New chat) and Session Chat (header switcher + inline approval card)
   — captured as annotations, not necessarily new renders.

### B. Interactive clickable prototype (NEW self-contained HTML)
A single-page, no-build, tappable prototype so the owner can test flows and see what each button
does, including the onboarding animations we will ship.

- **Architecture**: `index.html` + a tiny vanilla-JS screen router. Design tokens copied from the
  board helmet `:root`. A phone-frame shell. Screens are registered into a global
  `CONDUIT_SCREENS` map; navigation via `data-goto="<screen-id>"`; enter/exit CSS transition
  classes drive animations. Parallel-safe authoring: one JS module per screen group.
- **Screens (core loop)**:
  1. `onboarding-welcome` — animated hero (spectrum sweep, pixel avatar).
  2. `onboarding-howitworks` — "agents ask / you approve / work resumes" sequence.
  3. `onboarding-connect` — connect host / relay pair.
  4. `fleet-home` — hosts/sessions + `+ New chat`.
  5. `new-chat` — fast composer (agent/workspace pills, options).
  6. `chat` — block transcript, agent working, in-header model switcher.
  7. `approval` — inline approval card / inbox; approve/deny.
  8. `chat-resumed` — agent continues after approval.
- **Interactions**: `+`, agent pill, send, approve/deny, back, tab bar all navigate for real.
- **Build method**: wave 1 proves the shell/router + contract with one screen (Claude verifies in
  browser by clicking through); wave 2 fills real screens in parallel (file-isolated JS modules).

## Verification
- Board: curl + headless-Chrome screenshot each page; confirm renders + folds into combined board.
- Prototype: load in headless Chrome, click through the full loop via `data-goto`, screenshot each
  transition, confirm navigation + animations fire and no console errors.
