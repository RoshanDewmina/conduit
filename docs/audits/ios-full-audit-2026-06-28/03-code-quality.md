# 03 — Code Quality

The codebase is internally consistent and warning-clean (one type-check-time warning, ARCH-1). Items
below are small and local; none are blocking.

## Concurrency (verified)
- **CONC-2 (Medium, OPEN):** unconditional continuation resume in `DaemonChannel.sendRPC` catch
  (`DaemonChannel.swift:92-95`) → double-resume crash on disconnect-during-send. One-line guard fix.
- **CONC-1 (Low, OPEN):** orphaned 3s timeout `Task` in `SessionViewModel.swift:1010-1013` — store
  & cancel in `closeUnifiedShell()`.
- The 9 `@unchecked Sendable` + 2 `nonisolated(unsafe)` were each inspected: justifications hold
  (queue-isolation, immutable-after-init, NSLock `Protected<T>` wrapper). `PolicyPresetStore` /
  `TeamRoleStore` rely on `UserDefaults` thread-safety with no lock — acceptable today (single
  writer in practice); convert to `actor` only if a concurrent writer is ever introduced. **No fix.**

## Force-unwraps / casts (challenged)
- **CQ-1 (Low, OPEN):** `SettingsView.swift:666-668` `auditRepository!` is guarded by the enclosing
  `if … != nil` — safe, but use `if let`.
- **ACCT-476 (VERIFIED-SAFE):** `AccountClient.swift:476` `EmptyResponse() as! Response` is gated by
  a same-line type check — cannot fail. Optional: a default-constructible protocol removes the cast.
- The other ~22 `URL(string:)!` are over known-good literal endpoints — acceptable.

## Error handling
- **CQ-3 (Info, OPEN):** silent `try?` on a few persistence writes (`AppRoot.swift:421,426,1315,
  1331`) — add a failure log; toast for user-initiated saves. No data loss beyond the dropped write.

## Comments / docs / hygiene
- **CQ-2 (Info, OPEN):** stale `DSButton.primary` doc comment (renders accent/orange, like
  `.accent`) — historically caused a real white-button bug. Fix the comment.
- **CQ-4 (Info, OPEN):** candidate unused `import DiffFeature` (`AppRoot.swift:19`) — **grep for
  DiffFeature references before removing**; do not trust the candidate blindly.

## Compactness
No bloat sweep warranted. The giant files (AppRoot 2374, NewChatTabView 1374, SettingsView 1272,
SessionViewModel 1218) are large but cohesive per their surface; only ARCH-1's local extraction is
justified. Do **not** mass-split views or introduce single-use protocols — that adds indirection
without measured benefit (`agent-contract.md` §3).
