#if canImport(AppIntents)
import AppIntents
import Foundation
import LancerCore
import PersistenceKit

@available(iOS 17.0, *)
public struct RunEntity: AppEntity, Identifiable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Agent Run")
  public static let defaultQuery = RunEntityQuery()

  public let id: String
  public let title: String

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)")
  }

  init(runID: String, title: String) {
    id = runID
    self.title = title
  }
}

@available(iOS 17.0, *)
public struct RunEntityQuery: EntityQuery, EntityStringQuery {
  public init() {}

  public func entities(for identifiers: [RunEntity.ID]) async throws -> [RunEntity] {
    let wanted = Set(identifiers)
    return try await materialize(include: { wanted.contains($0.id) })
  }

  public func suggestedEntities() async throws -> [RunEntity] {
    try await materialize(include: { _ in true })
  }

  public func entities(matching string: String) async throws -> [RunEntity] {
    let query = IntentsKitSupport.normalizedQuery(string)
    return try await materialize(include: { entity in
      guard !query.isEmpty else { return true }
      return IntentsKitSupport.matchesFuzzy(entity.title, query: query)
        || IntentsKitSupport.matchesFuzzy(entity.id, query: query)
    })
  }

  private func materialize(
    include: (RunEntity) -> Bool
  ) async throws -> [RunEntity] {
    let db = try IntentsKitDependencies.database()
    let chatRepo = ChatConversationRepository(db)
    let runIDs = IntentsKitDependencies.activeRunIDs()
    var entities: [RunEntity] = []
    for runID in runIDs {
      let title: String
      if let turn = try await chatRepo.turnByRunID(runID) {
        let prompt = turn.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        title = prompt.isEmpty ? runID : prompt
      } else {
        title = runID
      }
      let entity = RunEntity(runID: runID, title: title)
      if include(entity) {
        entities.append(entity)
      }
    }
    return entities
  }
}
#endif
