import Foundation
import ConduitCore
import PersistenceKit

#if os(iOS)
import CloudKit
#endif

/// Last-write-wins CloudKit sync for hosts and snippets.
/// SSH private key material is never synced — only metadata.
public actor SyncEngine {
    private let cloudSync: CloudSync
    private let hostRepo: HostRepository
    private let snippetRepo: SnippetRepository

    public private(set) var lastSyncDate: Date?
    public private(set) var conflictCount: Int = 0
    public private(set) var syncError: String?

    private var notificationTask: Task<Void, Never>?

    public init(cloudSync: CloudSync, hostRepo: HostRepository, snippetRepo: SnippetRepository) {
        self.cloudSync = cloudSync
        self.hostRepo = hostRepo
        self.snippetRepo = snippetRepo
    }

    /// Starts the sync engine. Registers for CloudKit change notifications.
    public func start() async {
        let status = try? await cloudSync.accountStatus()
        // #region agent log
        #if os(iOS) && !targetEnvironment(simulator)
        CloudSync.debugLogSyncStart(status: String(describing: status))
        #endif
        // #endregion
        guard status == .available else { return }

        // Initial sync
        await performSync()

        // Listen for CloudKit account change notifications
        #if os(iOS)
        notificationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                await self?.performSync()
            }
        }
        #endif
    }

    public func stop() {
        notificationTask?.cancel()
        notificationTask = nil
    }

    /// Manually triggers a sync cycle.
    public func syncNow() async throws {
        await performSync()
    }

    // MARK: - Private sync logic

    private func performSync() async {
        do {
            try await pushHosts()
            try await pushSnippets()
            lastSyncDate = .now
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func pushHosts() async throws {
        #if os(iOS)
        let hosts = try await hostRepo.all()
        let records: [CKRecordWrapper] = hosts.map { host in
            let recordID = CKRecord.ID(recordName: host.id.uuidString)
            let record = CKRecord(recordType: "Host", recordID: recordID)
            record["name"]     = host.name as CKRecordValue
            record["hostname"] = host.hostname as CKRecordValue
            record["port"]     = host.port as CKRecordValue
            record["username"] = host.username as CKRecordValue
            // SSH key material is device-local — not synced
            record["updatedAt"] = (host.lastConnectedAt ?? host.createdAt) as CKRecordValue
            return CKRecordWrapper(record: record)
        }
        try await cloudSync.save(records: records)
        #endif
    }

    private func pushSnippets() async throws {
        #if os(iOS)
        let snippets = try await snippetRepo.all()
        let records: [CKRecordWrapper] = snippets.map { snippet in
            let recordID = CKRecord.ID(recordName: snippet.id.uuidString)
            let record = CKRecord(recordType: "Snippet", recordID: recordID)
            record["name"]      = snippet.name as CKRecordValue
            record["body"]      = snippet.body as CKRecordValue
            record["updatedAt"] = (snippet.lastUsedAt ?? snippet.createdAt) as CKRecordValue
            return CKRecordWrapper(record: record)
        }
        try await cloudSync.save(records: records)
        #endif
    }
}
