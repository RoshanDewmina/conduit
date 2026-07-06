# How Lancer Maps Vendor CLI Output to Work Thread Card Types

Research question: when a user picks a vendor CLI (Codex, Claude Code, OpenCode, or Kimi) to run a mission, how does Lancer's actual daemon/iOS architecture turn that CLI's raw output into one of the structured Work Thread cards shown in the wireframes (Question Card, Proof card, Diff card, Approval card, Preview cockpit, etc.)?

## 1. What's real today

**Two separate classification layers exist, and they're inconsistent with each other.**

**Layer A — daemon-side event normalization (`daemon/lancerd/dispatch.go`).** This is real and working. `agentArgv` (dispatch.go:33-67) already launches every vendor with its structured-output flag: Claude Code `--output-format stream-json --verbose --include-partial-messages` (line 36), Codex `codex exec --json` (line 44), OpenCode `run --format json` (line 59), Kimi `--output-format stream-json` (line 53). `streamJSONOutput` (lines 562-781) parses each vendor's distinct JSON event shape and reduces it to exactly two outbound wire events: `agent.run.output` (plain prose text) and, via `emitToolArtifact` (lines 531-546), `agent.tool.start` + `agent.artifact` — the latter **hardcoded** to `"kind": "tool"` (line 541). There is no other kind ever emitted from this path.

**Layer B — the iOS artifact model (`LancerCore/ChatConversation.swift:242-262`).** `ChatArtifact.Kind` is a 6-case enum: `.tool, .diff, .file, .test, .preview, .approval` — and `ChatArtifactCards.swift:6-372` has fully-built SwiftUI renderers for all six (diff stat chips, pass/fail test chip, preview URL card, pending/approved/denied approval card). This *looks* like the classification mechanism the wireframes want.

**The gap between them:** cross-referencing every real constructor of a `ChatArtifact`, only two kinds are ever actually produced: `.tool` (from dispatch.go's hardcoded string above) and `.approval` (constructed client-side in `PersistenceKit/ChatConversationRepository.swift:247-249` when an approval-pending event arrives — not derived from vendor stdout at all). **`.diff`, `.file`, `.test`, and `.preview` have zero producers anywhere in the codebase** — fully built UI with no data pipeline feeding it. `RunOutputStore.swift` (the live-run store) is even more primitive: `ToolBlock` (lines 37-43) only carries `toolName`/`inputJSON`/`running|done` — no diff/test/preview concept exists there at all.

There is also **no `.question` kind anywhere** — the wireframe's "Question Card" has no backing model type. And a third, independent heuristic exists in `DarkTranscriptComponents.swift:296-312`: it colors terminal-block lines by string-sniffing (`lower.contains("fail")`, `hasPrefix("pass")`, `contains("✓")`) — a hand-rolled text classifier, not vendor-schema-aware, living in a separate legacy rendering path.

## 2. What each vendor actually emits (per dispatch.go's own parsing)

- **Claude Code** — confirmed, well-structured: `stream_event`/`content_block_start|delta|stop` distinguishing `text_delta` vs `tool_use` blocks, plus `system`/`init` carrying `session_id` (lines 620-683). This matches Anthropic's documented stream-json contract and is the most solid of the four.
- **Codex** — `thread.started`, `item.started`/`item.completed` with `item.type` of `command_execution` vs `agent_message` (lines 722-759). Structurally clear in code, but comments elsewhere (CODEX_GATING.md references) flag headless-approval behavior as needing re-verification — can't independently confirm Codex's full event vocabulary beyond what's handled here.
- **OpenCode** — top-level `sessionID` on every event; `tool_use` events arrive fully resolved (`part.tool`/`callID`/`state.input`), not streamed deltas (lines 700-721). Code comment states this was "verified live 2026-07-02 against opencode 1.17.11" — fairly solid.
- **Kimi** — weakest: fallback parsing is just `{"role":"assistant","content":...}` (lines 764-776), and the code's own comment (lines 604-609) says the shape "could not be live-verified" and is "a best-effort guess." Flag this as unconfirmed.

None of the four vendors' native events map to anything like "a decision is needed" — Lancer's own approval/question semantics come from a **separate mechanism**, the per-tool `PreToolUse` hook (`daemon/lancerd/hook.go`, its own `command|patch|fileWrite` risk-kind enum, distinct from `ChatArtifact.Kind`), not from stdout classification.

## 3. The gap to build

This is squarely a per-vendor-adapter problem, and dispatch.go's structure makes it natural: `streamJSONOutput`'s per-`typ`/`eTyp` switch already is the seam. To realize `.diff`/`.test`/`.preview`/`.question`, each vendor branch would need to (a) recognize tool calls that are semantically diffs/tests/preview-servers (e.g., a `Write`/`Edit` tool call → `.diff`, a test-runner command whose output matches pass/fail → `.test`), and (b) emit `agent.artifact` with that real `kind` instead of the hardcoded `"tool"` string at line 541 — plus define a new `.question` case end-to-end (dispatch.go event → wire schema → `ChatArtifact.Kind` → new SwiftUI card) since none exists today. This is additive work inside the existing per-vendor switch statements, not a rearchitecture — but it is real, unbuilt work across 4 vendor branches plus the iOS enum/renderer.

## Bottom line

The wireframes describe artifacts as if they already come from a smart classifier. In reality: real per-vendor structured-output plumbing exists in dispatch.go, and a fully-built 6-case card renderer exists on iOS, but only 2 of those 6 kinds (`.tool`, `.approval`) are ever actually produced, and `.question` doesn't exist as a type at all. The fix is additive engineering across 4 vendor adapters plus one net-new card type — not a rearchitecture, but real, unbuilt work. Kimi's parsing is the least reliable foundation to build on first.
