#if canImport(AppIntents)
import AppIntents
import Foundation
import LancerCore
import PersistenceKit

@available(iOS 17.0, *)
public struct ConversationEntity: AppEntity, Identifiable, Sendable {
  public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Conversation")
  public static let defaultQuery = ConversationEntityQuery()

  public let id: String
  public let title: String
  public let hostName: String

  public var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(title)")
  }

  init(conversation: ChatConversation) {
    id = conversation.id
    title = conversation.title
    hostName = conversation.hostName
  }
}

@available(iOS 17.0, *)
public struct ConversationEntityQuery: EntityQuery, EntityStringQuery {
  public init() {}

  public func entities(for identifiers: [ConversationEntity.ID]) async throws -> [ConversationEntity] {
    let db = try IntentsKitDependencies.database()
    let repo = ChatConversationRepository(db)
    var resolved: [ConversationEntity] = []
    for identifier in identifiers {
      if let conversation = try await repo.conversation(id: identifier) {
        resolved.append(ConversationEntity(conversation: conversation))
      }
    }
    return resolved
  }

  public func suggestedEntities() async throws -> [ConversationEntity] {
    let db = try IntentsKitDependencies.database()
    let conversations = try await ChatConversationRepository(db).recent(limit: 25)
    return conversations.map(ConversationEntity.init)
  }

  public func entities(matching string: String) async throws -> [ConversationEntity] {
    let db = try IntentsKitDependencies.database()
    let results = try await ChatConversationRepository(db).search(string, limit: 25)
    return results.map { ConversationEntity(conversation: $0.conversation) }
  }
}

#endif
