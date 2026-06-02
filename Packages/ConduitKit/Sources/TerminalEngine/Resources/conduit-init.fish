functions -e __conduit_prompt 2>/dev/null
functions -e __conduit_preexec 2>/dev/null

# COLORFGBG hint: fish does not inherit this from the shell integration bootstrap,
# so we set it here. Remote TUI programs (Claude Code, codex) read COLORFGBG at
# startup to auto-select dark vs light scheme.
set -gx COLORFGBG '15;0'

function __conduit_prompt --on-event fish_prompt
    set -l __conduit_status $status
    printf '\033]133;D;%s\007\033]133;A\007\033]7;file://%s%s\007' $__conduit_status (hostname) (pwd)
end

function __conduit_preexec --on-event fish_preexec
    printf '\033]133;C\007'
end
