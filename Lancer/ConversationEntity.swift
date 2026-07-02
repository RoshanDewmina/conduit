import AppIntents
import Foundation
import LancerCore
import PersistenceKit

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// Wraps a persisted `ChatConversation`. `IndexedEntity`, not volatile: chat
/// threads already live durably in GRDB (`ChatConversationRepository`) and are
/// exactly the kind of long-lived, user-recognizable object Spotlight/Siri
/// "find my conversation about X" is built for — the same
/// `ChatConversationRepository.search` full-text index already used by
/// in-app search. No existing Siri intent needs conversation disambiguation
/// yet; this is forward groundwork, not a fix for a live bug.
@available(iOS 18.0, *)
public struct ConversationEntity: IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Conversation")
    public static let defaultQuery = ConversationEntityQuery()

    public let id: String
    let title: String
    let hostName: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(hostName)")
    }

    init(conversation: ChatConversation) {
        self.id = conversation.id
        self.title = conversation.title
        self.hostName = conversation.hostName
    }
}

@available(iOS 18.0, *)
public struct ConversationEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [ConversationEntity] {
        guard let db = try? AppDatabase.openShared() else { return [] }
        let repo = ChatConversationRepository(db)
        var results: [ConversationEntity] = []
        for id in identifiers {
            guard let conversation = try? await repo.conversation(id: id) else { continue }
            results.append(ConversationEntity(conversation: conversation))
        }
        return results
    }

    public func entities(matching string: String) async throws -> [ConversationEntity] {
        guard let db = try? AppDatabase.openShared(),
              let results = try? await ChatConversationRepository(db).search(string)
        else { return [] }
        return results.map { ConversationEntity(conversation: $0.conversation) }
    }

    public func suggestedEntities() async throws -> [ConversationEntity] {
        guard let db = try? AppDatabase.openShared(),
              let recent = try? await ChatConversationRepository(db).recent(limit: 10)
        else { return [] }
        return recent.map(ConversationEntity.init)
    }
}
