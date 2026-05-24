import Foundation
import ConduitCore
import PersistenceKit

#if os(iOS)
import CloudKit
#endif

// CKOperation callbacks are called serially by CloudKit, so this accumulator
// is safe even though Swift 6 can't prove it statically.
private final class CKAccumulator: @unchecked Sendable {
    var results: [CKRecordWrapper] = []
    var deletedIDs: [String] = []
}

/// Low-level wrapper around CloudKit private database operations.
/// All methods are no-ops on macOS or when CloudKit is unavailable (simulator without entitlement).
public actor CloudSync {
    #if os(iOS) && !targetEnvironment(simulator)
    private let container: CKContainer
    private var db: CKDatabase { container.privateCloudDatabase }
    #endif

    public init(containerIdentifier: String = "iCloud.dev.conduit.mobile") {
        #if os(iOS) && !targetEnvironment(simulator)
        self.container = CKContainer(identifier: containerIdentifier)
        #endif
    }

    /// Returns the current CloudKit account status.
    public func accountStatus() async throws -> CloudAccountStatus {
        #if os(iOS) && !targetEnvironment(simulator)
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
            self.db.add(operation)
        }
        return (acc.results, acc.deletedIDs)
        #else
        return ([], [])
        #endif
    }

    /// Saves or updates records in the private database.
    public func save(records: [CKRecordWrapper]) async throws {
        #if os(iOS) && !targetEnvironment(simulator)
        guard !records.isEmpty else { return }
        let ckRecords = records.map(\.record)
        let operation = CKModifyRecordsOperation(recordsToSave: ckRecords, recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            self.db.add(operation)
        }
        #endif
    }
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
    public subscript(key: String) -> (any CKRecordValueProtocol)? { record[key] }
    #else
    public var recordName: String { "" }
    public init() {}
    #endif
}
