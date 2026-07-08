#if canImport(AppIntents)
import AppIntents

// SyncableEntity conformances (I3, iOS 27+):
// `SyncableEntity` is an iOS 27 marker protocol that tells the App Intents
// runtime an entity's `id` is stable across devices — the same UUID resolves
// to the same logical object on iPhone, iPad, Apple Watch, and Mac without
// re-disambiguation. Confirmed @available(macOS 27.0, iOS 27.0, ...) against
// the installed iOS 27 SDK swiftinterface.
//
// Why these two entity types:
//   • ConversationEntity — conversation IDs are CloudKit-stable UUIDs:
//     `ConversationSyncCoordinator` (SyncKit) replicates them across all the
//     user's signed-in devices and they are never reassigned. Conforming is
//     additive and zero-cost: the protocol is empty (just a marker).
//   • RunEntity — run IDs are UUID strings passed through the relay from
//     `lancerd`, stable within a relay-machine's lifetime. They already
//     appear consistently in `ActiveRunRegistry` across sessions, making
//     them safe to treat as cross-device-stable identifiers.
//
// ApprovalEntity, MachineEntity, WorkspaceEntity intentionally excluded:
//   • ApprovalEntity IDs are per-machine and ephemeral.
//   • MachineEntity IDs include a "relay:" prefix that is local to the relay
//     bridge instance; they're not guaranteed stable across device add/remove.
//   • WorkspaceEntity IDs are relay-machine-scoped and not CloudKit-backed.

// Guarded by `#if swift(>=6.4)`, not just `@available(iOS 27.0, *)`: `SyncableEntity`
// doesn't exist in the iOS 26 SDK at all.
#if swift(>=6.4)

@available(iOS 27.0, macOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension ConversationEntity: SyncableEntity {}

@available(iOS 27.0, macOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension RunEntity: SyncableEntity {}

#endif // swift(>=6.4)

#endif
