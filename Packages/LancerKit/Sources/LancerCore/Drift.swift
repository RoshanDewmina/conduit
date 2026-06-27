import Foundation

/// What kind of remediation a drift finding supports. Mirrors the `remediation`
/// field produced by `lancerd`. Additive: older daemons omit it and findings
/// default to `.manual` (no auto-fix offered).
public enum DriftRemediation: String, Codable, Hashable, Sendable {
    /// The daemon can safely & idempotently repair this (e.g. comment out the
    /// dead reference line in the instruction file). Surfaced as "Apply fix".
    case applyFix = "apply-fix"
    /// Best resolved by authoring a policy/decision rather than an in-place edit.
    /// Surfaced as "Create policy" (handled client-side, no daemon write).
    case createPolicy = "create-policy"
    /// No automatic action is safe; the user must inspect manually. The only
    /// affordance is "Ignore".
    case manual = "manual"
}

/// One reference in an agent instruction file that no longer resolves to a file
/// on disk. Mirrors `DriftFinding` from `lancerd`'s `agent.drift.scan` result.
public struct DriftFinding: Codable, Identifiable, Hashable, Sendable {
    public let file: String
    public let line: Int
    public let kind: String // "dead-import" | "dead-link"
    public let ref: String
    public let message: String
    /// Whether (and how) this finding can be remediated. Decoded leniently:
    /// absent or unknown values fall back to `.manual` so an older daemon that
    /// predates remediation never offers an unsafe auto-fix.
    public let remediation: DriftRemediation

    public var id: String { "\(file):\(line):\(kind):\(ref)" }

    public init(
        file: String,
        line: Int,
        kind: String,
        ref: String,
        message: String,
        remediation: DriftRemediation = .manual
    ) {
        self.file = file
        self.line = line
        self.kind = kind
        self.ref = ref
        self.message = message
        self.remediation = remediation
    }

    private enum CodingKeys: String, CodingKey {
        case file, line, kind, ref, message, remediation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        line = try c.decode(Int.self, forKey: .line)
        kind = try c.decode(String.self, forKey: .kind)
        ref = try c.decode(String.self, forKey: .ref)
        message = try c.decode(String.self, forKey: .message)
        remediation = (try? c.decodeIfPresent(DriftRemediation.self, forKey: .remediation)) ?? .manual
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
