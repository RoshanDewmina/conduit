# Web Live Blocks + Reply-to-Agent — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Next.js web dashboard shows the live block/run transcript of an agent session (like the iOS block terminal) and lets the user send a text reply back to the running agent — all over the existing blind relay.

**Architecture:** The daemon **already streams** terminal output to the relay as JSON-RPC notifications mapped to `agentRunOutput`/`agentRunStatus` (`e2e_router.go:171-174`), and the iOS app already consumes them. The web relay client silently **drops** these because `decodeInbound` is a 3-type allowlist (`codec.ts:14`). So the **read** side is mostly "stop dropping + render": extend the web types/codec/store and add a transcript component. The **reply** side is the real gap — there is no agent stdin path (`realLauncher` opens no stdin pipe; `agentRunContinue` is sent by iOS but unhandled by the daemon). This plan delivers reply via `tmux send-keys` into the Conduit-managed tmux session (the container created by the Session-Continuity Shim plan), which is the clean, already-available write path.

**Tech Stack:** Next.js 16 / TypeScript (`web/`), zustand store, `@noble` relay crypto (existing), Go daemon (`daemon/conduitd/`), tmux.

## Global Constraints

- **The browser cannot SSH** — the web app's ONLY channel to the daemon is the blind relay. Block output and replies must travel over relay message types, not the SSH/tmux path the iOS app uses. (verified)
- **`bun` only** for web (`cd web && bun run build` / `bun test` are the authoritative gates). Never npm/yarn/pnpm.
- **Daemon already emits** `agent.run.output`/`agent.run.status` → `agentRunOutput`/`agentRunStatus` over relay (`e2e_router.go:150-177`). Do not add a parallel stream; consume the existing one. (verified)
- **Reply requires a writable session.** One-shot dispatch runs (`claude -p …`) have no stdin and exit on completion — replying to those is a *new dispatch*, not a continuation. True conversational reply targets the **tmux-managed** session via `tmux send-keys` (depends on the Session-Continuity Shim plan's tmux container). Scope reply-to-agent to tmux-backed sessions; for dispatch runs, expose "send as new run" instead. (verified gap)
- **First-class relay parity:** any new message type added on the web (TS) side must have the matching daemon (Go) handler; the Swift `agentRunContinue` already exists but is orphaned — fixing the daemon handler benefits iOS too. (verified)
- **Do NOT `git commit` unless the user explicitly asks.**

---

## File Structure

| File | New/Mod | Responsibility |
|---|---|---|
| `web/lib/relay/types.ts` | Mod (`:37-63`) | Add `InboundAgentRunOutput`/`InboundAgentRunStatus` to `InboundAppMessage`; add `AgentReply` outbound. |
| `web/lib/relay/codec.ts` | Mod (`:14-18`) | Accept `agentRunOutput`/`agentRunStatus` in `decodeInbound`; add `encodeAgentReply`. |
| `web/lib/relay/client.ts` | Mod (`:81-86`) | Add `sendRunContinue(runId, text)` mirroring `sendApprovalResponse`. |
| `web/lib/store/useConduitStore.ts` | Mod (`:18-68`) | Add `runs: Record<string, RunState>` slice; `ingest` accumulates chunks by `seq`, tracks status. |
| `web/lib/store/runState.ts` | New | `RunState` type + pure chunk-merge/dedup (mirrors iOS `RunOutputStore.Run`). |
| `web/components/BlockTranscript.tsx` | New | Renders ordered run chunks with block/stream styling. |
| `web/components/ReplyBar.tsx` | New | Text input + send → `sendRunContinue`. |
| `web/app/agent/[id]/page.tsx` | Mod (`:86-93`) | Replace the "coming to web" placeholder with `BlockTranscript` + `ReplyBar`. |
| `web/lib/store/runState.test.ts` | New | Chunk merge/dedup tests. |
| `web/lib/relay/codec.test.ts` | Mod | `decodeInbound` accepts the two new types; `encodeAgentReply` round-trip. |
| `daemon/conduitd/e2e_router.go` | Mod (`:85-144`) | Add `case "agentRunContinue":` → `applyRunReply(runId, text)`. |
| `daemon/conduitd/run_reply.go` | New | `applyRunReply`: resolve run → tmux session → `tmux send-keys -t <name> <text> Enter`. |
| `daemon/conduitd/run_reply_test.go` | New | Faked tmux; asserts send-keys invocation. |

---

## Task 1: web relay types + codec accept run output/status

**Files:**
- Modify: `web/lib/relay/types.ts`, `web/lib/relay/codec.ts`
- Test: `web/lib/relay/codec.test.ts`

**Interfaces:**
- Produces:
  - `type RunOutputChunk = { runId: string; stream: "stdout" | "stderr"; chunk: string; seq: number }`
  - `type RunStatusUpdate = { runId: string; status: string; exitCode?: number }`
  - `InboundAppMessage` grows: `| { type: "agentRunOutput"; payload: RunOutputChunk } | { type: "agentRunStatus"; payload: RunStatusUpdate }`
  - `type AgentReply = { runId: string; text: string }` + `encodeAgentReply(reply, key)`.

- [ ] **Step 1: Write the failing codec test**

```ts
import { test, expect } from "bun:test";
import { decodeInbound } from "./codec";
import { encryptFrame, textEncode } from "./crypto";

test("decodeInbound accepts agentRunOutput", () => {
  const key = new Uint8Array(32);
  const plain = JSON.stringify({ type: "agentRunOutput", payload: { runId: "r1", stream: "stdout", chunk: "hi", seq: 1 } });
  const frame = encryptFrame(textEncode(plain), key);
  const msg = decodeInbound(JSON.stringify(frame), key);
  expect(msg?.type).toBe("agentRunOutput");
  expect((msg as any).payload.chunk).toBe("hi");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd web && bun test lib/relay/codec.test.ts`
Expected: FAIL — `decodeInbound` returns `null` for `agentRunOutput`.

- [ ] **Step 3: Extend types + the codec allowlist**

In `types.ts` add the two payload types + union members + `AgentReply`. In `codec.ts:14`, extend the allowlist:
```ts
if (t === "approvalPending" || t === "agentStatus" || t === "loopUpdate" ||
    t === "agentRunOutput" || t === "agentRunStatus") {
  const payload = plain.payload ?? plain;
  return { type: t, payload } as InboundAppMessage;
}
```
Add `encodeAgentReply` mirroring `encodeApprovalResponse` (type `"agentRunContinue"`, fields `{runId, prompt}` to match the daemon handler in Task 4 and the existing iOS `sendRunContinue`).

- [ ] **Step 4: Run to verify it passes**

Run: `cd web && bun test lib/relay/codec.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add web/lib/relay/types.ts web/lib/relay/codec.ts web/lib/relay/codec.test.ts
git commit -m "feat(web): relay codec accepts agentRunOutput/Status + agentReply encode"
```

---

## Task 2: run-state store slice

**Files:**
- Create: `web/lib/store/runState.ts`, `web/lib/store/runState.test.ts`
- Modify: `web/lib/store/useConduitStore.ts:18-68`

**Interfaces:**
- Produces:
  - `type RunState = { runId: string; chunks: RunOutputChunk[]; status: string; exitCode?: number }`
  - `mergeChunk(run: RunState | undefined, chunk: RunOutputChunk): RunState` — appends, dedups by `seq`, keeps order.
  - Store gains `runs: Record<string, RunState>` and `ingest` handles the two new message types.

**Background (verified):** Mirrors iOS `RunOutputStore.Run` (`RunOutputStore.swift:12-27`) — accumulate chunks, dedup by `seq`, track lifecycle.

- [ ] **Step 1: Write the failing merge test**

```ts
import { test, expect } from "bun:test";
import { mergeChunk } from "./runState";

test("mergeChunk dedups by seq and preserves order", () => {
  let r = mergeChunk(undefined, { runId: "r1", stream: "stdout", chunk: "a", seq: 1 });
  r = mergeChunk(r, { runId: "r1", stream: "stdout", chunk: "b", seq: 2 });
  r = mergeChunk(r, { runId: "r1", stream: "stdout", chunk: "a", seq: 1 }); // dup
  expect(r.chunks.map(c => c.chunk).join("")).toBe("ab");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd web && bun test lib/store/runState.test.ts`
Expected: FAIL — `mergeChunk` undefined.

- [ ] **Step 3: Implement `runState.ts` + wire `ingest`**

```ts
import type { RunOutputChunk } from "@/lib/relay/types";

export type RunState = { runId: string; chunks: RunOutputChunk[]; status: string; exitCode?: number };

export function mergeChunk(run: RunState | undefined, chunk: RunOutputChunk): RunState {
  const base: RunState = run ?? { runId: chunk.runId, chunks: [], status: "running" };
  if (base.chunks.some(c => c.seq === chunk.seq)) return base;
  return { ...base, chunks: [...base.chunks, chunk].sort((a, b) => a.seq - b.seq) };
}
```
In `useConduitStore.ts`, add `runs: {}` to state and extend `ingest` (`:45-68`):
```ts
case "agentRunOutput": {
  const p = msg.payload;
  set(s => ({ runs: { ...s.runs, [p.runId]: mergeChunk(s.runs[p.runId], p) } }));
  break;
}
case "agentRunStatus": {
  const p = msg.payload;
  set(s => ({ runs: { ...s.runs, [p.runId]: { ...(s.runs[p.runId] ?? { runId: p.runId, chunks: [] }), status: p.status, exitCode: p.exitCode } } }));
  break;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd web && bun test lib/store`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add web/lib/store/runState.ts web/lib/store/runState.test.ts web/lib/store/useConduitStore.ts
git commit -m "feat(web): run-output store slice (chunk dedup by seq)"
```

---

## Task 3: BlockTranscript + ReplyBar UI

**Files:**
- Create: `web/components/BlockTranscript.tsx`, `web/components/ReplyBar.tsx`
- Modify: `web/app/agent/[id]/page.tsx:86-93`, `web/lib/relay/client.ts:81-86`

**Interfaces:**
- Consumes: `useConduitStore().runs`, `RelayClient.sendRunContinue(runId, text)`.
- Produces: `<BlockTranscript runId={…} />` (renders chunks, `$`-prefixed command lines, stdout/stderr styling using Conduit tokens `bg-card`/`text-foreground`/`font-mono`); `<ReplyBar runId={…} disabled={status!=="running"} />`.

- [ ] **Step 1: Add `sendRunContinue` to the relay client**

In `client.ts`, mirror `sendApprovalResponse` (`:81-86`):
```ts
sendRunContinue(runId: string, text: string) {
  const frame = encodeAgentReply({ runId, text }, this.key);
  this.ws?.send(frame);
}
```

- [ ] **Step 2: Implement `BlockTranscript.tsx`**

Render `runs[runId].chunks` in order; style command vs output; show a status chip (`running`/`exited <code>`). Use existing shadcn `Card` + Conduit tokens. Empty state: "Waiting for output…".

- [ ] **Step 3: Implement `ReplyBar.tsx`**

Controlled text input + Send button; on submit call `sendRunContinue(runId, text)` from the injected relay client (the same `sender` pattern used for approvals); disable when run status ≠ `running`.

- [ ] **Step 4: Replace the placeholder in the agent detail page**

In `app/agent/[id]/page.tsx:86-93`, replace the "Live block transcript is available on the phone…" card with `<BlockTranscript runId={…} />` + `<ReplyBar runId={…} />`, choosing the run id from the agent's active run (extend the store/selectors to map agent → current runId).

- [ ] **Step 5: Build gate**

Run: `cd web && bun run build`
Expected: zero TS/build errors.

- [ ] **Step 6: Commit (stage only)**

```bash
git add web/components/BlockTranscript.tsx web/components/ReplyBar.tsx web/app/agent/[id]/page.tsx web/lib/relay/client.ts
git commit -m "feat(web): live block transcript + reply bar on agent detail"
```

---

## Task 4: daemon `agentRunContinue` handler → tmux send-keys

**Files:**
- Create: `daemon/conduitd/run_reply.go`, `daemon/conduitd/run_reply_test.go`
- Modify: `daemon/conduitd/e2e_router.go:85-144`

**Interfaces:**
- Consumes: the `sessionRegistry` from the Session-Continuity Shim plan (Task 1 there) to resolve a runId/sessionId → tmux name; `writeFakeTmux` test helper (same package).
- Produces:
  - `func (s *server) applyRunReply(runID, text string) error` — looks up the run's tmux session, runs `tmux send-keys -t <name> -- <text>` then `Enter`.
  - `case "agentRunContinue":` in `handleMessage` decoding `{runId, prompt}` → `applyRunReply`.

**Background (verified):** `handleMessage` (`e2e_router.go:85`) handles approvalResponse/agentDispatch/agentRunControl and default-logs everything else — `agentRunContinue` falls through today. There is **no agent stdin pipe** (`realLauncher` opens none), so `send-keys` into the tmux container is the write path.

- [ ] **Step 1: Write the failing test**

```go
func TestApplyRunReplySendsKeys(t *testing.T) {
	dir := writeFakeTmux(t)
	s := newServer(t.TempDir())
	s.sessions.register(ShimSession{ID: "r1", TmuxName: "conduit-r1", Status: "running"})
	if err := s.applyRunReply("r1", "hello agent"); err != nil {
		t.Fatalf("applyRunReply: %v", err)
	}
	log, _ := os.ReadFile(filepath.Join(dir, "calls.log"))
	if !strings.Contains(string(log), "send-keys") || !strings.Contains(string(log), "conduit-r1") {
		t.Fatalf("send-keys not invoked: %q", log)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd daemon/conduitd && go test -run TestApplyRunReply ./...`
Expected: FAIL — `undefined: applyRunReply`.

- [ ] **Step 3: Implement `applyRunReply` + the handler case**

```go
package main

import (
	"fmt"
	"os/exec"
)

func (s *server) applyRunReply(runID, text string) error {
	sess, ok := s.sessions.get(runID)
	if !ok || sess.TmuxName == "" {
		return fmt.Errorf("no tmux-backed session for run %s", runID)
	}
	if err := exec.Command("tmux", "send-keys", "-t", sess.TmuxName, "--", text).Run(); err != nil {
		return err
	}
	return exec.Command("tmux", "send-keys", "-t", sess.TmuxName, "Enter").Run()
}
```
In `e2e_router.go:131` (next to `agentRunControl`), add:
```go
	case "agentRunContinue":
		var p struct {
			RunID  string `json:"runId"`
			Prompt string `json:"prompt"`
		}
		if err := json.Unmarshal(payload, &p); err != nil {
			log.Printf("e2e: unmarshal agentRunContinue failed: %v", err)
			return
		}
		if err := r.server.applyRunReply(p.RunID, p.Prompt); err != nil {
			log.Printf("e2e: applyRunReply: %v", err)
		}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd daemon/conduitd && go test -run TestApplyRunReply ./...`
Expected: PASS.

- [ ] **Step 5: Commit (stage only)**

```bash
git add daemon/conduitd/run_reply.go daemon/conduitd/run_reply_test.go daemon/conduitd/e2e_router.go
git commit -m "feat(conduitd): handle agentRunContinue via tmux send-keys (web/iOS reply)"
```

---

## Task 5: end-to-end verification

- [ ] **Step 1: Web gates green**

Run: `cd web && bun test && bun run build`
Expected: all tests pass, zero build errors.

- [ ] **Step 2: Daemon gate green**

Run: `cd daemon/conduitd && go test ./...`
Expected: PASS.

- [ ] **Step 3: Live interop (manual, documented in PR)**

1. Start `conduitd daemon` paired to a relay; launch an agent in a tmux-managed session (via the shim).
2. Open the web dashboard (paired as `role=phone`), navigate to the agent detail page.
3. Confirm the live block transcript streams as the agent runs.
4. Type a reply in the ReplyBar → confirm it lands in the agent's tmux session (visible in the transcript and on the host's `tmux attach`).
5. Confirm the iOS app shows the same reply (the daemon handler benefits both clients).

---

## Spec coverage check

| Requirement | Task |
|---|---|
| Web shows live block transcript | Tasks 1, 2, 3 (stop dropping + render) |
| Reply-to-agent from web | Tasks 3 (ReplyBar + sendRunContinue), 4 (daemon handler) |
| Relay protocol extension (TS side) | Task 1 |
| Daemon `agentRunContinue` handler (was orphaned) | Task 4 |
| iOS parity (existing `sendRunContinue` now works) | Task 4 (shared handler) |

## Dependency note

Task 4 (reply path) depends on the **Session-Continuity Shim** plan's `sessionRegistry` + tmux container. If that plan is not yet landed, implement Tasks 1–3 (read-only transcript) first — they stand alone on the already-emitted `agentRunOutput`/`agentRunStatus` stream — and gate the ReplyBar behind a "tmux-backed session" capability flag until the registry exists.

## Placeholder scan

- Every step shows concrete code + exact `bun`/`go test` commands with expected output. The agent→runId mapping in Task 3 step 4 is the one spot needing a selector addition; it is called out explicitly rather than left implicit.
