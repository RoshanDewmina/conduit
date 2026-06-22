import Foundation
import LancerCore
import PersistenceKit
import SecurityKit

#if os(iOS)
import CloudKit
#endif

/// Bidirectional CloudKit sync for Hosts and Snippets.
///
/// Sync contract:
/// - Pull then push each cycle.
/// - Last-write-wins using CloudKit's modificationDate as the authoritative clock.
/// - Auth method is always device-local; never overwritten from a remote record.
/// - syncedKeyHint (SHA256 fingerprint) travels with the host so a new device can
///   identify which SSH key to import — no private key material ever leaves the device.
/// - Local deletions are recorded in sync_tombstones and propagated to CloudKit on push.
public actor SyncEngine {
    private let cloudSync: CloudSync
    private let hostRepo: HostRepository
    private let snippetRepo: SnippetRepository
    private let tombstoneRepo: SyncTombstoneRepository
    private let keyStore: KeyStore?

    public private(set) var lastSyncDate: Date?
    public private(set) var conflictCount: Int = 0
    public private(set) var syncError: String?
    public private(set) var isSyncing: Bool = false

    private var notificationTask: Task<Void, Never>?

    public init(
        cloudSync: CloudSync,
        hostRepo: HostRepository,
        snippetRepo: SnippetRepository,
        tombstoneRepo: SyncTombstoneRepository,
        keyStore: KeyStore? = nil
    ) {
        self.cloudSync = cloudSync
        self.hostRepo = hostRepo
        self.snippetRepo = snippetRepo
        self.tombstoneRepo = tombstoneRepo
        self.keyStore = keyStore
    }

    /// Starts the sync engine and registers for CloudKit account change notifications.
    public func start() async {
        let status = try? await cloudSync.accountStatus()
        guard status == .available else { return }

        await performSync()

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

    // MARK: - Core sync cycle

    private func performSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            // Pull first: merge remote into local before pushing.
            let hostConflicts = try await pullHosts()
            let snippetConflicts = try await pullSnippets()
            conflictCount += hostConflicts + snippetConflicts

            // Push: send merged local state + propagate local deletions.
            try await pushHosts()
            try await pushSnippets()

            lastSyncDate = .now
            syncError = nil
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Pull (CloudKit → local)

    private func pullHosts() async throws -> Int {
        #if os(iOS) && !targetEnvironment(simulator)
        let (records, deletedIDs) = try await cloudSync.fetchChanges(recordType: "Host")
        let localHosts = try await hostRepo.all()
        let localByID = Dictionary(uniqueKeysWithValues: localHosts.map { ($0.id.uuidString, $0) })

        var conflicts = 0
        for wrapper in records {
            guard let incoming = hostFrom(wrapper: wrapper) else { continue }
            let remoteDate = wrapper.modificationDate ?? incoming.createdAt

            if let local = localByID[incoming.id.uuidString] {
                if remoteDate > local.modifiedAt {
                    let merged = mergedHost(remote: incoming, local: local)
                    try await hostRepo.upsertSync(merged)
                    if hasMeaningfulDifference(local, incoming) { conflicts += 1 }
                }
                // else: local is same age or newer; push will send our version
            } else {
                // New host from remote; auth defaults to .password until user configures a key
                try await hostRepo.upsertSync(incoming)
            }
        }

        for idStr in deletedIDs {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            try await hostRepo.deleteFromSync(id: HostID(uuid))
        }
        return conflicts
        #else
        return 0
        #endif
    }

    private func pullSnippets() async throws -> Int {
        #if os(iOS) && !targetEnvironment(simulator)
        let (records, deletedIDs) = try await cloudSync.fetchChanges(recordType: "Snippet")
        let localSnippets = try await snippetRepo.all()
        let localByID = Dictionary(uniqueKeysWithValues: localSnippets.map { ($0.id.uuidString, $0) })

        var conflicts = 0
        for wrapper in records {
            guard let incoming = snippetFrom(wrapper: wrapper) else { continue }
            let remoteDate = wrapper.modificationDate ?? incoming.createdAt

            if let local = localByID[incoming.id.uuidString] {
                if remoteDate > local.modifiedAt {
                    try await snippetRepo.upsertSync(incoming)
                    if local.name != incoming.name || local.body != incoming.body { conflicts += 1 }
                }
            } else {
                try await snippetRepo.upsertSync(incoming)
            }
        }

        for idStr in deletedIDs {
            guard let uuid = UUID(uuidString: idStr) else { continue }
            try await snippetRepo.deleteFromSync(id: SnippetID(uuid))
        }
        return conflicts
        #else
        return 0
        #endif
    }

    // MARK: - Push (local → CloudKit)

    private func pushHosts() async throws {
        #if os(iOS) && !targetEnvironment(simulator)
        let hosts = try await hostRepo.all()
        var records: [CKRecordWrapper] = []
        for host in hosts {
            let recordID = CKRecord.ID(recordName: host.id.uuidString)
            let record = CKRecord(recordType: "Host", recordID: recordID)
            record["name"]      = host.name as CKRecordValue
            record["hostname"]  = host.hostname as CKRecordValue
            record["port"]      = host.port as CKRecordValue
            record["username"]  = host.username as CKRecordValue
            record["tags"]      = ((try? String(data: JSONEncoder().encode(host.tags), encoding: .utf8)) ?? "[]") as CKRecordValue
            record["autoResume"] = (host.autoResume ? 1 : 0) as CKRecordValue
            record["createdAt"] = host.createdAt as CKRecordValue
            record["updatedAt"] = host.modifiedAt as CKRecordValue
            if let v = host.hostKeyFingerprint { record["hostKeyFingerprint"] = v as CKRecordValue }
            if let v = host.preferredShell     { record["preferredShell"]     = v as CKRecordValue }
            if let v = host.tmuxSessionName    { record["tmuxSessionName"]    = v as CKRecordValue }
            if let v = host.startupCommand     { record["startupCommand"]     = v as CKRecordValue }

            // Key hint: resolve fresh fingerprint for ed25519; preserve any stored hint otherwise.
            let hint: String?
            if case .ed25519(let keyID) = host.authMethod {
                hint = (try? await keyStore?.publicKey(tag: keyID.uuidString))?.sha256Fingerprint
                    ?? host.syncedKeyHint
            } else {
                hint = host.syncedKeyHint
            }
            if let hint { record["syncedKeyHint"] = hint as CKRecordValue }

            records.append(CKRecordWrapper(record: record))
        }
        try await cloudSync.save(records: records)

        // Propagate local deletions.
        let toDelete = try await tombstoneRepo.pending(recordType: "Host")
        if !toDelete.isEmpty {
            try await cloudSync.delete(recordIDs: toDelete)
            try await tombstoneRepo.remove(ids: toDelete, recordType: "Host")
        }
        #endif
    }

    private func pushSnippets() async throws {
        #if os(iOS) && !targetEnvironment(simulator)
        let snippets = try await snippetRepo.all()
        let records: [CKRecordWrapper] = snippets.map { snippet in
            let recordID = CKRecord.ID(recordName: snippet.id.uuidString)
            let record = CKRecord(recordType: "Snippet", recordID: recordID)
            record["name"]      = snippet.name as CKRecordValue
            record["body"]      = snippet.body as CKRecordValue
            record["hostTags"]  = ((try? String(data: JSONEncoder().encode(snippet.hostTags), encoding: .utf8)) ?? "[]") as CKRecordValue
            record["tags"]      = ((try? String(data: JSONEncoder().encode(snippet.tags), encoding: .utf8)) ?? "[]") as CKRecordValue
            record["createdAt"] = snippet.createdAt as CKRecordValue
            record["updatedAt"] = snippet.modifiedAt as CKRecordValue
            return CKRecordWrapper(record: record)
        }
        try await cloudSync.save(records: records)

        let toDelete = try await tombstoneRepo.pending(recordType: "Snippet")
        if !toDelete.isEmpty {
            try await cloudSync.delete(recordIDs: toDelete)
            try await tombstoneRepo.remove(ids: toDelete, recordType: "Snippet")
        }
        #endif
    }

    // MARK: - Merge helpers

    /// Merge remote into local: take remote values for all metadata fields, but
    /// always preserve the device-local auth method. Prefer a non-nil syncedKeyHint
    /// from either side so the hint survives a round-trip through a device that
    /// hasn't configured a key.
    private func mergedHost(remote: LancerCore.Host, local: LancerCore.Host) -> LancerCore.Host {
        var merged = remote
        merged.authMethod = local.authMethod
        merged.syncedKeyHint = remote.syncedKeyHint ?? local.syncedKeyHint
        return merged
    }

    private func hasMeaningfulDifference(_ a: LancerCore.Host, _ b: LancerCore.Host) -> Bool {
        a.name != b.name || a.hostname != b.hostname || a.port != b.port || a.username != b.username
    }

    // MARK: - Record decoding

    private func hostFrom(wrapper: CKRecordWrapper) -> LancerCore.Host? {
        #if os(iOS)
        guard let uuid = UUID(uuidString: wrapper.recordName) else { return nil }
        guard let name     = wrapper["name"]     as? String,
              let hostname = wrapper["hostname"] as? String,
              let username = wrapper["username"] as? String
        else { return nil }

        let port: Int
        if let v = wrapper["port"] as? Int           { port = v }
        else if let v = wrapper["port"] as? Int64    { port = Int(v) }
        else if let v = wrapper["port"] as? NSNumber { port = v.intValue }
        else { port = 22 }

        let tagsJSON  = wrapper["tags"] as? String ?? "[]"
        let tags      = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
        let createdAt = wrapper["createdAt"] as? Date ?? Date()
        let modifiedAt = wrapper.modificationDate ?? wrapper["updatedAt"] as? Date ?? createdAt

        let autoResume: Bool
        if let v = wrapper["autoResume"] as? Int          { autoResume = v != 0 }
        else if let v = wrapper["autoResume"] as? Int64   { autoResume = v != 0 }
        else if let v = wrapper["autoResume"] as? NSNumber { autoResume = v.boolValue }
        else { autoResume = true }

        return LancerCore.Host(
            id: HostID(uuid),
            name: name,
            hostname: hostname,
            port: port,
            username: username,
            authMethod: .password,   // auth is always device-local; set by mergedHost if updating existing
            tags: tags,
            hostKeyFingerprint: wrapper["hostKeyFingerprint"] as? String,
            preferredShell:     wrapper["preferredShell"]     as? String,
            tmuxSessionName:    wrapper["tmuxSessionName"]    as? String,
            startupCommand:     wrapper["startupCommand"]     as? String,
            autoResume: autoResume,
            createdAt: createdAt,
            lastConnectedAt: nil,
            modifiedAt: modifiedAt,
            syncedKeyHint: wrapper["syncedKeyHint"] as? String
        )
        #else
        return nil
        #endif
    }

    private func snippetFrom(wrapper: CKRecordWrapper) -> Snippet? {
        #if os(iOS)
        guard let uuid = UUID(uuidString: wrapper.recordName) else { return nil }
        guard let name = wrapper["name"] as? String,
              let body = wrapper["body"] as? String
        else { return nil }

        let createdAt   = wrapper["createdAt"] as? Date ?? Date()
        let modifiedAt  = wrapper.modificationDate ?? wrapper["updatedAt"] as? Date ?? createdAt
        let hostTagsJSON = wrapper["hostTags"] as? String ?? "[]"
        let tagsJSON     = wrapper["tags"]     as? String ?? "[]"
        let hostTags = (try? JSONDecoder().decode([String].self, from: Data(hostTagsJSON.utf8))) ?? []
        let tags     = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8)))     ?? []

        return Snippet(
            id: SnippetID(uuid),
            name: name,
            body: body,
            hostTags: hostTags,
            tags: tags,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
        #else
        return nil
        #endif
    }
}
