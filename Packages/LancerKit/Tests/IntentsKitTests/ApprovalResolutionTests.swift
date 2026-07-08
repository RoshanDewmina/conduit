#if canImport(AppIntents)
import Foundation
import Testing
import LancerCore
import PersistenceKit
@testable import IntentsKit

/// `ApprovalEntityQuery.resolveMostRecentPending()` backs the pre-D2 "Deny the
/// latest approval" phrase, which still needs to work without naming an
/// `ApprovalEntity` — it must resolve to the newest pending approval (D2).
@Suite("ApprovalEntityQuery.resolveMostRecentPending")
struct ApprovalResolutionTests {
  private func seedApproval(
    db: AppDatabase,
    command: String,
    hostName: String,
    createdAt: Date
  ) async throws -> Approval {
    let sessionID = SessionID()
    let approval = Approval(
      sessionID: sessionID,
      agent: .claudeCode,
      kind: .command,
      command: command,
      cwd: "/repo",
      risk: .high,
      createdAt: createdAt
    )
    try await ApprovalRepository(db).upsert(approval)
    try await BlockRepository(db).persist(
      Block(
        sessionID: sessionID,
        prompt: Block.PromptInfo(cwd: "/repo", hostName: hostName),
        command: command
      )
    )
    return approval
  }

  @Test("no pending approvals resolves to .none")
  func noPendingApprovals() async throws {
    try await IntentsKitTestFixtures.withDatabase { _ in
      let resolution = try await ApprovalEntityQuery().resolveMostRecentPending()
      guard case .none = resolution else {
        Issue.record("expected .none, got \(resolution)")
        return
      }
    }
  }

  @Test("single pending approval resolves directly")
  func singlePendingApproval() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let approval = try await seedApproval(db: db, command: "rm -rf build", hostName: "mac-studio", createdAt: .now)

      let resolution = try await ApprovalEntityQuery().resolveMostRecentPending()
      guard case .mostRecent(let entity) = resolution else {
        Issue.record("expected .mostRecent, got \(resolution)")
        return
      }
      #expect(entity.id == approval.id.uuidString)
    }
  }

  @Test("multiple pending approvals resolve to the newest one")
  func multiplePendingApprovalsPicksNewest() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let older = try await seedApproval(
        db: db, command: "rm -rf dist", hostName: "mac-studio",
        createdAt: Date(timeIntervalSince1970: 1_000)
      )
      let newer = try await seedApproval(
        db: db, command: "rm -rf build", hostName: "mac-studio",
        createdAt: Date(timeIntervalSince1970: 2_000)
      )

      let resolution = try await ApprovalEntityQuery().resolveMostRecentPending()
      guard case .mostRecent(let entity) = resolution else {
        Issue.record("expected .mostRecent, got \(resolution)")
        return
      }
      #expect(entity.id == newer.id.uuidString)
      #expect(entity.id != older.id.uuidString)
    }
  }

  @Test("entity carries the Host row's UUID so deny audits under the real host")
  func hostIDResolvesFromHostRow() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      let host = LancerCore.Host(name: "mac-studio", hostname: "studio.local", username: "dev")
      try await HostRepository(db).upsert(host)
      _ = try await seedApproval(db: db, command: "rm -rf build", hostName: "mac-studio", createdAt: .now)

      let resolution = try await ApprovalEntityQuery().resolveMostRecentPending()
      guard case .mostRecent(let entity) = resolution else {
        Issue.record("expected .mostRecent, got \(resolution)")
        return
      }
      #expect(entity.hostID == host.id.uuidString)
    }
  }

  @Test("hostID stays nil when the approval matches no Host row")
  func hostIDNilWhenUnresolvable() async throws {
    try await IntentsKitTestFixtures.withDatabase { db in
      _ = try await seedApproval(db: db, command: "rm -rf build", hostName: "mac-studio", createdAt: .now)

      let resolution = try await ApprovalEntityQuery().resolveMostRecentPending()
      guard case .mostRecent(let entity) = resolution else {
        Issue.record("expected .mostRecent, got \(resolution)")
        return
      }
      #expect(entity.hostID == nil)
    }
  }
}
#endif
