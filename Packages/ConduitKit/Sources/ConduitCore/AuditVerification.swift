import Foundation

public struct AuditVerification: Sendable, Codable {
    public let valid: Bool
    public let brokenAt: Int?
    public let entryCount: Int
    public let firstTimestamp: String?
    public let lastTimestamp: String?

    public init(valid: Bool, brokenAt: Int? = nil, entryCount: Int, firstTimestamp: String? = nil, lastTimestamp: String? = nil) {
        self.valid = valid
        self.brokenAt = brokenAt
        self.entryCount = entryCount
        self.firstTimestamp = firstTimestamp
        self.lastTimestamp = lastTimestamp
    }
}
