# Disk & Workspace Cleanup — 2026-07-06

Executed by Claude Cloud Agent on `cursor/workspace-cleanup-2026-07-06`.  
Repo root: `/Users/roshansilva/Documents/command-center`

---

## Summary

| Metric | Before | After |
|---|---|---|
| Free disk (`/System/Volumes/Data`) | **4.8 GB** (99% full) | **47 GB** (89% full) |
| Capacity used | 404 GB / 460 GB | 362 GB / 460 GB |
| **Freed** | — | **~42 GB** |

Master build result: `Build complete! (5.28 secs.)` — `cd Packages/LancerKit && swift build` on `origin/master` clean.

---

## Phase 2 — Deletions Executed

### Xcode DerivedData (largest win)

| Path | Size reclaimed | Reason |
|---|---|---|
| `~/Library/Developer/Xcode/DerivedData/Lancer-cvzaoxzrtyvkozclcvleezrvghrx` | 7.0 GB | Stale Lancer build cache |
| `~/Library/Developer/Xcode/DerivedData/Lancer-ecglbxlaauasnnazkhdmviuidudl` | 5.4 GB (16 MB residual locked) | Stale Lancer build cache |
| `~/Library/Developer/Xcode/DerivedData/Lancer-bifedywdxrkmctelgbrlaupidffu` | 5.3 GB | Stale Lancer build cache |
| `~/Library/Developer/Xcode/DerivedData/Lancer-hkeouceswtovooesbpujocvwjzgx` | 5.2 GB | Stale Lancer build cache |
| `~/Library/Developer/Xcode/DerivedData/Lancer-bovhporfjyergufmpumkznqnptmi` | 4.0 GB | Stale Lancer build cache |
| `~/Library/Developer/Xcode/DerivedData/Lancer-evtrbilozpptjdddqrkczvsxsbba` | 3.5 GB | Stale Lancer build cache |
| `~/Library/Developer/Xcode/DerivedData/Lancer-flajqyidheiwxtftefrqdlmuhzwa` | 3.4 GB | Stale Lancer build cache |
| `~/Library/Developer/Xcode/DerivedData/Lancer-efwqixtfypfizrcpqemfzjkchgvx` | 3.4 GB | Stale Lancer build cache |
| **Total DerivedData** | **37.2 GB** | — |

Command run: `rm -rf ~/Library/Developer/Xcode/DerivedData/Lancer-*`  
Note: One directory (`ecglbxlaauasnnazkhdmviuidudl`) had 16 MB of APFS-locked files that could not be removed; all substantial content was freed.

### /tmp Build Caches

| Path | Size reclaimed | Reason |
|---|---|---|
| `/tmp/lancer-tier0-dd` | 4.8 GB | Tier 0 test DerivedData cache |
| `/tmp/lancer-relay-e2e-derived-data` | 4.4 GB | E2E relay test DerivedData cache |
| `/tmp/lancer-e2e-workspace/` | < 1 MB | Empty e2e workspace stub |
| `/tmp/lancer-*.log`, `/tmp/lancer-*.json` | ~5 MB | Test run logs (device-build, live-approval, relay-e2e, sidebar, tapinjection, etc.) |
| **Total /tmp** | **~9.2 GB** | — |

### Empty Stub Directories

| Path | Action |
|---|---|
| `~/Documents/cc-merge-verify` | Removed (`rmdir`) — empty directory |
| `~/Documents/cc-wt` | Removed (`rmdir`) — empty directory |

### Merged Git Worktree Removed

| Worktree path | Branch | Size | Merge status | Notes |
|---|---|---|---|---|
| `.claude/worktrees/amazing-mayer-246fef/tier0-live-loop` | `cursor/tier0-live-loop` | 2.3 GB | **MERGED** into `origin/master` | Only had a trivial 1-line `Package.resolved` change (version bump from a build); no real work lost |

Command: `git worktree remove ".claude/worktrees/amazing-mayer-246fef/tier0-live-loop" --force`

