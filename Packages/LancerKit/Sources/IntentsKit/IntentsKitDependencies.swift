#if canImport(AppIntents)
import Foundation
import PersistenceKit

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
}
#endif
