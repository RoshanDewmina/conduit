#if canImport(AppIntents)
import Foundation
import LancerCore
import PersistenceKit
@testable import IntentsKit

enum IntentsKitTestFixtures {
  /// Pins the relay-machine seam too (default: none) so entity queries never
  /// fall through to `RelayMachineMigration.readIndex()` — the real Keychain —
  /// on the test host.
  static func withDatabase<T>(
    relayMachines: [RelayMachineRecord] = [],
    _ body: (AppDatabase) async throws -> T
  ) async throws -> T {
    let db = try AppDatabase.inMemory()
    return try await IntentsKitDependencies.$taskDatabase.withValue(db) {
      try await IntentsKitDependencies.$taskRelayMachines.withValue(relayMachines) {
        try await body(db)
      }
    }
  }

  static func withActiveRuns<T>(
    _ runIDs: [String],
    _ body: () async throws -> T
  ) async throws -> T {
    try await IntentsKitDependencies.$taskActiveRunIDs.withValue(runIDs) {
      try await body()
    }
  }
}
#endif
