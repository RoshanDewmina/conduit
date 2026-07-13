import Foundation

/// Claude Code injects user-role XML envelopes that must not render as chat turns.
enum ClaudeMetaPrompt {
    static func isWrapperUserText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<local-command-caveat>")
            || trimmed.hasPrefix("<command-name>")
            || trimmed.hasPrefix("<command-message>")
            || trimmed.hasPrefix("<system-reminder>")
            || trimmed.hasPrefix("<task-notification>")
    }
}
