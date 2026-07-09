# Orca-informed Cursor shell rebuild — Phase R design note

**Date:** 2026-07-09
**Scope:** Phase R (read-only research) for `docs/plans/2026-07-09-fable-frontend-shell-rebuild-brief.md`.
**Donor:** `research-repos/orca` (gitignored clone of `stablyai/orca`), **MIT** — verified at
`research-repos/orca/LICENSE:1-3` ("MIT License / Copyright (c) 2026 Lovecast Inc."). Patterns + logic
below are portable with attribution; no verbatim React/RN code is copied — everything is
re-implemented in SwiftUI against `CursorShellLiveBridge`.

Happier/Omnara were not needed for this pass — every behavior gap below had a direct Orca precedent
with clear file:line evidence, and the brief scopes Happier/Omnara to "patterns only, already
sketched in the port map" (`docs/product/2026-07-09-chat-ui-port-map.md`), which this note treats as
already covered background rather than re-deriving.

---

## 1. Post-pair → land on that machine/workspace

**Donor:** `research-repos/orca/mobile/app/pair-confirm.tsx:146-160`

```ts
const hostId = `host-${Date.now()}`
const hostName = await getNextHostName()
await saveHost({ id: hostId, name: hostName, endpoint: offer.endpoint, ... })
...
router.replace(`/h/${hostId}`)
```

Orca's pairing screen saves the host, then **replaces** the current route (not push) with the new
host's detail screen (`/h/${hostId}`) — the user never lands back on a settings/pairing list; they
land directly *inside* the thing they just paired.

**Port to Lancer:** `CursorRelayPairingSheet`'s `onChange(of: client.pairingState)` handler currently
only calls `onPaired(client, record)` then `dismiss()` — it never selects a workspace. The rebuilt
sheet must, on the same success edge:
1. Call `onPaired` (unchanged bridge contract — `AppRoot.addRelayMachine`).
2. Dismiss the pairing sheet **and** dismiss any parent Settings/onboarding sheet that's still on
   screen (atomic dismiss chain, not a second manual tap).
3. Switch the shell's active root to **Workspaces** and clear any stale `selectedThreadID`, mirroring
   `router.replace` semantics (replace, don't push) so back-navigation doesn't return to the pairing
   sheet.

Implemented in `CursorAppShell.swift` via a `postPairLandingRequest` callback threaded from
`CursorRelayPairingSheet` → shell root switch, attributed inline.

---

## 2. Start chat from named workspace always opens the thread

**Donors:**
- `research-repos/orca/src/renderer/src/lib/launch-agent-in-new-tab.ts:97` (`launchAgentInNewTab`) —
  creates the tab, flips `activeTabType` to the new surface, and queues startup **before** returning,
  so a successful launch is never left showing the old surface.
- `research-repos/orca/src/renderer/src/components/native-chat/native-chat-pending.ts:136-160`
  (`pendingSendsAsMessages`) — a sent prompt is turned into an optimistic message immediately, shown
  in the transcript before any server ack.

**Port to Lancer:** the old `CursorAppShell.composerSheetChain.onSend` already pushes
`CursorRoute.workThread(nil)` right after calling `onDispatch`/`onContinue` — that part is correct and
is preserved. The gap is workspace **CWD resolution**: `composerResolvedCWD` reports `blocked` (with a
"path unknown" message) whenever `repoPaths[repoName]` has no entry and no thread has been opened yet
for that repo, and the rebuilt docked composer disables Send in that state — matching Orca's rule that
a launch never fires from an unresolved target, but the UI must make the *reason* visible right on the
docked bar instead of only inside a modal composer sheet's small text line.

---

## 3. Docked composer / keyboard not full-screen

**Donor:** `research-repos/orca/src/renderer/src/components/native-chat/NativeChatView.tsx:403-405`

```tsx
<div className="flex h-full min-h-0 w-full flex-col ...">
  <div className="flex min-h-0 flex-1 flex-col">   {/* transcript: flex-1, scrolls */}
    ...
  </div>
  {/* composer renders after, sized to content — shrink-0 in the surrounding flex column */}
</div>
```

Orca's chat column is `flex-col`: the message list is `flex-1 min-h-0` (grows, scrolls, never pushed
off-screen) and the composer is a fixed-height sibling below it (`shrink-0`) — never an overlay/sheet.

