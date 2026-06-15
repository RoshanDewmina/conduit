# opencode/phase-next — Completion Report

**Date:** 2026-06-15
**Branch:** `opencode/phase-next` (off `codex/uiux-audit`)
**Author:** opencode agent

---

## Overview

Three tasks executed on a new branch `opencode/phase-next` (forked from
`codex/uiux-audit`). All Go code builds and tests pass (`go build ./...` and
`go test ./...` in both `daemon/conduitd` and `daemon/push-backend`). The
iOS ConduitKit package also builds (`swift build`).

---

## TASK 1 — Integrate git v1 feature set ✅

**Merge commit:** `604e3812` (from `worktree-agent-af1f307f6841d8ff4`) merged
into `opencode/phase-next`.

### What was merged:
- `daemon/conduitd/git.go` — 496 lines: host-side git RPCs (status, diff,
  changedFiles, ship/commit+push+PR, worktree list, CI proxy)
- `daemon/conduitd/git_test.go` — 295 lines: test coverage
- `SSHTransport/DaemonChannel.swift` — 100+ lines added: `gitStatus()`,
  `gitDiff()`, `gitChangedFiles()`, `gitShip()`, `listWorktrees()`,
  `recentCIEvents()`, `fetchPolicyYAML()`, `savePolicyYAML()`,
  `simulatePolicy()`
- `AppFeature/GitStore.swift` — 113 lines: new `@Observable` store calling
  daemon git RPCs
- `AppFeature/AgentRunDetailView.swift` — 194 lines added: "Changes" section
  with branch chip, file list, diff review, "Ship it" confirmation sheet,
  PR link display
- `AppFeature/LoopDetailView.swift` — 237 lines added: CI section + proof
  card wiring
- `AppFeature/WorktreeStore.swift` — updated: now calls `listWorktrees(workdir:)`
- `AppFeature/FleetView.swift` — `gitStore(for:)` + `ciEventLoader(for:)`
  wires GitStore + CI events into LoopDetailView
- `daemon/conduitd/server.go` — 128 lines added: `agent.git.status`,
  `agent.git.diff`, `agent.git.changedFiles`, `agent.git.ship`,
  `agent.worktree.list`, `agent.ci.recent`, `agent.policy.get/set/reload`
  RPC handlers

### Merge details:
- Single auto-merge in `daemon/conduitd/server.go` (clean, no conflicts)
- No other conflicts

### Verification:
- `go build ./...` ✅
- `go test ./...` ✅ (conduitd: 17.3s, policy: cached)
- `swift build` ✅ (ConduitKit)

---

## TASK 2 — Fix facades per DEAD_FEATURES_BACKLOG.md ✅

### 2.1 Scoped allow-always — FIXED

**Files changed:**
- `InboxFeature/InboxView.swift`:
  - Added `onSetPolicy: ((String) async -> Void)?` property + initializer param
  - Scope sheet completion now calls `buildPolicyYAML()` and sends the YAML
    via `onSetPolicy` closure in addition to local UserDefaults persist
- `AppFeature/AppRoot.swift`:
  - Passes `actions.savePolicyYAML` as `onSetPolicy` when creating InboxView

### 2.2 Worktree board — FIXED

**Files changed:**
- `AppFeature/WorktreeBoardView.swift`:
  - `.task {}` and `.refreshable {}` now derive `workdirByHost` from fleet
    slots' `sessionViewModel.cwd` (where connected + non-empty)
  - Previously called `store.refresh()` with no workdirs → always empty

### 2.3 CI/PR — FIXED (was part of git-v1 merge)

Already verified: `agent.ci.recent` RPC registered, proxies push-backend.

### 2.4 Blocked-state OS — FIXED

**Files changed:**
- `SessionFeature/Chat/ChatHeaderView.swift`:
  - Added `blockedReason: BlockedReason?` property + init parameter
  - When non-nil, renders `DSBlockedReasonRow(reason)` below header HStack
- `SessionFeature/SessionView.swift`:
  - Passes `vm.blockedReason` to ChatHeaderView

**DEAD_FEATURES_BACKLOG.md** updated to reflect all fixes.

---

## TASK 3 — Host-prints-QR onboarding (terminal QR + real installer) ✅

### 3.1 Terminal QR in `conduitd pair`

**Dependency added:** `github.com/skip2/go-qrcode` (pure Go QR library)

**Files changed:**
- `daemon/conduitd/relay_install_helper.go`:
  - `printRelayInstructions()` now generates an ephemeral X25519 keypair
  - Creates `qrPairingPayload` JSON matching iOS `QRPairingPayload` format
    (`{"v":1,"relay":"<url>","code":"<code>","pk":"<daemonPubKey>"}`)
  - Renders QR code to terminal using ASCII block characters
  - Keeps the existing numeric code box as fallback for manual entry

**Verified:** `go run . pair` prints QR + code + relay URL.

### 3.2 Real `curl | sh`-style installer

**Files changed:**
- `daemon/conduitd/install.sh`:
  - Added `--download-base <url>` flag for prebuilt binary URL
  - Added download path: detects OS/arch, fetches from
    `$DOWNLOAD_BASE/conduitd_${os}_${arch}` using curl or wget
  - After install, runs `conduitd pair` to print pairing QR
  - Added help text for `curl -fsSL https://conduit.dev/install.sh | sh` UX
  - Retains `--from-source` and `--hooks` flags

**Note:** The `curl conduit.dev/install.sh | sh` flow requires a release
pipeline (build/sign/publish binaries + the install.sh at a public domain).
This is documented as the intended UX path in the script's header and in
`ONBOARDING_CONNECT_RESEARCH.md`.

---

## Commit log on `opencode/phase-next`

```
<current_hash>  (HEAD -> opencode/phase-next) — TASK 3: terminal QR in conduitd pair + curl|sh installer
<merge_hash>   Merge commit '604e3812' — TASK 1: git v1 feature set + TASK 2: facade fixes
62652d21       docs(audit): feature verification, dead-features backlog, git + onboarding research
8aaf1605       fix(pairing): keyless QR relay works end-to-end + security hardening
```

(Exact commit hashes will be visible via `git log --oneline opencode/phase-next`.)

---

## What was NOT done (needs-review / future)

1. **PolicyEditorView** — still reads UserDefaults for display. The daemon
   rules written by `agent.policy.set` land in the daemon's in-memory store.
   PolicyEditor could be enhanced to fetch from `agent.policy.get` for a
   unified view. Low priority — the enforcement path is correct.
2. **iOS app-target build** — `swift build` inside ConduitKit (SPM) was
   verified, but the full Xcode app target build (which catches
   strict-concurrency breaks) was not run. Any `.swift` changes should be
   reviewed by the human reviewer.
3. **`curl conduit.dev/install.sh` live domain** — the installer code is
   ready but requires: (a) a release pipeline that builds & signs conduitd
   binaries for linux/macOS × amd64/arm64, (b) a domain serving install.sh
   and binaries over HTTPS. Documented in `install.sh` header and
   `ONBOARDING_CONNECT_RESEARCH.md`.
4. **E2ERelayClient.swift keepalive** — left untouched per constraint.
   The stash (`git stash pop` once keepalive hardening is ready) contains
   in-flight changes.