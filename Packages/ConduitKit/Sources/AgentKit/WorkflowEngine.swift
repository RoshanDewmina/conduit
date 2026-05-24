import Foundation
import ConduitCore

/// Executes multi-step workflow snippets, resolving `{{paramName}}` placeholders
/// before emitting each command line.
public actor WorkflowEngine {

    public init() {}

    /// Runs a workflow snippet line-by-line.
    ///
    /// - Parameters:
    ///   - workflow: The snippet whose `body` contains one command per line.
    ///   - parameterResolver: Called once per unique parameter name. Must return
    ///     the resolved value for that parameter.
    ///   - onCommand: Called for each resolved command line (blank lines are skipped).
    public func run(
        workflow: Snippet,
        parameterResolver: @escaping @Sendable (String) async -> String,
        onCommand: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        let lines = workflow.body.components(separatedBy: "\n")

        // Collect unique parameters across all lines upfront so we call
        // parameterResolver exactly once per unique param name.
        var orderedParams: [String] = []
        var seen = Set<String>()
        for line in lines {
            for param in extractParams(from: line) where !seen.contains(param) {
                seen.insert(param)
                orderedParams.append(param)
            }
        }

        // Resolve all parameters.
        var resolved: [String: String] = [:]
        for param in orderedParams {
            resolved[param] = await parameterResolver(param)
        }

        // Emit resolved command lines.
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            var command = trimmed
            for (param, value) in resolved {
                command = command.replacingOccurrences(of: "{{\(param)}}", with: value)
            }
            try await onCommand(command)
        }
    }

    /// Parses `{{paramName}}` tokens from `line` and returns unique param names
    /// in the order they first appear.
    internal func extractParams(from line: String) -> [String] {
        let pattern = #"\{\{([A-Za-z0-9_]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, range: range)

        var results: [String] = []
        var seen = Set<String>()
        for match in matches {
            if let r = Range(match.range(at: 1), in: line) {
                let name = String(line[r])
                if !seen.contains(name) {
                    seen.insert(name)
                    results.append(name)
                }
            }
        }
        return results
    }
}
