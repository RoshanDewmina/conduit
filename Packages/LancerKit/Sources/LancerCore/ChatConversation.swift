import Foundation

public struct ChatConversation: Codable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var agentID: String
    public var vendor: String?
    public var hostName: String
    public var hostID: String?
    public var cwd: String
    public var model: String?
    public var budgetUSD: Double?
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date
    public var lastActivityAt: Date
    /// Host identity this conversation's ledger row lives on — distinct from
    /// `hostID`/`hostName` above (the SSH-paired host record) because a
    /// conversation created via relay may not have one. `nil` for
    /// conversations that predate cross-device sync (Task 6) or were never
    /// bound to a host-owned ledger row (local-only chats).
    public var sourceHostID: String?
    public var sourceHostName: String?
    /// The highest `conversation_events.seq` this device has mirrored from
    /// the host ledger. Drives incremental `agent.conversations.fetch(sinceSeq:)`
    /// paging and lets the UI detect when another device has moved the
    /// conversation past what's shown locally.
    public var lastHostSeq: Int
    public var syncState: SyncState
    /// CloudKit private-database record name for this conversation's
    /// `Conversation` record (Task 8), once pushed at least once.
    public var cloudRecordName: String?
    public var cloudUploadedAt: Date?
    public var cloudModifiedAt: Date?
    public var archivedAt: Date?

    public enum Status: String, Codable, Sendable {
        case active
        case completed
        case failed
        case archived
    }

    /// Where this device's copy of a conversation stands relative to the
    /// host ledger (execution truth) and CloudKit (Apple-device mirror).
    public enum SyncState: String, Codable, Sendable {
        /// Never bound to a host ledger row — a pre-sync legacy conversation,
        /// or a brand-new local draft not yet sent.
        case localOnly
        /// A host-mediated append/fetch is currently in flight.
        case syncing
        /// This device's mirror matches the host's last known `lastSeq`.
        case synced
        /// The host rejected an append because `baseSeq` was stale — another
        /// device (or another turn on this one) moved the conversation
        /// forward first. Resolved by refetching before the next send.
        case conflict
        /// The host that owns this conversation's ledger could not be
        /// reached on the last attempt. Cached history is still shown;
        /// sending is disabled or the composer keeps an explicit draft.
        case hostOffline

        public var isRecoverable: Bool { self == .conflict || self == .hostOffline }
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        agentID: String,
        vendor: String? = nil,
        hostName: String,
        hostID: String? = nil,
        cwd: String,
        model: String? = nil,
        budgetUSD: Double? = nil,
        status: Status = .active,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastActivityAt: Date = .now,
        sourceHostID: String? = nil,
        sourceHostName: String? = nil,
        lastHostSeq: Int = 0,
        syncState: SyncState = .localOnly,
        cloudRecordName: String? = nil,
        cloudUploadedAt: Date? = nil,
        cloudModifiedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.agentID = agentID
        self.vendor = vendor
        self.hostName = hostName
        self.hostID = hostID
        self.cwd = cwd
        self.model = model
        self.budgetUSD = budgetUSD
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
        self.sourceHostID = sourceHostID
        self.sourceHostName = sourceHostName
        self.lastHostSeq = lastHostSeq
        self.syncState = syncState
        self.cloudRecordName = cloudRecordName
        self.cloudUploadedAt = cloudUploadedAt
        self.cloudModifiedAt = cloudModifiedAt
        self.archivedAt = archivedAt
    }
}

public struct ChatTurn: Codable, Sendable, Identifiable {
    public let id: String
    public let conversationID: String
    public let ordinal: Int
    public let prompt: String
    public let runID: String
    public let transportKind: String
    public var status: Status
    public var assistantText: String
    public var errorMessage: String?
    public var createdAt: Date
    public var completedAt: Date?
    /// The idempotency key the originating device minted for this turn
    /// (`device-id:local-counter`, per the build handoff). Lets a replayed
    /// append (e.g. after a dropped response) map back to the same turn
    /// instead of creating a duplicate.
    public var clientTurnID: String?
    /// The exact vendor CLI session/thread id this turn's process bound, if
    /// any. Present once the host has captured it from the CLI's structured
    /// output — see conversation_store.go's `bindVendorSession`.
    public var vendorSessionID: String?
    /// This turn's event range in the host ledger's per-conversation
    /// sequence space, once known.
    public var hostSeqStart: Int?
    public var hostSeqEnd: Int?
    public var cloudRecordName: String?

