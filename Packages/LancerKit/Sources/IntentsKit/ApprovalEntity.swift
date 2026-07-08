#if canImport(AppIntents)
import AppIntents
import Foundation
import LancerCore
import PersistenceKit

/// Pending approval surfaced to Siri. Volatile — queries always read fresh rows and never cache.
@available(iOS 17.0, *)
public struct ApprovalEntity: AppEntity, Identifiable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Approval")
  public static let defaultQuery = ApprovalEntityQuery()

  public let id: String
  public let title: String
  /// UUID string of the originating Host row, nil when unresolvable — consumers
  /// pass it to `ApprovalRelay.enqueue` so deny audits under the real host
  /// instead of the empty hostID the pre-D2 intent wrote.
  public let hostID: String?

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)")
  }

  init(approval: Approval, hostName: String, hostID: String?) {
    id = approval.id.uuidString
    let summary = IntentsKitSupport.approvalActionSummary(approval)
    title = IntentsKitSupport.approvalDisplayTitle(
      actionSummary: summary,
      risk: approval.risk,
      hostName: hostName
    )
    self.hostID = hostID
  }
}

@available(iOS 17.0, *)
public struct ApprovalEntityQuery: EntityQuery, EntityStringQuery {
  public init() {}

  public func entities(for identifiers: [ApprovalEntity.ID]) async throws -> [ApprovalEntity] {
    let wanted = Set(identifiers)
    return try await materialize(include: { wanted.contains($0.id.uuidString) })
  }

  public func suggestedEntities() async throws -> [ApprovalEntity] {
    try await materialize(include: { _ in true })
  }

  public func entities(matching string: String) async throws -> [ApprovalEntity] {
    let query = IntentsKitSupport.normalizedQuery(string)
    return try await materialize(include: { approval, hostName in
      guard !query.isEmpty else { return true }
      let summary = IntentsKitSupport.approvalActionSummary(approval)
      return IntentsKitSupport.matchesFuzzy(summary, query: query)
        || IntentsKitSupport.matchesFuzzy(hostName, query: query)
        || IntentsKitSupport.matchesFuzzy(IntentsKitSupport.riskLabel(approval.risk), query: query)
    })
  }

  private func materialize(
    include: @escaping (Approval, String) -> Bool
  ) async throws -> [ApprovalEntity] {
    let db = try IntentsKitDependencies.database()
    let pending = try await ApprovalRepository(db).pending()
    var entities: [ApprovalEntity] = []
    for approval in pending {
      let host = try await IntentsKitSupport.hostIdentity(for: approval, db: db)
      guard include(approval, host.name) else { continue }
      entities.append(ApprovalEntity(approval: approval, hostName: host.name, hostID: host.id))
    }
    return entities
  }

  private func materialize(
    include: @escaping (Approval) -> Bool
  ) async throws -> [ApprovalEntity] {
    try await materialize { approval, _ in include(approval) }
  }
}

/// "Deny the latest approval" (the pre-D2 phrase, kept working for users' existing
/// habit) names no `ApprovalEntity` — resolves to the most recent pending one.
/// `suggestedEntities()` mirrors `ApprovalRepository.pending()`'s
/// `ORDER BY createdAt DESC`, so the first entry here is always the newest.
@available(iOS 17.0, *)
public enum ApprovalResolution: Sendable {
  case none
  case mostRecent(ApprovalEntity)
}

@available(iOS 17.0, *)
extension ApprovalEntityQuery {
  public func resolveMostRecentPending() async throws -> ApprovalResolution {
    let pending = try await suggestedEntities()
    guard let first = pending.first else { return .none }
    return .mostRecent(first)
  }
}

#endif
