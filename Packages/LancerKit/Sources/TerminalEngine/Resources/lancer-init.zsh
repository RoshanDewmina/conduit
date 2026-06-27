autoload -Uz add-zsh-hook 2>/dev/null

__lancer_precmd() {
  local __lancer_status="$?"
  printf '\033]133;D;%s\007\033]133;A\007\033]7;file://%s%s\007' "$__lancer_status" "${HOST:-${HOSTNAME:-localhost}}" "$PWD"
}

__lancer_preexec() {
  printf '\033]133;C\007'
}

add-zsh-hook -d precmd __lancer_precmd 2>/dev/null
add-zsh-hook -d preexec __lancer_preexec 2>/dev/null
add-zsh-hook precmd __lancer_precmd
add-zsh-hook preexec __lancer_preexec

# Suppress zsh's partial-line marker ("%") so it doesn't leak into block output.
PROMPT_EOL_MARK=''