### Stale Merged Local Branches Deleted (no worktrees attached)

20 branches deleted via `git branch -d` / `git branch -D`:

```
audit/ios-2026-06-28
claude/adoring-margulis-0ae6eb
claude/bold-nash-8c3439
claude/busy-allen-e458f9
claude/intelligent-leakey-a68595
claude/loving-colden-c1f036
claude/nostalgic-archimedes-20bc5f
codex/ios27-shell-workspace
codex/uiux-audit
cursor/device-handoff-9257
cursor/sendapproval-log-9257
cursor/tier0-live-loop
cursor/voiceover-b8-remainder-9257
cursor/worktree-per-run-9257
fable/approval-security-hardening
fable/relay-connection-state
integration/security-plus-worktree
opencode/onboarding-redesign
worktree-agent-aac59917d8ef1a591
worktree-agent-af72b53c7c6d7c89b
```

These were all confirmed merged into `origin/master` via `git branch --merged origin/master` and `git merge-base --is-ancestor`.

---

## Phase 3 — Repo Clutter (origin/master state)

Checked from `cursor/workspace-cleanup-2026-07-06` (based on `origin/master` at `7697c39c`):

- **No empty source directories** found under `Packages/LancerKit/Sources/`
- **No dead-component references** found — all deleted components (`AgentHUDStore`, `AgentIsland`, `BlastRadiusView`, `ChatComponents`, `ProComponents`, `InboxApprovalCard`, `DSReviewSheet`, etc.) cleanly removed with no dangling imports or usages
- **No untracked junk** in the `origin/master` branch state (only `tier1-cursor-shell/` nested worktree is untracked, which is live work)
- **`.superpowers/brainstorm/`** — not present in `origin/master`; present in local worktrees (64 KB stale sessions, stopped servers) — left for owner
- **`docs/design-audit/`** — `lancer-expanded-mobile-2026-07-05/` and `proof-to-ship-wireframes-2026-07-05/` already deleted before PR #28; remaining content is design reference docs the owner likely wants to keep
- **`docs/test-runs/`** — 372 KB of test verification docs, all appear intentional; no duplicates removed

---

## Remaining Owner Decisions Required

### Decision 1 — Local `master` branch divergence

The local `master` branch (`amazing-mayer-246fef` worktree) has **3 commits not in `origin/master`** and origin has **22 commits not in local master**. This is a real divergence from the `cursor-style-app-shell` work:

```
Local-only: a1928c48 docs(product): add feature implementation gap matrix
            c29d2d16 Merge branch 'cursor-style-app-shell' into master
            d38c67e7 feat(ios): land Cursor app shell with Tier-0 live bridge
```

**Action needed:** Decide whether to rebase or merge local master onto `origin/master`. Potential conflict area: the cursor-style component deletions in local master vs the tier1 shell work in origin/master.

```bash
cd .claude/worktrees/amazing-mayer-246fef
git fetch origin
git rebase origin/master   # or: git merge origin/master
```

---

### Decision 2 — `clever-payne-ff4643` worktree (37 MB) with uncommitted changes

Branch `claude/clever-payne-ff4643` at `a1928c48` has **6 uncommitted Swift file modifications**:

- `CursorBottomSheetContainer.swift`, `CursorAppShell.swift`, `CursorComposerSheet.swift`  
- `CursorWorkThreadView.swift`, `CursorWorkspaceThreadListView.swift`, `CursorWorkspacesView.swift`

These are cursor-style redesign files being modified. **Unknown if this is orphaned work from a prior session or intentional in-progress work.** Do not delete until content is reviewed.

```bash
# To inspect:
cd .claude/worktrees/clever-payne-ff4643 && git diff

# To remove if orphaned (ONLY after verifying content is duplicate/stale):
cd /Users/roshansilva/Documents/command-center
git worktree remove .claude/worktrees/clever-payne-ff4643 --force
git branch -D claude/clever-payne-ff4643
```

