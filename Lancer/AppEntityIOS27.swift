// iOS 27 fast-follow — IndexedEntity, IndexedEntityQuery, SyncableEntity.
// App deployment target stays iOS 26; these APIs are availability-gated.

import AppIntents
import CoreSpotlight
import Foundation
import PersistenceKit

// MARK: - IndexedEntity (iOS 18+, used from iOS 27 indexing lane)

@available(iOS 18.0, *)
extension ConversationEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let fields = IntentEntitySpotlightSupport.ConversationIndexFields(
            IntentConversationRecord(
                id: id,
                title: title,
                hostName: hostName,
                workspacePath: "/\(title)",
                vendor: nil,
                lastActivityAt: .now
            )
        )
        let set = CSSearchableItemAttributeSet(contentType: .content)
        set.title = fields.title
        set.contentDescription = "\(fields.hostName) · \(fields.workspaceFolderName)"
        set.domainIdentifier = IntentEntitySpotlightSupport.spotlightDomain
        return set
    }
}

@available(iOS 18.0, *)
extension MachineEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .content)
        set.title = displayName
        set.contentDescription = connectivityLabel
        set.domainIdentifier = IntentEntitySpotlightSupport.spotlightDomain
        return set
    }
}

@available(iOS 18.0, *)
extension WorkspaceEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let folder = URL(fileURLWithPath: path).lastPathComponent
        let set = CSSearchableItemAttributeSet(contentType: .content)
        set.title = name
        set.contentDescription = folder
        set.domainIdentifier = IntentEntitySpotlightSupport.spotlightDomain
        return set
    }
}

@available(iOS 18.0, *)
extension RunEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .content)
        set.title = title
        set.contentDescription = subtitle
        set.domainIdentifier = IntentEntitySpotlightSupport.spotlightDomain
        return set
    }
}

@available(iOS 18.0, *)
extension ApprovalEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .content)
        set.title = headline
        set.contentDescription = riskLabel
        set.domainIdentifier = IntentEntitySpotlightSupport.spotlightDomain
        return set
    }
}

// MARK: - IndexedEntity builders from catalog records

@available(iOS 18.0, *)
enum SiriIndexedEntityFactory {
    static func conversation(_ record: IntentConversationRecord) -> ConversationEntity {
        ConversationEntity(record)
    }

    static func machine(_ record: IntentMachineRecord) -> MachineEntity {
        MachineEntity(record)
    }

    static func workspace(_ record: IntentWorkspaceRecord) -> WorkspaceEntity {
        WorkspaceEntity(record)
    }

    static func run(_ record: IntentRunRecord) -> RunEntity {
        RunEntity(record)
    }

    static func approval(_ record: IntentApprovalRecord) -> ApprovalEntity {
        ApprovalEntity(record)
    }

    static func conversationAttributeSet(_ record: IntentConversationRecord) -> CSSearchableItemAttributeSet {
        let fields = IntentEntitySpotlightSupport.ConversationIndexFields(record)
        let set = CSSearchableItemAttributeSet(contentType: .content)
        set.title = fields.title
        var subtitle = fields.hostName
        if let vendor = fields.vendorLabel, !vendor.isEmpty {
            subtitle += " · \(vendor)"
        }
        subtitle += " · \(fields.workspaceFolderName)"
        set.contentDescription = subtitle
        set.domainIdentifier = IntentEntitySpotlightSupport.spotlightDomain
        return set
    }
}

// MARK: - IndexedEntityQuery (iOS 27+)

@available(iOS 27.0, *)
extension ConversationEntityQuery: IndexedEntityQuery {
    public func reindexEntities(
        for identifiers: [ConversationEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await SiriEntityIndexer.shared.index(conversations: entities)
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriEntityIndexer.shared.refreshConversations()
    }
}

@available(iOS 27.0, *)
extension MachineEntityQuery: IndexedEntityQuery {
    public func reindexEntities(
        for identifiers: [MachineEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await SiriEntityIndexer.shared.index(machines: entities)
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriEntityIndexer.shared.refreshMachines()
    }
}

@available(iOS 27.0, *)
extension WorkspaceEntityQuery: IndexedEntityQuery {
    public func reindexEntities(
        for identifiers: [WorkspaceEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await SiriEntityIndexer.shared.index(workspaces: entities)
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriEntityIndexer.shared.refreshWorkspaces()
    }
}

@available(iOS 27.0, *)
extension RunEntityQuery: IndexedEntityQuery {
    public func reindexEntities(
        for identifiers: [RunEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await SiriEntityIndexer.shared.index(runs: entities)
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriEntityIndexer.shared.refreshActiveRuns()
    }
}

@available(iOS 27.0, *)
extension ApprovalEntityQuery: IndexedEntityQuery {
    public func reindexEntities(
        for identifiers: [ApprovalEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await SiriEntityIndexer.shared.index(approvals: entities)
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await SiriEntityIndexer.shared.refreshPendingApprovals()
    }
}

// MARK: - SyncableEntity (iOS 27+)

@available(iOS 27.0, *)
extension MachineEntity: SyncableEntity {}

@available(iOS 27.0, *)
extension WorkspaceEntity: SyncableEntity {}

@available(iOS 27.0, *)
extension ConversationEntity: SyncableEntity {}
