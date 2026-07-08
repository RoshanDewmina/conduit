#if canImport(AppIntents)
import Foundation
import LancerCore
import PersistenceKit
@testable import IntentsKit

enum IntentsKitTestFixtures {
  static func withDatabase<T>(
    _ body: (AppDatabase) async throws -> T
  ) async throws -> T {
    let db = try AppDatabase.inMemory()
    return try await IntentsKitDependencies.$taskDatabase.withValue(db) {
      try await body(db)
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