---

### Decision 3 — Three stale claude worktrees at `a1928c48` (no uncommitted changes)

All three are at the old local master HEAD (`a1928c48`) with **no uncommitted changes** and branches not merged to origin/master:

| Worktree | Branch | Size | Notes |
|---|---|---|---|
| `.claude/worktrees/cool-herschel-40dd38` | `claude/cool-herschel-40dd38` | 37 MB | Empty — safe to remove |
| `.claude/worktrees/focused-tereshkova-2fe39c` | `claude/focused-tereshkova-2fe39c` | 37 MB | Empty — safe to remove |
| `.claude/worktrees/upbeat-mirzakhani-a74cf1` | `claude/upbeat-mirzakhani-a74cf1` | 54 MB | Empty — safe to remove |

These are likely stale Cursor Cloud Agent session worktrees. **Recommend removal** if no agent is actively using them.

```bash
cd /Users/roshansilva/Documents/command-center
for wt in cool-herschel-40dd38 focused-tereshkova-2fe39c upbeat-mirzakhani-a74cf1; do
  git worktree remove ".claude/worktrees/$wt" --force
  git branch -D "claude/$wt"
done
```

**Potential recovery: ~128 MB**

---

### Decision 4 — `tier1-cursor-shell` nested worktree (2.3 GB)

Branch `cursor/tier1-cursor-shell` at `a5cc2217`, **NOT merged** to `origin/master`, no uncommitted changes.

```bash
# To remove if work is superseded by PR #28:
cd /Users/roshansilva/Documents/command-center
git worktree remove ".claude/worktrees/amazing-mayer-246fef/tier1-cursor-shell" --force
git branch -D cursor/tier1-cursor-shell
```

**Potential recovery: 2.3 GB**

---

### Decision 5 — `.cursor/worktrees/` (Cursor editor worktrees, ~6 GB total)

| Worktree | Branch | Size | Merged? | Notes |
|---|---|---|---|---|
| `docs-away-mode-cleanup` | `docs-away-mode-cleanup` | 39 MB | No | No uncommitted changes |
| `revenuecat-migration` | `revenuecat-migration` | 3.4 GB | No | No uncommitted changes |
| `security-p0-followup` | `security-p0-followup` | 2.3 GB | No | No uncommitted changes |
| `skill-cross-platform-audit` | `skill-cross-platform-audit` | 37 MB | No | No uncommitted changes |
| `skill-second-opinion-audit` | `skill-second-opinion-audit` | 37 MB | No | No uncommitted changes |

If these branches contain work you no longer need, remove them via the Cursor editor or:
```bash
cd /Users/roshansilva/Documents/command-center
git worktree remove ~/.cursor/worktrees/command-center/<name> --force
git branch -D <branch-name>
```

**Potential recovery if all removed: ~6 GB**

---

### Decision 6 — `Documents/.claude/worktrees/` tier0 worktrees (~4.3 GB total)

| Worktree | Branch | Size | Merged? |
|---|---|---|---|
| `tier0-approval-9aec` | `cursor/tier0-approval-9aec` | 2.1 GB | No |
| `tier0-settings-9aec` | `cursor/tier0-settings-9aec` | 2.1 GB | No |
| `tier0-attention-9aec` | `cursor/tier0-attention-9aec` | 37 MB | No |

These may contain tier-0 work from the `9aec` sprint that was never merged. If superseded by PR #28, safe to remove.

```bash
cd /Users/roshansilva/Documents/command-center
git worktree remove ~/Documents/.claude/worktrees/tier0-approval-9aec --force
git worktree remove ~/Documents/.claude/worktrees/tier0-settings-9aec --force
git worktree remove ~/Documents/.claude/worktrees/tier0-attention-9aec --force
git branch -D cursor/tier0-approval-9aec cursor/tier0-settings-9aec cursor/tier0-attention-9aec
```

