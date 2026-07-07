# Live Activity, Dynamic Island & Widget — design

Date: 2026-07-05  
Status: approved (design)  
Wireframes: `docs/design-audit/proof-to-ship-wireframes-2026-07-05/index.html` § `p0-live`, `p0-live-frames`

## Problem

Away Mode needs ambient mission status on Lock Screen, Dynamic Island, and Home Screen widget — without turning the phone into a terminal. Today's `LancerSessionAttributes` Live Activity is session-centric (chat tab), with phases limited to connected/streaming/needs-approval. Proof-to-ship requires **mission-centric** phases: running, needs-you, proof-ready, blocked.

## Decisions (brainstorm 2026-07-05)

| Decision | Choice |
|----------|--------|
| Cardinality | **One Live Activity per governed mission** (cap ~3 concurrent) |
| Island arbitration | Highest `relevanceScore`; tie-break: needs-you → proof-ready → blocked → running |
| Blocked semantics | **Passive stall** (CI, hook unreachable, budget pause) — not a user interrupt |
| Needs-you semantics | **Only true interrupt** when phone can unblock |
| Interactivity | **Hybrid** by sub-state (see Interaction matrix) |
| Widget V1 | **Fleet small** — aggregate counts + top urgent mission |
| Widget V1.5 | **Mission medium** — mirrors Island winner with proof gap chips |
| Implementation | **New `LancerMissionAttributes`**; deprecate session LA for Away missions |

## State machine

```
running ──interrupt──► needsYou
running ──stall──────► blocked
running ──done───────► proofReady
blocked ──unblocked──► running
blocked ──user fix───► needsYou
needsYou ──resolved──► running | proofReady
proofReady ──send back► running
proofReady ──ship────► end
```

## ContentState schema (`LancerMissionAttributes`)

**Static attributes:** `missionID`, `missionTitle`, `hostName`, `agentName`, `repoLabel`

**Push-updated `ContentState`:**

| Field | Type | Notes |
|-------|------|-------|
| `phase` | enum | `running` \| `needsYou` \| `proofReady` \| `blocked` |
| `needsYouSubtype` | enum? | `approval` \| `question` \| `drift` \| `validationFail` |
| `riskTier` | int 0–3 | Daemon scale; drives high-risk tone swap |
| `interactionMode` | enum | `inlineButtons` \| `chips` \| `tapThrough` |
| `summaryRedacted` | string | ≤80 chars; no secrets/paths/diffs |
| `chipLabels` | [string] | Up to 3 for agent questions |
| `proofPresent` / `proofRequired` / `gapCount` | int | Proof-ready frame |
| `blockedReason` | enum? | `ci` \| `hook` \| `budget` \| `other` |
| `elapsedSeconds` | int | Running/blocked metadata |
| `costUSD` | double? | Optional overlay |
| `eventID` | string | Binds chips/buttons to context-ledger event |
| `relevanceScore` | int 0–100 | Island arbitration |
| `lastUpdate` | Date | Staleness |

## Interaction matrix

| Sub-state | LA / Island UI | Deep link |
|-----------|----------------|-----------|
| Approval · low/med risk | Approve / Reject on expanded Island | Decision Capsule |
| Approval · high/critical | Red card · **Review decision** only | Decision Capsule |
| Agent question | 2–3 structured chips + Details | Work Thread (question) |
| Plan drift / validation fail | **Review** tap-through | Drift / validation surface |
| Proof ready | **Review proof** + gap count | Proof Ready page |
| Blocked / Running | Glance only | Work Thread |

V1: no Face ID on Live Activity buttons (owner decision). High/critical never get inline approve.

## Frame-by-frame UI

### Copy rules (all surfaces)

- Mission title is the glance anchor (agent name secondary)
- No secrets, file paths, or diffs on LA
- High/critical: whole-card tone swap (existing pattern in `LancerLiveActivityWidget.swift`)
- Proof-ready: **lavender** — not green (green implies "ship it")
- Blocked: grey only — never amber/red

### Phase summary

| Phase | Lock Screen | Island compact | Expanded |
|-------|-------------|----------------|----------|
| Running | Green border · title · agent · elapsed/cost | Green dot · `...` | Streaming + cost |
| Needs you | Amber (red if high) | `?` or `⚠` | Chips / buttons / Review |
| Proof ready | Lavender · gap count | Lavender `✓` | Review proof CTA |
| Blocked | Grey · stall reason | Grey `...` | Informational only |

### Widget V1 (systemSmall)

```
1 NEEDS YOU
checkout fix
2 running · 1 proof ready
Updated 2m ago
```

Tap → Home / Away Digest.

## Push & lifecycle

- **Start:** `lancerd` on governed mission launch; push-to-start when app killed
- **Update:** phase transitions via relay → `push-backend` → ActivityKit content-state
- **End:** mission archived/shipped/user dismiss; proof-ready uses `dismissalPolicy: .after(+4h)`
- **Cap:** max 3 concurrent mission LAs; 4th start ends oldest running LA
- **Prerequisite:** remove `AppRoot` `.end()` on background; register Live Activity push token on relay path

## Out of scope (V1)

- Face ID / `IntentAuthenticationPolicy` on LA buttons
- Mission medium widget (V1.5)
- Watch Smart Stack supplemental activity
- Full diff or terminal output in content-state

## References

- `Packages/LancerKit/Sources/SessionFeature/LiveActivityManager.swift` — current session model
- `LancerLiveActivityWidget/LancerLiveActivityWidget.swift` — presentation + risk tiering
- `docs/product/2026-07-04-v1-paid-away-workflow-spec.md` — Lock Screen Question Card
- `docs/wwdc26-lancer-opportunity-audit/04-live-activities-and-dynamic-island.md` — platform constraints
