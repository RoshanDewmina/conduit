# User-Ready Tier 0 — Competitor Borrow + Polish Plan

> **For agentic workers:** REQUIRED SUB-SKILL: subagent-driven-development. Steps use checkbox syntax.

**Goal:** Ship a polished, user-ready Cursor shell where a developer can pair, dispatch, approve, and continue agent work on simulator (screenshot-proven), borrowing the best patterns from T3 Code, Orca, and Happier without abandoning Lancer's blind-relay + `lancerd` governance wedge.

**Architecture:** Integrate on `codex/tier-0-live-cursor-shell` (P0 fixes + live bridge). Cherry-pick UI/tests from `amazing-mayer` only — **no wholesale Settings/Inbox deletion**. Borrow competitor UX at the Cursor shell layer; keep real Settings handoff for policy/relay/audit.

**Tech Stack:** SwiftUI (LancerKit), Xcode 26 / iOS 26 sim, `lancerd` relay E2E harness.

## Global Constraints

- V1 wedge: phone steers/approves — not a phone IDE (no Orca-style xterm mirror).
- Home IA: Cursor shell / durable threads — no tab bar.
- Security: TOFU, fail-closed biometric, atomic emergency stop (already on codex branch).
- Do not copy Happier's stateful relay server model.
- Verify with Xcode app-target build + UITests + screenshots before claiming done.

---

## Competitor borrow matrix

| Pattern | Source | Lancer target | Priority |
|---------|--------|---------------|----------|
| Durable dispatch outbox (offline enqueue, shell-level drain) | T3 `thread-outbox-model.ts` | `DispatchOutbox` + bridge drain | P1 |
| Approval cards above composer, not buried in feed | T3 `PendingApprovalCard.tsx` | `CursorWorkThreadView` banner + review sheet | P0 |
| Thread list attention pills (`Needs Approval` > `Working`) | T3 `threadPresentation.ts` + Happier `deriveSessionAttentionState` | `CursorWorkspaceThreadListView` | P0 |
| Connection health ladder (offline / reconnecting / re-pair) | Orca `connection-health.ts` | `CursorWorkspacesView` + bridge status | P0 |
| Resume last active thread on launch | Orca `resume-worktree.ts` | Bridge `selectedThreadID` restore | P1 |
| Pairing: network hint + confirm screen + timeout | Orca `pair-confirm.tsx` | `CursorRelayPairingSheet` | P1 |
| Composer draft survives navigation | Happier `session.composerDraftContinuity` | `CursorComposerSheet` draft key | P1 |
| Notification → deep link dedup | T3 `notificationNavigation.ts` | Existing APNs routing audit | P2 |
| Real Settings handoff (not mock-only) | Lancer existing | `CursorSettingsView` → `SettingsWithLibraryView` | P0 |

**Anti-patterns to avoid:** Clerk-gated push (T3), LAN-only WS without relay story (Orca), stateful session server (Happier), phone xterm IDE (Orca 5K-line session screen).

---

## Scope decisions (agent-chosen)

| Question | Decision |
|----------|----------|
| Base branch | `codex/tier-0-live-cursor-shell` |
| amazing-mayer | Cherry-pick: `DispatchAgent`, `CursorRelayPairingSheet`, Haiku/Legacy UI tests — **not** Settings/Inbox deletion |
| Shell | Cursor production root + real Settings sheet |
| Tier 2 MVP | Frozen |
| Done bar | User-ready: polished Tier 0, all UITests green, screenshot suite, gap matrix updated |

---

## Parallel lanes (separate worktrees)

| Lane | Branch | Owns | Out of scope |
|------|--------|------|--------------|
| **L1 Attention + connection** | `cursor/tier0-attention-9aec` | `CursorWorkspacesView`, thread list, connection status UI | `AppRoot.swift` |
| **L2 Approval + composer polish** | `cursor/tier0-approval-9aec` | `CursorWorkThreadView`, `CursorComposerSheet`, `CursorReviewDiffView` | Settings |
| **L3 Settings + pairing** | `cursor/tier0-settings-9aec` | `CursorSettingsView`, `CursorRelayPairingSheet`, Settings handoff | AppRoot routing |
| **L4 Tests + screenshots** | `cursor/tier0-proof-9aec` | `LancerUITests/**`, `docs/test-runs/**`, gap matrix | Production Swift except test seams |

**Merge owner:** integration branch `cursor/user-ready-tier0-9aec` off codex base.

---

## Task checklist

### Wave 0 — Integration base
- [ ] Create worktree from `codex/tier-0-live-cursor-shell`
- [ ] Cherry-pick amazing-mayer: `DispatchAgent`, relay pairing sheet, UI tests (no mass deletes)
- [ ] Xcode build + baseline UITest run

### Wave 1 — Parallel implementation (L1–L3)
- [ ] L1: Thread attention pills + connection health banner
- [ ] L2: Approval-above-composer polish + composer draft persistence
- [ ] L3: Settings rows wire to real surfaces; pairing confirm UX

### Wave 2 — Proof (L4)
- [ ] Extend screenshot walkthrough for Tier 0 path
- [ ] Fix relay E2E for Cursor-shell navigation if broken
- [ ] Update gap matrix + test-run evidence

### Wave 3 — Merge + gate
- [ ] Merge lanes → integration branch
- [ ] Full UITest suite PASS
- [ ] Screenshot evidence committed
- [ ] Push + PR

---

## Verification commands

```bash
cd Packages/LancerKit && swift build && swift test
# App target (from repo root after xcodegen):
xcodebuild -scheme Lancer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build test
scripts/validation/relay-approval-e2e.sh  # if lancerd available
```
