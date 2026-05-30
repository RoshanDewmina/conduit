import Foundation
import ConduitCore
import PersistenceKit

#if os(iOS)
import CloudKit
import Security
#endif

// CKOperation callbacks are called serially by CloudKit, so this accumulator
// is safe even though Swift 6 can't prove it statically.
private final class CKAccumulator: @unchecked Sendable {
    var results: [CKRecordWrapper] = []
    var deletedIDs: [String] = []
}

/// Low-level wrapper around CloudKit private database operations.
/// All methods are no-ops on macOS, simulator, or when the CloudKit entitlement is absent.
public actor CloudSync {
    #if os(iOS) && !targetEnvironment(simulator)
    private let container: CKContainer?
    private var db: CKDatabase? { container?.privateCloudDatabase }
    #endif

    public init(containerIdentifier: String = "iCloud.dev.conduit.mobile") {
        #if os(iOS) && !targetEnvironment(simulator)
        self.container = CloudSync.hasCloudKitEntitlement()
            ? CKContainer(identifier: containerIdentifier)
            : nil
        #endif
    }

    /// Returns the current CloudKit account status.
    public func accountStatus() async throws -> CloudAccountStatus {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let container else { return .unavailable }
        let status = try await container.accountStatus()
        switch status {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .couldNotDetermine: return .unknown
        case .temporarilyUnavailable: return .unknown
        @unknown default: return .unknown
        }
        #else
        return .unavailable
        #endif
    }

    /// Fetches records of a given type modified after a server change token.
    /// Returns new/updated records and deleted record IDs.
    public func fetchChanges(recordType: String) async throws -> ([CKRecordWrapper], [String]) {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let db else { return ([], []) }
        let operation = CKFetchRecordZoneChangesOperation()
        let zoneID = CKRecordZone.default().zoneID
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        operation.recordZoneIDs = [zoneID]
        operation.configurationsByRecordZoneID = [zoneID: config]

        let acc = CKAccumulator()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result, record.recordType == recordType {
                    acc.results.append(CKRecordWrapper(record: record))
                }
            }
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                acc.deletedIDs.append(recordID.recordName)
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            db.add(operation)
        }
        return (acc.results, acc.deletedIDs)
        #else
        return ([], [])
        #endif
    }

    /// Saves or updates records in the private database.
    /// Uses .changedKeys so the last writer wins regardless of server state.
    public func save(records: [CKRecordWrapper]) async throws {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let db, !records.isEmpty else { return }
        let ckRecords = records.map(\.record)
        let operation = CKModifyRecordsOperation(recordsToSave: ckRecords, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            db.add(operation)
        }
        #endif
    }

    /// Deletes records from the private database by record name.
    public func delete(recordIDs: [String]) async throws {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let db, !recordIDs.isEmpty else { return }
        let ckIDs = recordIDs.map { CKRecord.ID(recordName: $0) }
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ckIDs)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            db.add(operation)
        }
        #endif
    }

    #if os(iOS) && !targetEnvironment(simulator)
    private static func hasCloudKitEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let key = "com.apple.developer.icloud-services" as CFString
        guard let value = SecTaskCopyValueForEntitlement(task, key, nil) as? [String] else { return false }
        return value.contains("CloudKit")
    }
    #endif
}

/// Platform-agnostic account status.
public enum CloudAccountStatus: Sendable, Equatable {
    case available, noAccount, restricted, unknown, unavailable
}

/// Wrapper to make CKRecord Sendable.
public struct CKRecordWrapper: @unchecked Sendable {
    #if os(iOS)
    public let record: CKRecord
    public init(record: CKRecord) { self.record = record }
    public var recordName: String { record.recordID.recordName }
    /// Server-set timestamp of when this record was last saved to CloudKit.
    /// Used as the authoritative LWW timestamp on pull.
    public var modificationDate: Date? { record.modificationDate }
    public subscript(key: String) -> (any CKRecordValueProtocol)? { record[key] }
    #else
    public var recordName: String { "" }
    public var modificationDate: Date? { nil }
    public init() {}
    #endif
}
