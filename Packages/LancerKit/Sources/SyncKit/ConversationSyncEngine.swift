import Foundation
import LancerCore
import PersistenceKit
import NotificationsKit

#if os(iOS)
import CloudKit
#endif

/// Bidirectional CloudKit mirror for the host-owned conversation ledger's
/// already-mirrored rows (Task 8). Deliberately a separate actor from
/// `SyncEngine` (Hosts/Snippets) per the build handoff: different zone
/// (`LancerConversations`, not the default zone), different conflict
/// semantics, and a much larger, append-mostly data volume.
///
/// The host ledger — not CloudKit — remains the execution source of truth.
/// This engine only mirrors rows this device (or another of the user's
/// devices) has already confirmed with the host, so a fresh device can
/// restore conversation history from iCloud before it next talks to a host.
/// It never originates a turn or drives dispatch.
public actor ConversationSyncEngine {
    public static let zoneName = "LancerConversations"
    /// Stable across launches/upserts — `CKModifySubscriptionsOperation` treats a
    /// re-save of the same ID as an update, and the AppDelegate-delivered
    /// `CKNotification.subscriptionID` must match this to be routed here.
    public static let backgroundSubscriptionID = "lancer.conversationSync.dbSubscription"
    private static let changeTokenDefaultsKey = "lancer.cloudsync.conversationZoneToken"

    private let cloudSync: CloudSync
    private let chatRepo: ChatConversationRepository
    private let defaults: UserDefaults
    private var zoneReady = false

    public private(set) var lastSyncDate: Date?
    public private(set) var syncError: String?
    public private(set) var isSyncing: Bool = false

    private var notificationTask: Task<Void, Never>?
    private var remotePushTask: Task<Void, Never>?

    public init(
        cloudSync: CloudSync,
        chatRepo: ChatConversationRepository,
        defaults: UserDefaults = .standard
    ) {
        self.cloudSync = cloudSync
        self.chatRepo = chatRepo
        self.defaults = defaults
    }

    /// Starts the engine and registers for CloudKit account change
    /// notifications, matching `SyncEngine.start()`.
    public func start() async {
        let status = try? await cloudSync.accountStatus()
        guard status == .available else { return }

        await performSync()
        // Best-effort: a build without the full CloudKit entitlement (or a
        // sandboxed/dev profile) may reject subscription creation even though
        // record read/write still works. Don't let that block startup — it
        // just means this device falls back to foreground/pull-to-refresh
        // sync, the pre-existing behavior.
        try? await cloudSync.ensureDatabaseSubscriptionExists(subscriptionID: Self.backgroundSubscriptionID)

        #if os(iOS)
        notificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                await self?.performSync()
            }
        }
        remotePushTask = Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: .lancerCloudKitRemoteNotification) {
                // Parse here, outside actor isolation, and cross the boundary
                // with only a Sendable String — `note.userInfo` is
                // `[AnyHashable: Any]?`, which Swift 6 strict concurrency
                // correctly refuses to hand to an actor-isolated method.
                guard let userInfo = note.userInfo,
                      let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) else { continue }
                await self?.handleRemoteNotification(subscriptionID: ckNotification.subscriptionID)
            }
        }
        #endif
    }

    public func stop() {
        notificationTask?.cancel()
        notificationTask = nil
        remotePushTask?.cancel()
        remotePushTask = nil
    }

    /// Confirms a background remote-notification belongs to this engine's
    /// subscription (not some other push type routed onto the same
    /// NotificationCenter name) before triggering an out-of-cycle sync.
    /// Takes the already-parsed `CKNotification.subscriptionID` rather than
    /// the raw `userInfo` dictionary so callers can parse the `CKNotification`
    /// in a non-isolated context first — `[AnyHashable: Any]` isn't Sendable,
    /// so handing it directly to an actor-isolated method trips Swift 6
    /// strict concurrency's region-isolation check.
    @discardableResult
    public func handleRemoteNotification(subscriptionID: String?) async -> Bool {
        guard subscriptionID == Self.backgroundSubscriptionID else { return false }
        await performSync()
        return true
    }

    /// Manually triggers a sync cycle — used by "Sync now" in Settings and
    /// by `ConversationSyncCoordinator` after a `cloudStale` refresh.
    public func syncNow() async throws {
        await performSync()
    }

    // MARK: - Core sync cycle

    private func performSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await cloudSync.ensureZoneExists(zoneName: Self.zoneName)
            try await pull()
            try await push()
            lastSyncDate = .now
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Pull (CloudKit → local mirror)

    private func pull() async throws {
        let previousToken = defaults.data(forKey: Self.changeTokenDefaultsKey)
        let (records, deletedNames, newToken) = try await cloudSync.fetchZoneChanges(
            zoneName: Self.zoneName, previousChangeToken: previousToken
        )

        for wrapper in records {
            switch wrapper.recordType {
            case ConversationRecordType.conversation:
                try await mergeConversation(wrapper)
            case ConversationRecordType.turnChunk:
                try await mergeTurnChunk(wrapper)
            default:
                continue
            }
        }

        // Conversation records are only ever hard-deleted by out-of-band
        // action (e.g. the CloudKit dashboard); treat that as an archive so
        // any already-mirrored turns/events survive.
        for name in deletedNames {
            try await chatRepo.applyCloudArchive(conversationID: name)
        }

        if let newToken {
            defaults.set(newToken, forKey: Self.changeTokenDefaultsKey)
        }
    }

    private func mergeConversation(_ wrapper: CKRecordWrapper) async throws {
        guard let incoming = ConversationCloudRecords.conversation(from: wrapper) else { return }
        let remoteDate = wrapper.modificationDate ?? incoming.updatedAt
        let local = try await chatRepo.conversation(id: incoming.id)

        if let local, remoteDate <= local.updatedAt {
            // Local is same age or newer (often this device's own last
            // push echoing back) — the next push cycle will (re)send it.
            return
        }

        var merged = incoming
        merged.updatedAt = remoteDate
        let mergedSeq = max(local?.lastHostSeq ?? 0, incoming.lastHostSeq)
        _ = try await chatRepo.upsertConversationMirror(
            merged, lastHostSeq: mergedSeq, syncState: local?.syncState ?? .synced
        )
        try await chatRepo.markCloudUploaded(conversationID: incoming.id, recordName: wrapper.recordName, modifiedAt: remoteDate)
    }

    private func mergeTurnChunk(_ wrapper: CKRecordWrapper) async throws {
        guard let decoded = try ConversationCloudRecords.turnChunk(from: wrapper) else { return }
        try await chatRepo.appendEventsMirror(conversationID: decoded.turn.conversationID, events: decoded.events)
        _ = try await chatRepo.upsertTurnMirror(
            decoded.turn,
            vendorSessionID: decoded.turn.vendorSessionID,
            hostSeqStart: decoded.turn.hostSeqStart,
            hostSeqEnd: decoded.turn.hostSeqEnd
        )
        // Turn chunks are immutable, so mark this device's copy uploaded
        // too — otherwise the push cycle would try to re-upload a chunk it
        // just pulled from another device.
        try await chatRepo.markTurnCloudUploaded(turnID: decoded.turn.id, recordName: wrapper.recordName)
    }

    // MARK: - Push (local mirror → CloudKit)

    private func push() async throws {
        let candidates = try await chatRepo.conversationsNeedingCloudPush()
        for conversation in candidates {
            try await pushConversation(conversation)
            try await pushTurns(conversationID: conversation.id)
        }
    }

    private func pushConversation(_ conversation: ChatConversation) async throws {
        let wrapper = ConversationCloudRecords.conversationRecord(from: conversation, zoneName: Self.zoneName)
        try await cloudSync.save(records: [wrapper])
        try await chatRepo.markCloudUploaded(conversationID: conversation.id, recordName: wrapper.recordName, modifiedAt: conversation.updatedAt)
    }

    private func pushTurns(conversationID: String) async throws {
        let turns = try await chatRepo.turnsNeedingCloudPush(conversationID: conversationID)
        guard !turns.isEmpty else { return }
        let allEvents = try await chatRepo.events(conversationID: conversationID, sinceSeq: 0, limit: 10_000)
        let eventsByTurn = Dictionary(grouping: allEvents, by: { $0.turnID })

        for turn in turns {
            let events = eventsByTurn[turn.id] ?? []
            let wrapper = try ConversationCloudRecords.turnChunkRecord(turn: turn, events: events, zoneName: Self.zoneName)
            try await cloudSync.save(records: [wrapper])
            try await chatRepo.markTurnCloudUploaded(turnID: turn.id, recordName: wrapper.recordName)
        }
    }
}
