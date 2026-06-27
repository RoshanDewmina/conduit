import Foundation

/// A one-glance, plain-language summary of what a pending `Approval` will do.
///
/// Pure and on-device: derived entirely from the `Approval` already on the phone
/// (kind, command, patch, policy blast radius) — no daemon verb, no round-trip.
/// `headline` is the single line to surface before the user decides; `facts` are
/// optional supporting bullets for a denser surface.
public struct ApprovalSummary: Sendable, Hashable {
    public let headline: String
    public let facts: [String]

    public init(headline: String, facts: [String] = []) {
        self.headline = headline
        self.facts = facts
    }

    public static func derive(from a: Approval) -> ApprovalSummary {
        // Impact tags come from the daemon's policy blast radius when present.
        var impact: [String] = []
        if a.blastRadius?.touchesGit == true { impact.append("touches git") }
        if a.blastRadius?.touchesNetwork == true { impact.append("network access") }

        switch a.kind {
        case .askQuestion:
            let q = (a.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return ApprovalSummary(headline: q.isEmpty ? "Asks a question" : "Asks: \(truncate(q, 80))")

        case .patch:
            let stats = diffStats(a.patch)
            let fileCount = a.blastRadius?.files?.count ?? stats.files
            let base = fileCount > 0 ? "Edits \(fileCount) file\(fileCount == 1 ? "" : "s")" : "Edits the working tree"
            var facts = impact
            if stats.added + stats.removed > 0 { facts.insert("+\(stats.added) −\(stats.removed)", at: 0) }
            return ApprovalSummary(headline: join(base, impact), facts: facts)

        case .fileWrite:  return ApprovalSummary(headline: join("Writes a file", impact), facts: impact)
        case .fileDelete: return ApprovalSummary(headline: join("Deletes a file", impact), facts: impact)
        case .network:    return ApprovalSummary(headline: join("Makes a network request", impact), facts: impact)
        case .credential: return ApprovalSummary(headline: join("Accesses a credential", impact), facts: impact)
        case .browser:    return ApprovalSummary(headline: join("Controls the browser", impact), facts: impact)
        case .callMCP:    return ApprovalSummary(headline: join("Calls an MCP tool", impact), facts: impact)
        case .command:
            let base = commandVerb(a.command).map { "Runs `\($0)`" } ?? "Runs a shell command"
            return ApprovalSummary(headline: join(base, impact), facts: impact)
        }
    }

    // MARK: - Derivation helpers

    private static func join(_ base: String, _ impact: [String]) -> String {
        impact.isEmpty ? base : base + " · " + impact.joined(separator: " · ")
    }

    private static func truncate(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    /// First command token (basename), plus the subcommand for common multiplexer
    /// CLIs (`git push`, `npm run`) so the headline reads naturally. nil if empty.
    static func commandVerb(_ command: String?) -> String? {
        let trimmed = (command ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        guard let first = tokens.first else { return nil }
        let head = first.split(separator: "/").last.map(String.init) ?? first
        let multiplexers: Set<String> = ["git", "npm", "bun", "yarn", "pnpm", "cargo", "go", "docker", "kubectl", "brew", "pip", "pip3"]
        if multiplexers.contains(head), tokens.count > 1, !tokens[1].hasPrefix("-") {
            return "\(head) \(tokens[1])"
        }
        return head
    }

    /// Count files / added / removed lines from a unified diff. Best-effort, never throws.
    static func diffStats(_ patch: String?) -> (files: Int, added: Int, removed: Int) {
        guard let patch, !patch.isEmpty else { return (0, 0, 0) }
        var files = 0, added = 0, removed = 0
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") { files += 1 }
            else if line.hasPrefix("+++") || line.hasPrefix("---") { continue }
            else if line.hasPrefix("+") { added += 1 }
            else if line.hasPrefix("-") { removed += 1 }
        }
        // Patches without `diff --git` headers (raw hunks): fall back to one file.
        if files == 0, added + removed > 0 { files = 1 }
        return (files, added, removed)
    }
}
