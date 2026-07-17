# Research brief for Fable — Lancer differentiation, direction, and roadmap

Prepared: 2026-07-07
For: Claude Fable 5 (`claude-fable-5`), dispatched via the Agent tool per `CLAUDE.md`'s escalation model
Status: input brief — not a decision doc. Fable's output is the next artifact, not this one.

---

## 1. The ask

Deep-dive on one question and produce two deliverables.

**The question:** given everything below — what Lancer actually is today, what's already been decided, what's still open, and how the competitive landscape looks — what makes Lancer genuinely different from its competitors, and what should it do next to make that difference real and sellable?

**Deliverable A — a differentiation verdict.** Not a restatement of the governance pitch already in this repo (§7 below shows that thesis has been proposed, pushed back on, and re-proposed at least four times across three sessions without ever being pressure-tested against fresh outside evidence). Independently re-derive it: do your own web research on the current state of Omnara, GitHub Agent HQ, Codex-in-ChatGPT-mobile, Claude Code Remote Control, Cursor, Orca, Happy/Happier, and any others you find — the data in §6 is 1–5 days old in a market that moves in days, so verify rather than trust it. Then give a direct answer: is there a defensible wedge, what is it, and why would a specific buyer pick Lancer over the alternative they already have. If the honest answer is "no, not as currently scoped," say that.

**Deliverable B — a prioritized roadmap.** Given the verdict, what should get built next, in what order, and what should explicitly wait or get cut. Ground it in the current engineering reality (§4) and the already-decided scope (§5) — don't re-litigate settled calls without a stated reason, but don't defer to them either if your independent research contradicts them.

Do not write code. This is a strategy and planning pass — the deliverable is analysis and a plan, which then becomes the input to `writing-plans` / actual implementation dispatch in a later session.

---

## 2. Why this, why now

The repo carries a hard deadline: **2026-07-21**, a validation gate requiring 10 contacted users, 5 repeat-use, 3 paying, 1 team customer (`docs/STATUS_LEDGER.md`). As of this pass, **there is no evidence those interviews have run** — the gate is a prepared instrument, not a completed study, in every doc that references it going back to 2026-06-24.

Five separate sessions across Claude Code, Codex, and Cursor have independently arrived at some version of "governance (policy engine + hash-chained audit + emergency stop) is Lancer's real differentiator" — and the owner has pushed back on that conclusion at least three times in the raw transcripts as too weak, too easily copied, or not what makes someone actually switch. The thesis keeps getting re-asserted rather than re-tested. That's the specific failure mode this brief is trying to break: another session agreeing with the governance thesis because it's already in the room, not because it independently checked.

Separately, `AGENTS.md`'s working rules for this repo state plainly: *"Distrust another agent's or tool's self-report by default, not just your own. A prior transcript, PR description, or doc saying 'done'/'merged'/'verified' is a claim, not a fact."* The 2026-07-06 cross-platform audit that produced most of the canonical docs cited below found this was the single most repeated, most expensive failure mode across every agent that touched this repo in the prior week — including its own first draft. Apply that same distrust to everything in this brief, especially §6 and §7.

---

## 3. What Lancer is (one paragraph)

iOS/iPadOS "mission control" for AI coding agents (Claude Code, Codex, OpenCode, Kimi) that run on a developer's own machines or servers — not a phone IDE, not a generic SSH terminal. Three layers: a SwiftUI app (`Packages/LancerKit/`), a resident Go daemon (`daemon/lancerd/`) that evaluates policy/audit/dispatch and survives disconnects, and a hosted control plane (`daemon/push-backend/`, `daemon/agent-runner/`) carrying an end-to-end-encrypted blind relay plus APNs. The phone steers, reviews, and approves; it does not hold execution.

---

## 4. Current engineering reality

Treat this as ground truth over any product-doc claim below it. Full detail: [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](2026-07-06-feature-implementation-gap-matrix.md), [`docs/product/2026-07-06-lancer-consolidated-status.md`](2026-07-06-lancer-consolidated-status.md), [`docs/STATUS_LEDGER.md`](../STATUS_LEDGER.md).

