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

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)")
  }

  init(approval: Approval, hostName: String) {
    id = approval.id.uuidString
    let summary = IntentsKitSupport.approvalActionSummary(approval)
    title = IntentsKitSupport.approvalDisplayTitle(
      actionSummary: summary,
      risk: approval.risk,
      hostName: hostName
    )
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
      let hostName = try await IntentsKitSupport.hostName(for: approval, db: db)
      guard include(approval, hostName) else { continue }
      entities.append(ApprovalEntity(approval: approval, hostName: hostName))
    }
    return entities
  }

  private func materialize(
    include: @escaping (Approval) -> Bool
  ) async throws -> [ApprovalEntity] {
    try await materialize { approval, _ in include(approval) }
  }
}

#endif