    public enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    public init(
        id: String = UUID().uuidString,
        conversationID: String,
        ordinal: Int,
        prompt: String,
        runID: String,
        transportKind: String = "ssh",
        status: Status = .running,
        assistantText: String = "",
        errorMessage: String? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        clientTurnID: String? = nil,
        vendorSessionID: String? = nil,
        hostSeqStart: Int? = nil,
        hostSeqEnd: Int? = nil,
        cloudRecordName: String? = nil
    ) {
        self.id = id
        self.conversationID = conversationID
        self.ordinal = ordinal
        self.prompt = prompt
        self.runID = runID
        self.transportKind = transportKind
        self.status = status
        self.assistantText = assistantText
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.clientTurnID = clientTurnID
        self.vendorSessionID = vendorSessionID
        self.hostSeqStart = hostSeqStart
        self.hostSeqEnd = hostSeqEnd
        self.cloudRecordName = cloudRecordName
    }
}

/// One immutable event in a host conversation's append-only transcript log
/// (`conversation_events` on the daemon ledger). Mirrored locally so a device
/// that reopens a conversation mid-stream, or after being offline, can render
/// exactly what the host recorded rather than only what it personally
/// streamed live. Ordered and deduplicated by `(conversationID, seq)`.
public struct ChatEvent: Codable, Sendable, Hashable {
    public let conversationID: String
    public let seq: Int
    public let turnID: String?
    public let runID: String?
    public let kind: String
    public let role: String?
    public let stream: String?
    public let text: String?
    public let payloadJSON: String?
    public let createdAt: Date

    public init(
        conversationID: String,
        seq: Int,
        turnID: String? = nil,
        runID: String? = nil,
        kind: String,
        role: String? = nil,
        stream: String? = nil,
        text: String? = nil,
        payloadJSON: String? = nil,
        createdAt: Date = .now
    ) {
        self.conversationID = conversationID
        self.seq = seq
        self.turnID = turnID
        self.runID = runID
        self.kind = kind
        self.role = role
        self.stream = stream
        self.text = text
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

/// An unsent prompt saved locally because the host was unreachable when the
/// user tried to send it. Per the build handoff's non-negotiable #5, this is
/// never auto-sent on reconnect — the user must explicitly tap Send again.
/// One draft per conversation; saving a new draft overwrites the prior one.
public struct ChatDraft: Codable, Sendable, Equatable {
    public let conversationID: String
    public var text: String
    public var savedAt: Date

    public init(conversationID: String, text: String, savedAt: Date = .now) {
        self.conversationID = conversationID
        self.text = text
        self.savedAt = savedAt
    }
}

public struct ChatArtifact: Codable, Sendable, Identifiable {
    public let id: String
    public let conversationID: String
    public let turnID: String
    public let runID: String
    public let kind: Kind
    public var title: String
    public var summary: String?
    public var payloadJSON: String
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date

    public enum Kind: String, Codable, Sendable {
        case tool
        case diff
        case file
        case test
        case preview
        case approval
        case receipt
        case question
    }

    public enum Status: String, Codable, Sendable {
        case running
        case done
        case failed
    }

    public init(
        id: String = UUID().uuidString,
        conversationID: String,
        turnID: String,
        runID: String,
        kind: Kind,
        title: String,
        summary: String? = nil,
        payloadJSON: String = "{}",
        status: Status = .running,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.conversationID = conversationID
        self.turnID = turnID
        self.runID = runID
        self.kind = kind
        self.title = title
        self.summary = summary
        self.payloadJSON = payloadJSON
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ChatConversationSearchResult: Sendable, Identifiable {
    public let conversation: ChatConversation
    public let snippet: String
    public var id: String { conversation.id }

    public init(conversation: ChatConversation, snippet: String) {
        self.conversation = conversation
        self.snippet = snippet
    }
}
