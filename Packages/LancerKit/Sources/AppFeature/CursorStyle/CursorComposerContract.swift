import Foundation
import LancerCore

/// Pure contract-building logic for the composer's optional `ProofReceipt.Contract`
/// disclosure. Extracted from the old `CursorComposerSheet` (view file, deleted in the
/// 2026-07-09 shell rebuild) so `CursorComposerContractTests` keeps exercising the same
/// logic without depending on any specific composer view implementation.
public enum CursorComposerContract {
    public static let maxDoneCriteria = 8
    public static let maxValidationCommands = 4
    public static let maxCriterionLength = 200

    /// Builds a wire contract when the user supplied criteria, commands, or an
    /// explicit goal. Goal defaults to the prompt's first line when omitted.
    public static func resolvedContract(
        prompt: String,
        goal: String,
        doneCriteria: [String],
        validationCommands: [String]
    ) -> ProofReceipt.Contract? {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let criteria = doneCriteria
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxDoneCriteria)
        let commands = validationCommands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maxValidationCommands)
        guard !criteria.isEmpty || !commands.isEmpty || !trimmedGoal.isEmpty else { return nil }
        let effectiveGoal = trimmedGoal.isEmpty ? firstLine(of: prompt) : trimmedGoal
        guard !effectiveGoal.isEmpty else { return nil }
        return ProofReceipt.Contract(
            goal: effectiveGoal,
            doneCriteria: Array(criteria),
            validationCommands: Array(commands)
        )
    }

    private static func firstLine(of prompt: String) -> String {
        prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
    }
}

/// Pure CWD-resolution rule for the docked composer, shared by Home (always "~"),
/// a named workspace (resolved via `repoPaths`), and "All Repos" (blocked until a
/// thread is opened) — same rule the pre-rebuild `CursorAppShell.composerResolvedCWD`
/// used, factored out so it's independent of any one view.
public enum CursorComposerCWDResolution {
    public struct Resolution: Sendable, Equatable {
        public let path: String?
        public let blocked: Bool
        public let message: String?

        public init(path: String?, blocked: Bool, message: String?) {
            self.path = path
            self.blocked = blocked
            self.message = message
        }
    }

    public static func resolve(
        repoName: String,
        repoPaths: [String: String],
        hasSelectedThread: Bool
    ) -> Resolution {
        if repoName.isEmpty || repoName == "Home" {
            return Resolution(path: "~", blocked: false, message: nil)
        }
        if let path = repoPaths[repoName] {
            return Resolution(path: path, blocked: false, message: nil)
        }
        return Resolution(
            path: nil,
            blocked: !hasSelectedThread,
            message: "Path for \(repoName) unknown — open one of its threads first"
        )
    }
}
