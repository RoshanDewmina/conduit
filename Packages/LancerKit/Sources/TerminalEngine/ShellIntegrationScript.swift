import Foundation

public enum ShellIntegrationScript {
    public enum Shell: String, Sendable, CaseIterable {
        case bash
        case zsh
        case fish
    }

    public static func script(for shell: Shell) -> String {
        let name = "lancer-init.\(shell.rawValue)"
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
        __lancer_prompt_command() {
          local __lancer_status="$?"
          printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' "$__lancer_status" "${HOST:-${HOSTNAME:-localhost}}" "$PWD"
        }
        __lancer_preexec() {
          printf '\\033]133;C\\007'
        }
        if [ -n "${ZSH_VERSION-}" ]; then
          autoload -Uz add-zsh-hook 2>/dev/null
          add-zsh-hook -d precmd __lancer_prompt_command 2>/dev/null
          add-zsh-hook -d preexec __lancer_preexec 2>/dev/null
          add-zsh-hook precmd __lancer_prompt_command
          add-zsh-hook preexec __lancer_preexec
          # Suppress the partial-line marker ("%") zsh prints before a prompt
          # when the last command's output lacked a trailing newline — it would
          # otherwise leak into block output.
          PROMPT_EOL_MARK=''
        elif [ -n "${BASH_VERSION-}" ]; then
          __lancer_prompt_command() { local __lancer_status="$?"; trap '__lancer_preexec' DEBUG; printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' "$__lancer_status" "${HOSTNAME:-${HOST:-localhost}}" "$PWD"; }
          __lancer_preexec() { printf '\\033]133;C\\007'; trap - DEBUG; }
          PROMPT_COMMAND="__lancer_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
          trap '__lancer_preexec' DEBUG
        fi
        """
    }

    /// Encodes `script` as base64 and returns a single newline-free eval line.
    /// Works on both BSD base64 (macOS/iOS) and GNU base64: `--decode` is the
    /// portable flag; `-d`/`-D` diverge between implementations.
    private static func singleLineEval(_ script: String) -> String {
        let b64 = Data(script.utf8).base64EncodedString()
        return #"eval "$(printf %s '\#(b64)' | base64 --decode)""#
    }

    /// Returns a single newline-free line that installs the POSIX integration
    /// hooks into the running interactive shell via eval+base64.
    public static func bootstrapForPOSIXShellsOneLine() -> String {
        return singleLineEval(bootstrapForPOSIXShells())
    }

    /// Returns a single newline-free line for fish shell.
    public static func bootstrapForFishOneLine() -> String {
        let script = script(for: .fish)
        let b64 = Data(script.utf8).base64EncodedString()
        return "eval (printf %s '\(b64)' | base64 --decode)"
    }

    private static func fallbackScript(for shell: Shell) -> String {
        switch shell {
        case .bash:
            return """
            __lancer_prompt_command() { local s="$?"; trap '__lancer_preexec' DEBUG; printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' "$s" "${HOSTNAME:-${HOST:-localhost}}" "$PWD"; }
            __lancer_preexec() { printf '\\033]133;C\\007'; trap - DEBUG; }
            PROMPT_COMMAND="__lancer_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"; trap '__lancer_preexec' DEBUG
            """
        case .zsh:
            return """
            autoload -Uz add-zsh-hook 2>/dev/null
            __lancer_precmd() { local s="$?"; printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' "$s" "${HOST:-${HOSTNAME:-localhost}}" "$PWD"; }
            __lancer_preexec() { printf '\\033]133;C\\007'; }
            add-zsh-hook precmd __lancer_precmd; add-zsh-hook preexec __lancer_preexec
            PROMPT_EOL_MARK=''
            """
        case .fish:
            return """
            set -gx COLORFGBG '15;0'
            function __lancer_prompt --on-event fish_prompt; set -l s $status; printf '\\033]133;D;%s\\007\\033]133;A\\007\\033]7;file://%s%s\\007' $s (hostname) (pwd); end
            function __lancer_preexec --on-event fish_preexec; printf '\\033]133;C\\007'; end
            """
        }
    }
}
