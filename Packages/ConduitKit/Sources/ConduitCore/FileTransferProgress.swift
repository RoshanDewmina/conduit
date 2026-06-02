import Foundation

/// Progress payload for SFTP upload/download operations.
public struct FileTransferProgress: Sendable, Equatable {
    public let bytesTransferred: Int64
    public let totalBytes: Int64?

    public init(bytesTransferred: Int64, totalBytes: Int64? = nil) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
    }

    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(bytesTransferred) / Double(totalBytes)))
    }
}
