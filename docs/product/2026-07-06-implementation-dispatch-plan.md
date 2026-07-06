# Implementation dispatch plan — 2026-07-06

**Owner decisions locked this session:**

| Decision | Call |
|----------|------|
| Cleanup | **Option B** — aggressive; legacy sidebar/settings removed from default path |
| Agent isolation | **One git worktree per lane** — no shared-file parallel writes |
| Workspaces IA | **Repo-first, Workspaces as production root** for T0/T1; Home/Away Digest wireframe is V1 (frozen) |
| Repo vs host-first data | **Recommend repo-first** — matches Cursor shell, live bridge, wireframes; migrate `WorkspaceRepository` incrementally (host metadata nested under repo, not parallel root) |
| Billing | **Stripe cloud entitlement** via `push-backend` (`PurchaseManager.hasCloudEntitlement`) — dormant StoreKit IAP to remove or hide in Cursor Settings |
| Build order | **T0 → T1 → V1** (V1 core stays frozen until T0 device proof) |
| Competitor study | Happier/Orca already in `.study/`; Omnara + lfg cloned 2026-07-06 |

**Companion docs:**

- `docs/product/study/2026-07-06-apple-api-map.md` — Apple built-in vs custom
- `docs/product/study/2026-07-06-omnara-lfg-notes.md` — competitor borrow list
- `docs/product/study/2026-07-06-aggressive-cleanup-spec.md` — legacy delete status
- `docs/product/OWNER_RELAY_TEST_GUIDE.md` — **you + agent relay session**

---

## Lane 0 — Tier 0 live loop (P0)

**Goal:** pair → dispatch → approval → continue on **sim maximum**, then **physical device** with owner.

**Worktree:** `git worktree add ../tier0-live-loop -b cursor/tier0-live-loop claude/amazing-mayer-246fef`

| Task | Files (typical) | Acceptance |
|------|-----------------|------------|
| T0-1 | `CursorShellLiveBridge.swift`, `E2ERelayPairingView` | Live pair sheet completes against running `lancerd` |
| T0-2 | `CursorComposerSheet`, bridge dispatch | Typed prompt reaches `performDispatch` |
| T0-3 | `InboxViewModel`, `ApprovalRelay`, `CursorWorkThreadView` | Pending approval banner → approve → `decide()` |
| T0-4 | Bridge continue callback | Follow-up message resumes vendor session |
| T0-5 | `scripts/relay-approval-e2e.sh` | Harness PASS on sim (already) + owner device run |
| T0-6 | `ApprovalActionIntent` | Add `authenticationPolicy` for high-risk (Apple API map) |

**Reuse:** `DesignSystem/Cursor/CursorApprovalBanner`, `CursorConnectionBanner`, `CursorBottomComposer`.

**Do not touch:** V1 Away Launch Composer, Proof Suite mocks, Git/PR ship UI.

---

## Lane 1 — Tier 1 Cursor shell polish

**Worktree:** `git worktree add ../tier1-cursor-shell -b cursor/tier1-cursor-shell claude/amazing-mayer-246fef`

**Start after T0-1..T0-4 sim-green** (can parallelize T1 UI if files don't overlap).

| Task | Backlog | Acceptance |
|------|---------|------------|
| T1-1 | Connection health ladder | `CursorConnectionBanner` shows Orca-style phases from bridge |
| T1-2 | Approval above composer | `CursorApprovalBanner` live-gated on work thread |
| T1-3 | Cursor Settings depth | `CursorSettingsView` rows wired per `10-settings.html` |
| T1-4 | Composer chain flake | Fix `CursorAppShellExhaustiveTests` composer timing |
| T1-5 | Repo-first hydration | Thread list groups by repo; hosts nested in workspace detail |

---

## Lane 2 — V1 Away Mode core (frozen gate)

**Do not start until:** Tier 0 physical device checkpoint in `OWNER_RELAY_TEST_GUIDE.md` is PASS.

**Worktree:** `cursor/v1-away-core` branched from merged T0+T1.

Wireframe-only stubs OK first: Away Launch contract sheet, Question Card component, Proof artifact card shell — all using `DesignSystem/Cursor/*`.

---

## Lane 3 — Docs + hygiene (ongoing)

- Update `FEATURE_BACKLOG.md` status when tests pass
- Keep `gap-matrix` in sync
- No new planning sprawl — edit existing SSOT files only

---

## Subagent file boundaries (hard rule)

| Lane | May write | Must not write |
|------|-----------|----------------|
| T0 | `AppFeature/CursorStyle/*`, `CursorShellLiveBridge`, `LancerUITests/CursorShell*`, `daemon/lancerd` only if hook/dispatch fix | `DesignSystem/Cursor` tokens, Settings views |
| T1 | `DesignSystem/Cursor/*`, `CursorSettingsView`, connection/approval banners | `dispatch.go` without vendor-cli-audit |
| V1 | New V1-only views under `AppFeature/CursorStyle/` | Tier 0 bridge files |

---

## Verification gate (every merge)

1. `cd Packages/LancerKit && swift build && swift test`
2. `xcodebuild -scheme Lancer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
3. `LegacyUIRemovalTests` + `CursorShellLiveApprovalTests` + changed UITest class
4. If daemon touched: `cd daemon/lancerd && go test ./...`

---

## Next actions (orchestrator)

1. Create worktrees `tier0-live-loop` + `tier1-cursor-shell`
2. Dispatch T0-1..T0-4 subagents on `tier0-live-loop`
3. Run **OWNER_RELAY_TEST_GUIDE** Phase A–C with owner on Mac (relay already up)
4. Merge T0 slices → `amazing-mayer` → cherry-pick to integration branch when green