**Potential recovery: ~4.3 GB**

---

### Decision 7 — `cc-lane-02` and `cc-lane-04` (~4.6 GB total)

| Path | Branch | Size | Merged? |
|---|---|---|---|
| `~/Documents/cc-lane-02` | `cursor/siri-phase2-fixes-9257` | 2.3 GB | No |
| `~/Documents/cc-lane-04` | `cursor/pr20-redaction-9257` | 2.3 GB | No |

These are standalone worktrees at `9257`-sprint commits. If those PRs/features are complete and merged elsewhere, these can be removed.

```bash
cd /Users/roshansilva/Documents/command-center
git worktree remove ~/Documents/cc-lane-02 --force
git worktree remove ~/Documents/cc-lane-04 --force
git branch -D cursor/siri-phase2-fixes-9257 cursor/pr20-redaction-9257
```

**Potential recovery: ~4.6 GB**

---

## Additional Potential Savings (if all deferred items removed)

| Item | Estimated Recovery |
|---|---|
| `clever-payne-ff4643` | 37 MB |
| `cool-herschel-40dd38` + `focused-tereshkova-2fe39c` + `upbeat-mirzakhani-a74cf1` | ~128 MB |
| `tier1-cursor-shell` | 2.3 GB |
| `.cursor/worktrees/` (all 5) | ~6 GB |
| `tier0-approval/settings/attention` worktrees | ~4.3 GB |
| `cc-lane-02` + `cc-lane-04` | ~4.6 GB |
| **Total potential additional** | **~17.4 GB** |

---

## Current Worktree Inventory (post-cleanup)

```
/Users/roshansilva/Documents/command-center          [cursor/user-ready-tier0-9aec] @ b54a40e9  (has uncommitted changes — DO NOT disturb)
~/.cursor/worktrees/command-center/docs-away-mode-cleanup    [docs-away-mode-cleanup] @ be8c3e65
~/.cursor/worktrees/command-center/revenuecat-migration      [revenuecat-migration] @ d7f298f0
~/.cursor/worktrees/command-center/security-p0-followup      [security-p0-followup] @ e8616e10
~/.cursor/worktrees/command-center/skill-cross-platform-audit [skill-cross-platform-audit] @ a5e389f9
~/.cursor/worktrees/command-center/skill-second-opinion-audit [skill-second-opinion-audit] @ 8bbeacd0
~/Documents/.claude/worktrees/tier0-approval-9aec    [cursor/tier0-approval-9aec] @ a29ddec7
~/Documents/.claude/worktrees/tier0-attention-9aec   [cursor/tier0-attention-9aec] @ 8ad8e9f0
~/Documents/.claude/worktrees/tier0-settings-9aec    [cursor/tier0-settings-9aec] @ a34edad3
~/Documents/cc-lane-02                               [cursor/siri-phase2-fixes-9257] @ 954ab264
~/Documents/cc-lane-04                               [cursor/pr20-redaction-9257] @ d9c266f0
command-center/.claude/worktrees/amazing-mayer-246fef [cursor/workspace-cleanup-2026-07-06] @ 7697c39c  ← THIS RUN
command-center/.claude/worktrees/amazing-mayer-246fef/tier1-cursor-shell [cursor/tier1-cursor-shell] @ a5cc2217
command-center/.claude/worktrees/clever-payne-ff4643 [claude/clever-payne-ff4643] @ a1928c48  (has 6 uncommitted Swift files)
command-center/.claude/worktrees/cool-herschel-40dd38 [claude/cool-herschel-40dd38] @ a1928c48
command-center/.claude/worktrees/focused-tereshkova-2fe39c [claude/focused-tereshkova-2fe39c] @ a1928c48
command-center/.claude/worktrees/upbeat-mirzakhani-a74cf1 [claude/upbeat-mirzakhani-a74cf1] @ a1928c48
```

---

*Generated by Claude cleanup agent — 2026-07-06*