**Shipped and working:** governed-approval loop (hook → policy → inbox → approve → hash-chained audit), E2E-encrypted blind relay pairing, multi-vendor dispatch with explicit argv (no shell interpolation) across Claude Code / Codex / OpenCode / Kimi, push-driven Live Activities, a physical-device app-closed APNs approval loop (proved 2026-06-23), fail-closed policy defaults, drift detection, LancerMac thin companion.

**Current engineering priority (as of 2026-07-06, per `STATUS_LEDGER.md`):** prove the **Tier 0 live loop** — pair → dispatch → approve → follow-up — end-to-end through the now-merged Cursor-style shell (`LANCER_CURSOR_SHELL_LIVE=1`) against a real `lancerd`. Everything past this (Away Mode, Proof Suite, Git/PR ship actions, further IA redesign) is explicitly **frozen** until this proves out on a physical device.

**Open correctness/security gaps** (from `docs/product/2026-07-05-lancer-feature-master-plan.md` §7 and the 2026-07-06 gap matrix):

| Gap | Severity | Status |
|---|---|---|
| Biometric gate degrades open on no-passcode devices | P0 — security | **Fixed on branch** `codex/tier-0-live-cursor-shell` (`531685b6`); owner device validation still pending |
| Emergency Stop not atomic (client-side loop, not one daemon RPC) | P0 — correctness | **Fixed on same branch** — daemon latch + RPC |
| JWT verification HS256-only, no JWKS/RS256 | P1 — security | Open |
| Two uncoordinated billing mechanisms (dormant StoreKit IAP + live Stripe cloud entitlement) | P1 — correctness | Open — business decision needed |
| Watch app built and tested, not embedded in the iOS target — reaches zero users | P1 — distribution | Open |
| Audit hash chain has no external anchor (tip hash not pushed anywhere outside the file) | P1 — security | Open |
| Daemon single relay-pairing slot (one pairing overwrites the last) | P2 — architecture | Open by design |

If your differentiation argument leans on "governed, audit-backed autonomy," these gaps matter — several of them are exactly the kind of thing a technically sophisticated buyer (the persona this pitch targets) would check first. Weigh that in Deliverable A.

---

## 5. What's already decided (don't re-derive, do feel free to challenge)

The repo has a **canonical, decided feature scope** as of 2026-07-05, produced by auditing the same raw brainstorm material you're about to read in §7 plus a wireframe pass. Read it rather than re-deriving it: [`docs/product/2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md) (the decisions + rationale), [`docs/product/FEATURE_BACKLOG.md`](FEATURE_BACKLOG.md) (sortable status tracker), [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](2026-07-06-feature-implementation-gap-matrix.md) (shipped vs. mocked vs. missing).

Condensed shape, so you don't have to open all three cold:

- **Locked IA:** 3 roots — Home, Workspaces, Settings. No tab bar. No 4th root. (`ARCHITECTURE.md` §4.1, master plan §2)
- **V1 core loop, decided but mostly unbuilt** (Away Launch Composer, Question Cards, Proof Suite base layer + Reel + Timeline, Away Digest as Home, Mobile QA Annotation, Git/PR/Merge actions, Flight Recorder) — wireframed, several explicitly headline/differentiator-tier, almost none is live-wired yet (master plan §5, gap matrix Tier 2).
- **Post-MVP, evaluated and sequenced** — highest-scored is **Cross-Vendor Second-Agent Review** ("a second, different-vendor agent critiques a result without re-solving it") — explicitly called the single highest-differentiation Post-MVP item because it's structurally impossible for a single-vendor competitor to copy (master plan §6).
- **Explicitly rejected**, with reasons — Needs-Me-Queue-as-Home rename, standalone Evidence Inbox, heavy Mission-Draft/plan-mode clone, Live Activity Risk Meter, Haptic Risk Language, always-on Live Shadow second opinion, Break-Point-Aware Nudges, Live Camera Bug Repro, Big Agent Router, Frustration Signal Missions, Micro Editor (conflicts a locked non-goal), Developer App Drawer (conflicts the locked 3-root IA) (master plan §8).
- **Still genuinely open, not resolved by any prior pass:** Workspaces data model (repo-first vs. host-first — repo-first was since decided, see the ADR referenced in `FEATURE_BACKLOG.md` §2), which of 3 uncoordinated billing mechanisms ships, whether Return-to-Desk is a real single recap surface or scattered.