**Port to Lancer:** replace `CursorComposerSheet` (`.sheet` with `.presentationDetents([.height(380),
.large])`, which the audit and owner both flagged as effectively going full-screen once the keyboard
and contract disclosure expand) with a **docked** `CursorDockedComposer` pinned via
`.safeAreaInset(edge: .bottom)` directly on the thread/list column — same mechanism
`CursorWorkThreadView` already used for `CursorBottomComposer`, except the new component is the real
editable field (not a tap-target proxy into a sheet). SwiftUI's safe-area inset naturally lifts with
the keyboard without a `.large` sheet ever appearing.

---

## 4. 2nd+ message live update (no leave/reopen)

**Donor:** `research-repos/orca/src/renderer/src/components/native-chat/native-chat-pending.ts:118-160`

```ts
export function prunePendingSends(pending, messages): NativeChatPendingSend[] {
  const advanced = advancedPastUserMessageTexts(messages)
  return pending.filter((entry) => !advanced.has(normalize(entry.text)))
}
export function pendingSendsAsMessages(pending, ...): NativeChatMessage[] { /* optimistic bubbles */ }
```

Orca keeps an optimistic "pending send" as its own synthetic message until the **real transcript
provably advances past it** (matched by normalized text), never clearing it just because a timer or a
single status flag flipped. This is exactly the bug class the brief calls out for Lancer's Nth turn.

**Root cause found in `CursorTranscriptMapper.makeRows` (file:line
`Packages/LancerKit/Sources/AppFeature/CursorStyle/CursorTranscriptMapper.swift:74-90`, pre-rebuild):**
the live overlay is only ever attached to the **last persisted turn** (`isLast`). On turn 1 this is
correct — `sortedTurns` is empty, so the overlay renders as its own synthetic row. But on turn 2+
(`onContinue`), turn 1 is already persisted, so the "last turn" is turn 1, and the live overlay
(carrying turn 2's new prompt + in-flight response) gets silently attached to turn 1's `TurnSection` —
which only forwards `response`/`isWorking`, never the overlay's `prompt`. The new user bubble for turn
2 has nowhere to render until the daemon round-trip finishes and `CursorThreadTranscriptModel.reload()`
re-pulls turn 2 from the ledger — exactly the "stale until reopen" symptom.

**Fix (this is the one engine file the brief allows Fable/executor to patch):** treat the overlay as a
**new pending turn** (Orca's `pendingSendsAsMessages` — a synthetic row, not a graft onto the last real
row) whenever `liveOverlay.prompt != sortedTurns.last?.prompt` (i.e., the live prompt has already moved
past what's persisted), instead of only when `sortedTurns.isEmpty`. Implemented in
`CursorTranscriptMapper.swift` — see `overlayIsNewPendingTurn` in the rebuilt file, ported comment
attributes Orca `native-chat-pending.ts`.

---

## 5. Markdown + tool/artifact cards

**Donor:** Lancer's own `CursorAssistantMarkdownView` / `CursorMarkdownPreprocessor` (already landed,
Slice 1 polish, `fa04426f`) already implements "prose then tools; fold + summary" per the port map;
Orca's fold/summary pattern was already mined for that slice. No new porting needed here — Phase B
keeps calling the existing engine unchanged (`ReceiptCardView` for `.receipt`, `QuestionCardView` for
`.question`).

---

## Files ported into (with attribution comments)

| Lancer file (new) | Orca donor | What's ported |
|---|---|---|
| `CursorAppShell.swift` (rebuilt) | `mobile/app/pair-confirm.tsx:146-160` | Atomic dismiss → root-switch → workspace select on pair success |
| `CursorRelayPairingSheet.swift` (rebuilt) | `mobile/app/pair-confirm.tsx:146-160` | `router.replace` semantics → shell root replace, not push |
| `Components/CursorDockedComposer.swift` (new) | `NativeChatView.tsx:403-405` | `flex-1` transcript / `shrink-0` composer column via `safeAreaInset` |
| `CursorTranscriptMapper.swift` (patched) | `native-chat-pending.ts:118-160` | Pending-send-as-synthetic-row until transcript provably advances |
| `CursorWorkThreadView.swift` (rebuilt) | `native-chat-autoscroll.ts:26-44` | (unchanged from pre-rebuild — already ported in Slice 1; carried forward as-is into the new file) |

No Happier or Omnara ports were needed this pass; both were already mined for Slice 1
(`CursorStreamingTextSmoother`/`CursorStreamingTextPacer`, existing attribution comments preserved
verbatim in the KEEP engine files).
