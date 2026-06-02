# WS-14 — Real bidirectional iCloud sync  (post-launch)

> Do NOT un-hide the Sync UI until this lands (WS-9 hides it for v1). Needs a paid Apple account + a configured CloudKit container; compiled out on the simulator. Larger effort — scope carefully.

## Context
Repo `/Users/roshansilva/Documents/command-center`, branch off `feat/warp-style-agent-blocks`. Build: `cd Packages/ConduitKit && swift build`. Module: `SyncKit` (`SyncEngine.swift`, `CloudSync.swift`). Read `ARCHITECTURE.md`.

**Confirmed state:** `SyncEngine.performSync()` only **pushes** Hosts (name/hostname/port/username — *no key material*) and Snippets to the CloudKit private DB; account-gated; compiled out on sim. Gaps: `CloudSync.fetchChanges()` exists but is **never called** (no pull/merge/restore); no conflict handling (`conflictCount` declared, never incremented) despite a "last-write-wins" comment; **no key linkage** (a restored host has no SSH-key reference, so it can't connect); no settings/key sync, no backup/restore, no migration, no progress UI.

## Tasks
1. **Pull + merge** — call `CloudSync.fetchChanges()`; implement real last-write-wins with a working `conflictCount`.
2. **Restore-on-new-device** — bring down Hosts + Snippets onto a fresh install.
3. **Host↔key reference design** — so a restored host knows which stored key to use (keys themselves stay device-local in Keychain; sync a *reference*, not key material). This is the crux — design it explicitly and document what is/isn't synced.
4. **Progress UI** + error handling; only then un-hide the Sync row (coordinate with WS-9).
5. Tests for merge/conflict logic where the harness allows (the `SyncEngine` date test was previously de-flaked — keep it stable).

## Constraints
- **Never sync private key material** — references only; keys stay in Keychain. · Don't ship a half-working "Sync" that implies backup — keep it hidden until restore actually works.

## Acceptance
- Bidirectional sync (push + pull + merge) with real conflict handling; restore-on-new-device works; restored hosts can connect via the key-reference design; progress UI; documented sync scope. Build + suite green.

## Report Template (fill in, return)
```
## WS-14 Report
### Pull/merge: <fetchChanges wired? LWW + conflictCount working?>
### Restore-on-new-device: <result>
### Host↔key reference design: <how; confirm no key material synced>
### Progress UI + Sync row un-hidden: <state>
### Tests: <merge/conflict coverage> · Build/Suite: <green/red>
### Files changed: <list> · Deviations/risks:
```
