import Foundation
import LancerCore

#if os(iOS)
import CloudKit
#endif

/// CloudKit record types backing the conversation mirror (Task 8), all
/// living in the `LancerConversations` custom zone — see
/// `ConversationSyncEngine`.
public enum ConversationRecordType {
    /// One record per `ChatConversation`, mutable metadata, last-write-wins
    /// (mirrors the `SyncEngine` Host/Snippet pattern).
    public static let conversation = "Conversation"
    /// One record per finished turn plus its full event transcript.
    /// Immutable once created — see `ChatConversationRepository
    /// .turnsNeedingCloudPush`/`.markTurnCloudUploaded`.
    public static let turnChunk = "ConversationTurnChunk"
}

/// A turn plus its full event transcript, chunked into one immutable
/// CloudKit record per turn. Encoded directly as JSON since `ChatTurn`/
/// `ChatEvent` are already `Codable` — no separate wire-shape needed.
public struct ConversationTurnChunkPayload: Codable, Sendable {
    public var turn: ChatTurn
    public var events: [ChatEvent]

    public init(turn: ChatTurn, events: [ChatEvent]) {
        self.turn = turn
        self.events = events
    }
}

/// JSON payload above this size is written to a `CKAsset` file instead of an
/// inline `String` field, keeping individual records comfortably under
/// CloudKit's ~1 MB record-size ceiling (handoff §CloudKit Private Mirror).
private let inlinePayloadLimit = 200 * 1024

/// Maps between `ChatConversation`/`ConversationTurnChunkPayload` and
/// CloudKit records. All methods are cross-platform no-ops off iOS, matching
/// `SyncEngine`'s `hostFrom(wrapper:)` / `snippetFrom(wrapper:)` convention.
public enum ConversationCloudRecords {
    // MARK: - Conversation (mutable metadata, last-write-wins)

    public static func conversationRecord(from conversation: ChatConversation, zoneName: String) -> CKRecordWrapper {
        #if os(iOS)
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: conversation.id, zoneID: zoneID)
        let record = CKRecord(recordType: ConversationRecordType.conversation, recordID: recordID)
        record["title"]          = conversation.title as CKRecordValue
        record["agentID"]        = conversation.agentID as CKRecordValue
        record["hostName"]       = conversation.hostName as CKRecordValue
        record["cwd"]            = conversation.cwd as CKRecordValue
        record["status"]         = conversation.status.rawValue as CKRecordValue
        record["createdAt"]      = conversation.createdAt as CKRecordValue
        record["updatedAt"]      = conversation.updatedAt as CKRecordValue
        record["lastActivityAt"] = conversation.lastActivityAt as CKRecordValue
        record["lastHostSeq"]    = conversation.lastHostSeq as CKRecordValue
        if let v = conversation.vendor         { record["vendor"] = v as CKRecordValue }
        if let v = conversation.hostID         { record["hostID"] = v as CKRecordValue }
        if let v = conversation.model          { record["model"] = v as CKRecordValue }
        if let v = conversation.budgetUSD      { record["budgetUSD"] = v as CKRecordValue }
        if let v = conversation.sourceHostID   { record["sourceHostID"] = v as CKRecordValue }
        if let v = conversation.sourceHostName { record["sourceHostName"] = v as CKRecordValue }
        if let v = conversation.archivedAt     { record["archivedAt"] = v as CKRecordValue }
        return CKRecordWrapper(record: record)
        #else
        return CKRecordWrapper()
        #endif
    }

    /// Decodes a `Conversation` record into a `ChatConversation`. Always
    /// returns `syncState: .synced` — the caller (`ConversationSyncEngine`)
    /// is responsible for reconciling that against any existing local state
    /// (e.g. a pending conflict) before writing to the mirror.
    public static func conversation(from wrapper: CKRecordWrapper) -> ChatConversation? {
        #if os(iOS)
        guard let title = wrapper["title"] as? String,
              let agentID = wrapper["agentID"] as? String,
              let hostName = wrapper["hostName"] as? String,
              let cwd = wrapper["cwd"] as? String,
              let statusRaw = wrapper["status"] as? String,
              let status = ChatConversation.Status(rawValue: statusRaw),
              let createdAt = wrapper["createdAt"] as? Date,
              let updatedAt = wrapper["updatedAt"] as? Date
        else { return nil }

        let lastHostSeq: Int
        if let v = wrapper["lastHostSeq"] as? Int            { lastHostSeq = v }
        else if let v = wrapper["lastHostSeq"] as? Int64     { lastHostSeq = Int(v) }
        else if let v = wrapper["lastHostSeq"] as? NSNumber  { lastHostSeq = v.intValue }
        else { lastHostSeq = 0 }

        return ChatConversation(
            id: wrapper.recordName,
            title: title, agentID: agentID, vendor: wrapper["vendor"] as? String,
            hostName: hostName, hostID: wrapper["hostID"] as? String, cwd: cwd,
            model: wrapper["model"] as? String, budgetUSD: wrapper["budgetUSD"] as? Double,
            status: status, createdAt: createdAt, updatedAt: updatedAt,
            lastActivityAt: wrapper["lastActivityAt"] as? Date ?? updatedAt,
            sourceHostID: wrapper["sourceHostID"] as? String,
            sourceHostName: wrapper["sourceHostName"] as? String,
            lastHostSeq: lastHostSeq,
            syncState: .synced,
            archivedAt: wrapper["archivedAt"] as? Date
        )
        #else
        return nil
        #endif
    }

    // MARK: - Turn chunk (immutable, created once per finished turn)

    public static func turnChunkRecord(turn: ChatTurn, events: [ChatEvent], zoneName: String) throws -> CKRecordWrapper {
        #if os(iOS)
        let payload = ConversationTurnChunkPayload(turn: turn, events: events)
        let data = try Self.encoder.encode(payload)

        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: turn.id, zoneID: zoneID)
        let record = CKRecord(recordType: ConversationRecordType.turnChunk, recordID: recordID)
        record["conversationID"] = turn.conversationID as CKRecordValue
        record["ordinal"]        = turn.ordinal as CKRecordValue
        record["createdAt"]      = turn.createdAt as CKRecordValue
        if let start = turn.hostSeqStart { record["hostSeqStart"] = start as CKRecordValue }
        if let end = turn.hostSeqEnd     { record["hostSeqEnd"] = end as CKRecordValue }

        if data.count <= inlinePayloadLimit, let json = String(data: data, encoding: .utf8) {
            record["payload"] = json as CKRecordValue
        } else {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(turn.id)-chunk.json")
            try data.write(to: url, options: .atomic)
            record["payloadAsset"] = CKAsset(fileURL: url)
        }
        return CKRecordWrapper(record: record)
        #else
        return CKRecordWrapper()
        #endif
    }

    public static func turnChunk(from wrapper: CKRecordWrapper) throws -> ConversationTurnChunkPayload? {
        #if os(iOS)
        let data: Data
        if let json = wrapper["payload"] as? String {
            data = Data(json.utf8)
        } else if let asset = wrapper["payloadAsset"] as? CKAsset, let url = asset.fileURL {
            data = try Data(contentsOf: url)
        } else {
            return nil
        }
        return try Self.decoder.decode(ConversationTurnChunkPayload.self, from: data)
        #else
        return nil
        #endif
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
