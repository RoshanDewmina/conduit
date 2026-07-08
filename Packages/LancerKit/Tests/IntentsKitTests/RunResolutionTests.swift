#if canImport(AppIntents)
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

/// `RunEntityQuery.resolveActiveRun()` backs `PauseRunIntent`/`StopRunIntent`'s
/// "no run named" default: act directly on the sole active run, else surface
/// candidates for `IntentParameter.requestDisambiguation` (D2).
@Suite("RunEntityQuery.resolveActiveRun")
struct RunResolutionTests {
  @Test("zero active runs resolves to .none")
  func zeroActiveRuns() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      try await IntentsKitTestFixtures.withActiveRuns([]) {
        let resolution = try await RunEntityQuery().resolveActiveRun()
        guard case .none = resolution else {
          Issue.record("expected .none, got \(resolution)")
          return
        }
      }
    }
  }

  @Test("sole active run resolves without disambiguation")
  func soleActiveRun() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      try await IntentsKitTestFixtures.withActiveRuns(["run-1"]) {
        let resolution = try await RunEntityQuery().resolveActiveRun()
        guard case .sole(let entity) = resolution else {
          Issue.record("expected .sole, got \(resolution)")
          return
        }
        #expect(entity.id == "run-1")
      }
    }
  }

  @Test("multiple active runs surface all candidates for disambiguation")
  func multipleActiveRuns() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      try await IntentsKitTestFixtures.withActiveRuns(["run-a", "run-b", "run-c"]) {
        let resolution = try await RunEntityQuery().resolveActiveRun()
        guard case .ambiguous(let candidates) = resolution else {
          Issue.record("expected .ambiguous, got \(resolution)")
          return
        }
        #expect(candidates.count == 3)
        #expect(Set(candidates.map(\.id)) == ["run-a", "run-b", "run-c"])
      }
    }
  }
}
#endif
