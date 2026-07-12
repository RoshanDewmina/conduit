# Can the owner go full-time on Lancer? — essentials audit (2026-07-12)

Owner question: "make a list of all the essentials I need to build [away from the computer],
then see if that's there — (1) webapps, (2) iOS/macOS apps."

Grounding: ARCHITECTURE §0.1 (2026-07-06 snapshot) + this week's shipped PRs (#89–#98) + the
live dogfood run of 2026-07-12 (a real warning-fix in this repo dispatched, approved, and
verified entirely through Lancer). Statuses: ✅ works today · 🔶 partial · ❌ missing.

## The core loop (workflow-agnostic)

| Essential | Status | Evidence / gap |
|---|---|---|
| Dispatch an agent on a repo from the phone | ✅ | Composer → daemon dispatch; proven live today (PONG, SECOND, warning-fix runs) |
| Follow-up / continue a run | ✅ | per-vendor `continueArgv`; follow-up bar; retry re-dispatch (#97) |
| Governed approvals with push, app closed | ✅ | C2 device proof (2026-06-23); today: Edit approval approved from owner's phone |
| Live transcript + honest run status | ✅ | streaming reveal; list statuses advance running→terminal only (#93, #97) |
| Receipts / proof of what ran | ✅ | Proof card + Proof Reel (#90); receipt decode fixtures |
| Thread/workspace organization | ✅ | one row per repo incl. worktree/relative/tilde aliases (#95, #98) |
| Multi-vendor (Claude/Codex/OpenCode/Kimi) | ✅ | dispatch + continue argv; opencode plugin gate re-verified live |
| Emergency stop | 🔶 | client-orchestrated; not yet an atomic daemon-side primitive |
| Session survives phone disconnect | ✅ | resident daemon owns state by design |
| **Reliability of first send after reconnect** | 🔶 | send races relay re-key → "machine didn't respond"; Retry recovers, but full-time use will hit this daily. Seen 3× today. **Top reliability gap.** |
| Plan/quota awareness (Claude/Cursor limits) | ❌ | owner-asks #22; subscription-only billing makes this the "can I even dispatch" signal |

## Workflow 1 — building webapps from the phone

| Essential | Status | Notes |
|---|---|---|
| Agent writes code, you approve edits | ✅ | core loop |
| **See the diff before approving / after the run** | 🔶 | approval card shows command + blast radius; Flight Recorder shows events; no first-class per-file diff viewer. Rely on agent-pasted diffs today |
| **Preview the running webapp** (dev server → phone browser) | ❌ | biggest webapp gap. Needs a tunnel/port-forward story (SOCKS/port-forward code exists but is V2-deferred with the terminal). Workaround: deploy previews (Vercel) + phone browser |
| Run tests / see results | 🔶 | via prompt + transcript; no structured test-report card |
| Git: branch, commit, push, PR | 🔶 | agents do it on instruction (proven: PRs today were agent-made); no first-class UI, and that's probably fine — GitHub mobile covers PR review |
| CI status | 🔶 | via agent query; no push notification on CI red |
| Logs / server state | 🔶 | ask the agent; interactive terminal is V2-deferred (correct per scope) |
| Artifacts (screenshots, built pages) in chat | 🔶 | `ChatArtifactCard` renders persisted run artifacts; image/screenshot rendering inline is owner-ask #26 — needed to "see" what the agent built |

**Verdict:** dispatch/approve/iterate on a webapp works end-to-end today. What keeps you tied
to the computer: **no live preview of the app you're building** and **no diff-level review
surface**. With deploy-preview discipline (agent pushes → Vercel preview → phone Safari) you
can genuinely run webapp development from the phone now; without it you're trusting
transcripts.

## Workflow 2 — building iOS/macOS apps from the phone

| Essential | Status | Notes |
|---|---|---|
| Build/test on the Mac via agent | ✅ | agents drive XcodeBuildMCP/xcodebuild on the host (this entire session is the proof) |
| Build errors → readable transcript | ✅ | structured error output in thread |
| **See simulator screenshots in chat** | ❌ | the iOS-dev killer feature. Agent can capture PNGs; chat can't render them inline yet (#26). Without it you can't judge UI work remotely |
| UI automation evidence (taps, flows) | 🔶 | agent-side exists (snapshot_ui etc.); surfacing to phone = same #26 gap |
| Install to device / TestFlight | 🔶 | device install needs the phone cabled to the Mac (as done today — worked because you were home). Remote path = agent-driven TestFlight upload (proven 2026-06-23) + phone installs from TestFlight. Slower loop but fully remote |
| Crash logs / device diagnostics | 🔶 | via agent prompts |
| App Store submission ops | 🔶 | archive/altool via agent proven; metadata/review is web UI anyway |

**Verdict:** code-level iOS work (fix bugs, add features, run tests/builds) is fully doable
from the phone today — today's dogfood literally was iOS development through Lancer. UI work
is not, until screenshots/artifacts render in chat (#26). TestFlight-as-remote-install makes
device testing possible but slow.

## Ranked: what to build to cut the cord

1. **#26 artifact/image rendering in chat — BOTH directions.** Outbound: agent screenshots/artifacts render inline (unlocks iOS UI work + webapp visual review). Inbound: the composer's Context sheet (Photos/Screenshots/Camera/Files/MCP Servers) is affordance-only today — `ContextAttachView.swift:132` "attach wiring deferred" (owner asked 2026-07-12; verified not wired). Sending the agent a design screenshot or error photo is a core mobile move. Single highest-leverage item.
2. **First-send-after-reconnect reliability** (relay re-key race) — the loop must not need a Retry tap per session. (New, from today's live runs.)
3. **Diff review card** — per-file diff on Edit approvals and in receipts; turns "trust the transcript" into review.
4. **#22 plan-limits collector** — know remaining Claude/Cursor budget before dispatching from the couch.
5. **Webapp preview story** — cheapest: document/automate the deploy-preview flow per repo; a tunnel is V2.
6. **Test/CI result cards + CI-red push** — closes the verify half of the loop remotely.

## Proof card placement (owner ask, 2026-07-12)

Decision (recommended): keep a **one-line receipt chip** in the chat flow (status + duration,
tappable), move the **full Proof card + Proof Reel into the thread's Flight Recorder view**,
which is already the "what actually happened" surface. No new Activity root (the 3-root IA is
locked; a fourth root re-opens the tab-bar mistake). Backlogged as a design task.
