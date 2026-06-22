import Foundation

/// One reference in an agent instruction file that no longer resolves to a file
/// on disk. Mirrors `DriftFinding` from `lancerd`'s `agent.drift.scan` result.
public struct DriftFinding: Codable, Identifiable, Hashable, Sendable {
    public let file: String
    public let line: Int
    public let kind: String // "dead-import" | "dead-link"
    public let ref: String
    public let message: String

    public var id: String { "\(file):\(line):\(kind):\(ref)" }

    public init(file: String, line: Int, kind: String, ref: String, message: String) {
        self.file = file
        self.line = line
        self.kind = kind
        self.ref = ref
        self.message = message
    }
}

/// Result of one setup-drift scan over a repo's instruction topology.
/// Mirrors `DriftReport` from `lancerd`.
public struct DriftReport: Codable, Hashable, Sendable {
    public let root: String
    public let scanned: Int
    public let findings: [DriftFinding]

    public init(root: String, scanned: Int, findings: [DriftFinding]) {
        self.root = root
        self.scanned = scanned
        self.findings = findings
    }
}
