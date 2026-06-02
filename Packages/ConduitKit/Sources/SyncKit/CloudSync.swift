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
/// All methods are no-ops on macOS, simulator, or when the CloudKit entitlement is absent.
public actor CloudSync {
    #if os(iOS) && !targetEnvironment(simulator)
    private let container: CKContainer?
    private var db: CKDatabase? { container?.privateCloudDatabase }
    #endif

    public init(
        containerIdentifier: String = "iCloud.dev.conduit.mobile",
        cloudKitEnabled: Bool = false
    ) {
        #if os(iOS) && !targetEnvironment(simulator)
        // #region agent log
        CloudSync.debugLog(
            hypothesisId: "A",
            location: "CloudSync.swift:init",
            message: "CloudKit entitlement probe",
            data: [
                "cloudKitEnabled": cloudKitEnabled,
                "containerIdentifier": containerIdentifier,
                "willCreateContainer": cloudKitEnabled,
            ]
        )
        // #endregion
        self.container = cloudKitEnabled ? CKContainer(identifier: containerIdentifier) : nil
        // #region agent log
        CloudSync.debugLog(
            hypothesisId: "C",
            location: "CloudSync.swift:init",
            message: "CloudSync container state",
            data: ["containerIsNil": container == nil]
        )
        // #endregion
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
    public func save(records: [CKRecordWrapper]) async throws {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let db, !records.isEmpty else { return }
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
            db.add(operation)
        }
        #endif
    }

    #if os(iOS) && !targetEnvironment(simulator)
    private static func debugLog(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        let payload: [String: Any] = [
            "sessionId": "6a22e9",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload)
        else { return }
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:7531/ingest/f956616c-beac-4baf-8b56-a323a2cf21e8")!
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("6a22e9", forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = json
        URLSession.shared.dataTask(with: request).resume()
    }

    static func debugLogSyncStart(status: String) {
        debugLog(
            hypothesisId: "D",
            location: "SyncEngine.swift:start",
            message: "SyncEngine start account status",
            data: ["status": status]
        )
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
    public subscript(key: String) -> (any CKRecordValueProtocol)? { record[key] }
    #else
    public var recordName: String { "" }
    public init() {}
    #endif
}
