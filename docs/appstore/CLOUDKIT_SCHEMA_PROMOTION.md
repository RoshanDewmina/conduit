# CloudKit schema promotion runbook — `LancerConversations`

**Why this exists:** cross-device conversation continuation
(`ARCHITECTURE.md` §11.2, landed 2026-07-03) added a custom private-database
zone, `LancerConversations`, with two new record types. CloudKit
auto-creates schema in the **Development** environment the first time the
app runs against it, but the **Production** environment (the one every
App Store / TestFlight install talks to) does not get those record types
until someone explicitly promotes the schema in the CloudKit Dashboard. This
gap is already flagged as an open P1 in `docs/STATUS_LEDGER.md` ("Production
burn list... CloudKit Production schema") and `docs/PUBLISH_READINESS_CHECKLIST.md`
item D2 — this doc is the step-by-step to close it.

**If this is skipped:** every App Store user's first CloudKit conversation
sync attempt fails against a Production container that only knows
whatever record types existed before 2026-07-03 (the pre-existing
`SyncEngine` `Host`/`Snippet` types) — `ConversationSyncEngine` calls will
error, degrading to the `.cloudStale`/local-only sync state, silently, for
every new install. Not a crash, but a broken advertised feature (Lancer Pro
sells "CloudKit sync... across your devices" per
`docs/distribution/APP_STORE_CONNECT_METADATA.md`).

---

## What needs to be promoted

Two record types, both defined in
`Packages/LancerKit/Sources/SyncKit/ConversationCloudRecords.swift`:

| Record type | Mutability | Key fields (from `ConversationCloudRecords.swift`) |
|---|---|---|
| `Conversation` | Mutable, last-write-wins | `title`, `agentID`, `hostName`, `cwd`, `status`, `createdAt`, `updatedAt`, `lastActivityAt`, `lastHostSeq`, optional: `vendor`, `hostID`, `model`, `budgetUSD`, `sourceHostID`, `sourceHostName`, `archivedAt` |
| `ConversationTurnChunk` | Immutable, created once per finished turn | `conversationID`, `ordinal`, `createdAt`, optional `hostSeqStart`/`hostSeqEnd`, and either an inline `payload` (String, JSON, <200 KB) or a `payloadAsset` (`CKAsset`, for payloads above the inline limit) |

Zone: `LancerConversations` (custom zone in the private database, one per
iCloud account — `zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName:
CKCurrentUserDefaultName)`, `ConversationCloudRecords.swift:47`).

Container: `iCloud.dev.lancer.mobile`
(`project.yml:111`,
`com.apple.developer.icloud-container-identifiers`).

---

## Pre-flight checks

1. **Confirm the Development schema actually exists first.** The record
   types are auto-created lazily, the first time
   `ConversationSyncEngine`/`CloudSync.ensureZoneExists` runs against a
   Development-environment build (a debug/simulator or ad-hoc build signed
   with the same container, with `LANCER_ICLOUD_ENABLED: true` — see
   `project.yml:90-95` — and an entitlements file that actually grants
   `icloud-services: CloudKit`, e.g. `Lancer.entitlements`, not
   `Lancer-DeviceTesting.entitlements`).
   - Run the app once against that build, create a conversation, and give
     `ConversationSyncEngine` time to push a `Conversation` +
     `ConversationTurnChunk` record.
2. **Confirm the paid Apple Developer Program capability is live** —
   `project.yml`'s comment block above the `Lancer` target's entitlements
   (lines 97-103) notes iCloud/CloudKit requires the paid account; this
   should already be true given TestFlight has shipped, but verify the
   iCloud capability + CloudKit container are enabled in the Apple
   Developer portal for `39HM2X8GS6` before touching the Dashboard.

## Promotion steps (CloudKit Dashboard)

1. Go to <https://icloud.developer.apple.com/dashboard/> → sign in with the
   Apple ID on team `39HM2X8GS6`.
2. Select container `iCloud.dev.lancer.mobile`.
3. Switch environment selector (top of the Dashboard) to **Development** and
   open **Schema** → **Record Types**. Confirm `Conversation` and
   `ConversationTurnChunk` are both listed with the fields in the table
   above (case-sensitive field names must match exactly what
   `ConversationCloudRecords.swift` writes).
4. Also check **Indexes**: any field the app queries by (at minimum,
   whatever `ConversationSyncEngine`'s zone-change fetch relies on —
   `recordName`/`modifiedTimestamp` are default-queryable; if a custom
   query field like `conversationID` on `ConversationTurnChunk` needs a
   queryable index for the app's fetch predicates, confirm it's marked
   queryable in Development first).
5. Click **Deploy Schema Changes to Production** (top-right of the Schema
   view). Review the diff CloudKit shows you — it should show exactly the
   two new record types (and nothing from an unrelated in-flight
   Development experiment; **do not deploy if the diff shows anything you
   don't recognize** — abort and investigate first).
6. Confirm the deploy. CloudKit schema deploys are **one-directional and
   effectively irreversible for field removal** — see rollback notes below
   before confirming.
7. Switch the environment selector to **Production** and re-open **Record
   Types** — confirm `Conversation` and `ConversationTurnChunk` now appear
   there with the same fields.

## Verification steps

1. **Archive-build smoke test.** Build a Release-configuration archive (or
   a TestFlight build) — which talks to the Production CloudKit
   environment by construction (Release always uses Production CloudKit;
   only Xcode-debug-signed builds use Development) — install it on a real
   device signed into a real iCloud account, and:
   - Create a conversation, let it sync, and confirm no CloudKit error is
     logged (`ConversationSyncEngine`'s sync state should reach `.synced`,
     not `.cloudStale`/`.conflict`).
   - In the CloudKit Dashboard, switch to **Production** → **Data** →
     browse the private database for that user's zone and confirm a
     `Conversation` record and at least one `ConversationTurnChunk` record
     exist with the expected field values.
2. **Two-device proof (separate, larger gate — do not conflate with schema
   promotion).** `docs/PUBLISH_READINESS_CHECKLIST.md` item C7 tracks a
   distinct, still-open gate: proving actual cross-device propagation
   (start on device A → appears on device B; kill/reinstall A → restores
   from CloudKit) and silent-push delivery via the registered
   `CKDatabaseSubscription`. That requires two physical Apple devices on
   the same iCloud account and is owner-gated per the checklist — schema
   promotion is a prerequisite for it, not a substitute.

## Rollback notes

- **Adding a record type or field is safe and reversible in the sense that
  an unused type/field costs nothing** — you can leave it in place even if
  a later app version stops writing it.
- **Removing or renaming a field/record type in Production is NOT something
  CloudKit lets you do via a simple redeploy** — CloudKit schema deploys are
  additive; Apple's guidance is that field/type removal in Production
  requires either leaving it permanently unused or, in the worst case,
  recreating the container. **Do not experiment directly against
  Production** — get the Development schema exactly right first (step 1-4
  above) since Production promotion is meant to be a one-way, low-risk
  "copy what Development already proved" operation, not a place to iterate.
- If a deploy is confirmed with an unexpected field (e.g. a stray
  Development-only debug field), the safe fix is to stop writing that field
  from the app going forward — it becomes permanently-present-but-unused
  metadata, not a class of bug requiring a Production schema revert.
- There is no "undo deploy" button — the mitigation for a bad promotion is
  forward-only (ship a fixed app version, leave the extra schema inert).

## Sources read this session

- `ARCHITECTURE.md` §11.2 "Cross-device sync"
- `Packages/LancerKit/Sources/SyncKit/ConversationCloudRecords.swift`
- `docs/PUBLISH_READINESS_CHECKLIST.md` item D2, item C7, item B9
- `docs/STATUS_LEDGER.md` "Open P0/P1" table ("Production burn list... CloudKit Production schema")
- `docs/product/2026-07-09-production-readiness-gaps.md` (CloudKit/cross-device row)
- `project.yml` lines 90-116 (entitlements, `LANCER_ICLOUD_ENABLED`, `icloud-container-identifiers`)
