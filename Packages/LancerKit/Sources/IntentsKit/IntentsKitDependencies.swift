#if canImport(AppIntents)
import Foundation
import LancerCore
import PersistenceKit
import SSHTransport

/// Injectable seams for entity queries. Production wiring (e.g. `ActiveRunRegistry`)
/// lands in D2 when `RunControlIntents` is refactored; tests override these hooks.
@available(iOS 17.0, *)
public enum IntentsKitDependencies {
  @TaskLocal static var taskDatabase: AppDatabase?

  /// Database factory used by every entity query. Tests set `taskDatabase`; production
  /// falls back to the shared on-disk store.
  nonisolated(unsafe) public static var database: @Sendable () throws -> AppDatabase = {
    if let taskDatabase {
      return taskDatabase
    }
    return try AppDatabase.openShared()
  }

  @TaskLocal static var taskActiveRunIDs: [String]?

  /// Mirror of `ActiveRunRegistry.shared.activeRunIDs`. Defaults empty until D2 wires it.
  nonisolated(unsafe) public static var activeRunIDs: @Sendable () -> [String] = {
    taskActiveRunIDs ?? []
  }

  @TaskLocal static var taskRelayMachines: [RelayMachineRecord]?

  /// Relay-paired machines (Siri Phase 2, I1): mirrors `RelayMachineMigration.readIndex()`,
  /// the same Keychain-persisted snapshot `RelayFleetStore` hydrates from at launch — kept
  /// as an injectable seam (rather than calling the `@MainActor` Keychain reader directly
  /// from entity queries, which run off-main) so tests never touch the real device Keychain.
  nonisolated(unsafe) public static var relayMachineSnapshots: @Sendable () async -> [RelayMachineRecord] = {
    if let taskRelayMachines {
      return taskRelayMachines
    }
    return await RelayMachineMigration.readIndex()
  }
}
#endif
