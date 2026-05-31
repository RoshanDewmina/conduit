import Foundation

public enum ShellIntegrationScript {
    public enum Shell: String, Sendable, CaseIterable {
        case bash
        case zsh
        case fish
    }

    public static func script(for shell: Shell) -> String {
        let name = "conduit-init.\(shell.rawValue)"
        if let url = Bundle.module.url(forResource: name, withExtension: nil),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return fallbackScript(for: shell)
    }

    /// COLORFGBG environment hint for remote TUI programs (Claude Code, codex, etc.).
    /// Dark terminal themes → `15;0` (white fg on black bg), Light → `0;15`.
    /// Remote apps read COLORFGBG at startup to auto-select their colour scheme,
    /// avoiding the need to run `/theme` manually after every connect.
    public static func colorfgbgExport() -> String {
        let themeName = UserDefaults.standard.string(forKey: "terminalTheme") ?? "Dark"
        let isDark = themeName != "Light"
        return isDark ? "export COLORFGBG='15;0'" : "export COLORFGBG='0;15'"
    }

    public static func bootstrapForPOSIXShells() -> String {
        let colorHint = colorfgbgExport()
        return """
        \(colorHint)
        __conduit_prompt_command() {
          local __conduit_status="$?"
          printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' "$__conduit_status" "${HOST:-${HOSTNAME:-localhost}}" "$PWD"
        }
        __conduit_preexec() {
          printf '\\033]133;C\\007'
        }
        if [ -n "${ZSH_VERSION-}" ]; then
          autoload -Uz add-zsh-hook 2>/dev/null
          add-zsh-hook -d precmd __conduit_prompt_command 2>/dev/null
          add-zsh-hook -d preexec __conduit_preexec 2>/dev/null
          add-zsh-hook precmd __conduit_prompt_command
          add-zsh-hook preexec __conduit_preexec
          # Suppress the partial-line marker ("%") zsh prints before a prompt
          # when the last command's output lacked a trailing newline — it would
          # otherwise leak into block output.
          PROMPT_EOL_MARK=''
        elif [ -n "${BASH_VERSION-}" ]; then
          __conduit_prompt_command() { local __conduit_status="$?"; trap '__conduit_preexec' DEBUG; printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' "$__conduit_status" "${HOSTNAME:-${HOST:-localhost}}" "$PWD"; }
          __conduit_preexec() { printf '\\033]133;C\\007'; trap - DEBUG; }
          PROMPT_COMMAND="__conduit_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
          trap '__conduit_preexec' DEBUG
        fi
        """
    }

    private static func fallbackScript(for shell: Shell) -> String {
        switch shell {
        case .bash:
            return """
            __conduit_prompt_command() { local s="$?"; trap '__conduit_preexec' DEBUG; printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' "$s" "${HOSTNAME:-${HOST:-localhost}}" "$PWD"; }
            __conduit_preexec() { printf '\\033]133;C\\007'; trap - DEBUG; }
            PROMPT_COMMAND="__conduit_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"; trap '__conduit_preexec' DEBUG
            """
        case .zsh:
            return """
            autoload -Uz add-zsh-hook 2>/dev/null
            __conduit_precmd() { local s="$?"; printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' "$s" "${HOST:-${HOSTNAME:-localhost}}" "$PWD"; }
            __conduit_preexec() { printf '\\033]133;C\\007'; }
            add-zsh-hook precmd __conduit_precmd; add-zsh-hook preexec __conduit_preexec
            PROMPT_EOL_MARK=''
            """
        case .fish:
            return """
            function __conduit_prompt --on-event fish_prompt; set -l s $status; printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' $s (hostname) (pwd); end
            function __conduit_preexec --on-event fish_preexec; printf '\\033]133;C\\007'; end
            """
        }
    }
}
