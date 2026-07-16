#if os(iOS)
import Foundation

enum TerminalShellCommand {
    /// `cd` into `cwd` for an interactive shell startup command.
    static func cdToWorkingDirectory(_ cwd: String) -> String? {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "cd \(shellQuote(trimmed))"
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
#endif
