# WP-P1b Result

## What I changed

- Wired `RelayReviewDataSource` to the real relay path via a bridge-backed adapter (`RelayReviewBridge`) while preserving no-bridge fallback behavior (`supported: false` / empty data).
- Added five bounded (15s) repo review relay helpers in `E2ERelayBridge`:
  - `relayRepoTurnDiff`
  - `relayRepoSessionDiff`
  - `relayRepoFileDiff`
  - `relayRepoTree`
  - `relayRepoFile`
- Added matching relay result handlers in `E2ERelayBridge.handleRelayMessage` for:
  - `repoTurnDiffResult`
  - `repoSessionDiffResult`
  - `repoFileDiffResult`
  - `repoTreeResult`
  - `repoFileResult`
  including host error propagation via `RelayRepoError`.
- Updated review data-source injection in the two requested views:
  - `LiveThreadView.reviewDataSource` now uses the active/connected relay machine bridge when available, else fallback.
  - `ThreadDetailView.reviewDataSource` now uses first connected machine bridge when available, else fallback.
- Added review-path tests in `ReviewModelsTests`:
  - Verbatim Go-router envelope decode fixtures for all `repo.*Result` payload shapes.
  - Explicit nil-bridge fallback test ensuring unsupported/empty responses.

## Acceptance commands and output tails

### 1) `cd Packages/LancerKit && swift build`

```text
Building for debugging...
[Computing dependencies]
[Using on-disk description]
[1 / 156]
[2 / 11] AppFeature
[13 / 22] AppFeature
[19 / 22] AppFeature
Build complete! (2.04 secs.)
```

### 2) `cd Packages/LancerKit && swift test`

```text
...
✔ Test "decodes verbatim relay repo.* result payloads from Go router" passed after 0.170 seconds.
...
✔ Test "relay review source falls back when bridge is nil" passed after 0.170 seconds.
...
---
exit_code: 0
elapsed_ms: 35320
ended_at: 2026-07-14T02:26:18.508Z
---
```

### 3) `git diff --stat`

```text
 .../Sources/AppFeature/Chat/LiveThreadView.swift   |  17 +-
 .../AppFeature/Review/ReviewDataSource.swift       |  89 +++++++-
 .../AppFeature/ThreadDetail/ThreadDetailView.swift |   5 +-
 .../Sources/SessionFeature/E2ERelayBridge.swift    | 228 +++++++++++++++++++++
 .../Tests/LancerKitTests/ReviewModelsTests.swift   | 131 ++++++++++++
 5 files changed, 458 insertions(+), 12 deletions(-)
```

## Deviations from spec

- Introduced a small `RelayReviewBridge` protocol in `ReviewDataSource.swift` and an iOS-only conformance from `E2ERelayBridge`.
  - Reason: `E2ERelayBridge` is iOS-gated in `SessionFeature`; direct type usage in always-compiled `ReviewDataSource.swift` breaks non-iOS builds.
  - Effect: no behavior change to requested data path; this only preserves cross-platform compilation while wiring the requested bridge calls.