**Working assumption for this brief, stated so you can challenge it explicitly:** the repo currently treats "governance/policy/audit + Away Mode with proof" as the settled direction and is mid-build on it. If your independent competitive research or product judgment says that's wrong, say so plainly — this brief is explicitly asking you not to rubber-stamp it.

---

## 6. Competitive landscape — what's in-repo, and what you should re-verify

**Caveat up front:** a fuller multi-agent competitive audit ran on 2026-07-03 (referenced in prior-session memory as a large parallel-agent research pass against 25+ competitors) but its narrative report was purged from this repo in the 2026-07-06 documentation cleanup along with the rest of the July-4 strategy batch. What survives is the **structured dataset** it (or an adjacent pass) produced — 19 competitor profiles and 85 feature-support rows, still in `docs/competitive-intelligence/data/{competitors,competitor-features}.jsonl` — plus a 2026-07-02 narrative baseline. Treat the structured data as the more reliable of the two (it's more recent than most of the narrative), and treat both as **stale enough to re-verify**, not settled fact. This is exactly the kind of gap your own web research should close.

**Local clones available — read real code, not just web summaries.** Four of the closest competitors are shallow-cloned at `.study/competitors/{omnara,happier,lfg,orca}/` (gitignored, not part of Lancer's own codebase):

- `omnara/` — last commit **2025-12-27**. Public repo has been dormant ~6 months, consistent with the "archived-oss, pivoted to closed-source" note in the structured dataset — worth confirming whether that pivot is real and what replaced it.
- `happier/` — last commit 2026-06-25. Active.
- `lfg/` (BennyKok/lfg) — last commit 2026-07-06. Active, not in the structured dataset at all — a self-hostable VPS/Tailscale/tmux pattern referenced heavily in the raw brainstorm transcripts as "the reference host architecture to steal from" but never formally profiled. Worth a first-class look.
- `orca/` (stablyai/orca) — last commit **2026-07-07** (today). Actively shipping; check `mobile/`, `native/`, and `notes/` for what's actually built vs. `docs/` claims.

18 competitors, condensed from the surviving dataset (self-reported threat score 1–5, 5 = most direct):

| Competitor | Category | Threat | Positioning | Pricing | Security posture |
|---|---|---|---|---|---|
| **Claude Code Remote Control** | first-party | 5 | Drive a local Claude Code session from phone/browser; code never leaves the machine | Free with Pro/Max | Outbound-only HTTPS, no inbound ports, short-lived scoped creds |
| **Codex in ChatGPT mobile** | first-party | 5 | Queue/steer/approve/review Codex sessions on your own machines from ChatGPT mobile | All plans incl. Free | Sandboxed exec (Seatbelt/bwrap/WSL2), network off by default, Face ID lock |
| **GitHub Copilot CLI Remote Control + Agent HQ** | first-party | 5 | Stream a local CLI session, approve/deny from GitHub Mobile; Agent HQ = cross-vendor mission control | Included in paid Copilot | Tool/file/URL-scoped permission prompts, no self-merge |
| **Omnara** (YC S25) | direct | 4 | Command center for coding agents — monitor/steer/approve from phone/web/voice | Free 10 sess/mo → $9→$20/mo | **No true E2EE (founder-admitted)**, plaintext server-side, no SOC2 |
| **Orca (ADE)** | direct | 4 | Parallel-agent dev environment, isolated git worktrees, desktop + mobile companion | Free/OSS | Undocumented — an opening |
| **DIY: Tailscale+SSH+tmux(+Termius/mosh/ntfy)** | substitute | 4 | Free VPN mesh + SSH client + persistence + push hooks | Free | VPN-mesh trust, **no governed approvals, no audit trail, no policy engine** |
| **Tactic Remote** | direct | 3 | Live terminal stream, tmux, file browsing, approvals, plan review | Unknown | Cloudflare Tunnel + API key — weaker than relay+TOFU+biometric competitors |
| **Nimbalyst** | adjacent | 2 | AI-native desktop kanban + iOS companion, visual diff review | Unknown | Unknown |
| **Happy / Happier** | adjacent | 3 | Native iOS monitor for Claude Code sessions, push, status | Claimed cheaper than Omnara | Claimed E2E — unverified in-repo |
| **Cursor Cloud/Background Agents** | first-party | 3 | Steer background agents from mobile browser/PWA, Slack | Cursor subscription | Cloud-hosted (not user's machine) — different trust model |
| **Factory (Droids)** | first-party | 3 | Approve diffs, unblock droids, feedback from phone | Unknown | Unknown |
| **OpenCode (sst)** | adjacent | 3 | Local agent client/server, mobile client in beta — architecturally closest to Lancer | Free/OSS | Unknown |
| **Sourcegraph Amp** | first-party | 2 | Drive agents from web/CLI/mobile, synced threads | Unknown | Unknown |
| **Devin / Cognition** | substitute | 2 | Async cloud-VM agent, Slack-tag, scheduled sessions | Unknown | Unknown |
| **Gemini CLI + Jules** | first-party | 2 | Async cloud-VM agent, plan-approval before code | Unknown | Unknown |
| **Vibe Kanban (BloopAI)** | adjacent | 2 | Kanban for orchestrating agents, cross-vendor, local-only | Free/OSS | Local-only, no relay |
| **Locally AI / LM Link** | adjacent | 1 | On-device LLMs (MLX) + E2E phone↔desktop LM Studio pairing | Free preview | E2E phone-to-desktop, well-received |
| **Blume** | adjacent | 1 | Desktop sidecar watching agents, hidden config management | Unknown | Local-only, no relay |

Full per-competitor JSON: `docs/competitive-intelligence/data/competitors.jsonl` (19 rows incl. Lancer); feature-support matrix: `competitor-features.jsonl` (85 rows); narrative baseline with more detail and code-vs-claim cross-checks: [`current-product-baseline.md`](../competitive-intelligence/reports/current-product-baseline.md).

**What's changed materially since 2026-07-02 that a fresh search should catch:** Cursor Composer 30-feature brainstorm content (§7 below) references Happier as "grown into a much more serious multi-provider/worktree product" than earlier framing implied, and flags Happy as the star-count leader — re-verify current GitHub stars/activity for Happy, Happier, Orca, and Litter (a "native mobile/Rust-core" competitor mentioned once in the raw transcripts but never added to the structured dataset — check if it's real and worth profiling).

---

## 7. The prior differentiation debate — condensed arc, so you don't re-run it blind

Across roughly a dozen sessions over 2026-07-03 to 2026-07-06, three different agent platforms (Claude Code, Codex, Cursor) worked through this exact question with the owner pushing back at each stage. The arc, compressed:

1. **"Mobile IDE / generic remote control"** → rejected almost immediately. Every first-party platform (Claude Code Remote Control, Codex mobile, Copilot Agent HQ) already ships this; commoditized.
2. **"Policy + hash-chained audit + emergency stop = governance moat"** → proposed, and genuinely true structurally (none of the 6-18 competitor repos independently checked across sessions have all three primitives together). Owner's objection, twice: *"our competition has these points too"* / *"is that the only thing we have up our sleeve?"* — governance alone doesn't feel unique enough, and a competitor could plausibly bolt on a policy layer in weeks if they decided to.
3. **"Agent Firewall + Repo-Aware Risk + Flight Recorder"** → sharper framing of the same governance idea (repo risk mapping, blast-radius-aware approvals). Never independently pressure-tested against fresh competitor evidence before the conversation moved on.
4. **"Away Mode with proof"** (Mission Contract → Proof Suite/Reel → Away Digest → Question Cards → Return-to-Desk) → the owner responded most positively to this arc, specifically praising the Cursor-style "proof video showing the fix works" pattern and the "walk away, only get pulled back in when judgment is required" framing. This became the committed spec: [`2026-07-04-v1-paid-away-workflow-spec.md`](2026-07-04-v1-paid-away-workflow-spec.md).
5. **A 30-feature "mission control" brainstorm** (Cursor, `claude-fable-5` at `xhigh` effort — i.e., a prior Fable pass on an *adjacent* but not identical question) ranked its own top 7 as: Artifact stream (structured cards, not chat) · Live Activity + lock-screen Face ID approve · Proof video scrub/search + annotate-back · Phone-as-test-device + shake-to-report · Speculative decision queue · Checkpoint/revert + burn switch · Return-to-desk packet + Handoff. Several of these **do not appear in the current master plan's MVP or Post-MVP tables** — see §8.
6. **Reconciliation pass (2026-07-05)** folded most of this into the canonical master plan (§5 above), keeping Proof Suite / Away Digest / Question Cards as the flagship V1 loop and elevating Cross-Vendor Review as the top Post-MVP bet.

The unresolved tension you're being asked to actually resolve: **is governance the moat, is proof-of-work the moat, or is neither one sufficient on its own** — and if neither is, is there a sharper synthesis, or is the honest answer that Lancer needs to find its wedge through the unrun validation interviews rather than more internal reasoning?

---

## 8. Ideas raised but never formally triaged into the master plan

These surfaced in the Cursor Composer "mission control" brainstorm (§7 item 5) and the immediately following ChatGPT-wireframe-artifact conversation, but never went through the same MVP/Post-MVP/Rejected evaluation the rest of the feature set got in the 2026-07-05 master plan. Listed here undigested — evaluate them yourself rather than trusting either the raw enthusiasm they got in the original conversation or an assumption that omission from the master plan means someone already rejected them.

- **Speculative Decision Queue** — when the agent hits a blocking fork while the user is away, branch both paths in parallel worktrees; when the user answers, the chosen branch is already done. Flagged in the original brainstorm as "the deepest host+phone synthesis" and also as "best differentiator, worst cost/complexity" in the same breath.
- **Burn Switch** — kill all sessions + revoke device-bound relay keys from the phone, or from iCloud if the phone is lost. Distinct from the existing Emergency Stop (which stops runs, not credentials).
- **Phone-as-test-device + shake-to-report** — for web/mobile UI work, tunnel the actual dev server to the phone as a real target-class device; shake to freeze-annotate a bug and send it back structured. Positioned as inverting "phone is the weak screen" into a strength no competitor claims.
- **Checkpoint/revert per risky step** — more granular than the existing Stop-and-Snapshot: every risky action gets its own git-shadow-ref checkpoint with a one-tap "revert to before this."
- **Cross-session memory search** — "when did we touch the auth middleware, and why?" across all runs/decisions/proof, broader than the already-planned Flight Recorder + Work Search.
- **Focus-aware batching, Commute mode (offline-first decisions), Audio standup briefing, On-call mode, Geofenced dispatch, Camera-to-plan, Two-key production actions, Fleet board with drag-priority, Diff triage cards (swipeable), Failing tests as actionable cards, Event triggers (CI-fail/issue-labeled auto-start)** — each named once, none evaluated against the differentiation/clutter/mobile-native rubric the master plan applied to everything else.

If any of these belong in the roadmap, say which and why — using the same rubric the master plan already applied elsewhere (mobile-specific? clutter risk? structurally hard for a competitor to copy? real user job?) would keep your output consistent with the rest of the decided scope rather than introducing a second, incompatible evaluation standard.

---

## 9. Business reality

- **Deadline:** 2026-07-21, hard gate: 10 contacted / 5 repeat-use / 3 paying / 1 team customer. **Unrun as of this writing** — no interview results, tracking sheet, or payment record found anywhere in the repo across two independent verification passes (2026-07-02 and 2026-07-04).
- **Target pricing** (never reconciled against the product): $25/mo solo, $99/mo team — sits alongside a dormant StoreKit one-time IAP that gates nothing and a live Stripe cloud entitlement that gates hosted-agent features only. Three mechanisms, one decision needed.
- **Positioning tried and explicitly rejected by the owner:** "mission control for AI coding agents" (too broad, matches every competitor's pitch).
- **Positioning the owner most recently reacted well to:** *"Lancer lets you leave agents working, then review, test, annotate, and ship the result from your phone without guessing whether it actually works"* / *"Run agents away from your desk without giving them a blank check."* Neither has been tested with a real prospect.

---

## 10. What "done" looks like

Two deliverables, not a document dump:

1. **A direct, evidence-backed differentiation verdict** — your own competitive research (don't just re-cite §6), a clear statement of what makes Lancer different (if anything), and who specifically would pay for that difference and why. If the honest conclusion is "the current governance-plus-proof framing is not differentiated enough to justify continued build," say that as plainly as the CONTINUE case.
2. **A prioritized roadmap** grounded in §4's actual engineering state (not the aspirational parts of §5), sequenced so the next 1-2 weeks of work either (a) closes the 2026-07-21 validation gate with a sharper pitch, or (b) if you conclude validation should happen before more building, says that instead and describes what the validation conversation should actually test.

Format is your call — a written analysis with clear headers works; don't feel obligated to produce a rigid section-by-section mirror of this brief. State your reasoning as you go rather than only the conclusion, since the next session will need to know *why*, not just *what*, to avoid repeating the same un-pressure-tested-thesis loop described in §2.

---

## 11. Source index

| Doc | Role |
|---|---|
| [`ARCHITECTURE.md`](../../ARCHITECTURE.md) §0.1 + §4.1 | Current-state snapshot + locked navigation |
| [`docs/product/2026-07-05-lancer-feature-master-plan.md`](2026-07-05-lancer-feature-master-plan.md) | Decided feature scope + rationale (canonical) |
| [`docs/product/FEATURE_BACKLOG.md`](FEATURE_BACKLOG.md) | Sortable status tracker |
| [`docs/product/2026-07-06-feature-implementation-gap-matrix.md`](2026-07-06-feature-implementation-gap-matrix.md) | Shipped vs. mocked vs. missing |
| [`docs/product/2026-07-06-lancer-consolidated-status.md`](2026-07-06-lancer-consolidated-status.md) | Latest engineering session outcomes |
| [`docs/STATUS_LEDGER.md`](../STATUS_LEDGER.md) | Owner hub: priority, deadlines, doc map |
| [`docs/product/2026-07-04-v1-paid-away-workflow-spec.md`](2026-07-04-v1-paid-away-workflow-spec.md) | Committed Away Mode paid-workflow spec |
| [`docs/competitive-intelligence/reports/current-product-baseline.md`](../competitive-intelligence/reports/current-product-baseline.md) | 2026-07-02 code-verified baseline + competitive framing |
| `docs/competitive-intelligence/data/competitors.jsonl`, `competitor-features.jsonl` | Structured competitor dataset (19 competitors / 85 feature rows) |
| [`docs/product/2026-07-06-competitor-borrow-matrix.md`](2026-07-06-competitor-borrow-matrix.md) | Tactical UI-pattern borrow list (not strategic) |
| [`docs/validation-cycle-v1.md`](../validation-cycle-v1.md) | The unrun design-partner interview instrument |
| [`AGENTS.md`](../../AGENTS.md) | Working rules — read before trusting any prior "done" claim |
