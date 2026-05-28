autoload -Uz add-zsh-hook 2>/dev/null

__conduit_precmd() {
  local __conduit_status="$?"
  printf '\033]133;D;%s\007\033]133;A\007\033]7;file://%s%s\007' "$__conduit_status" "${HOST:-${HOSTNAME:-localhost}}" "$PWD"
}

__conduit_preexec() {
  printf '\033]133;C\007'
}

add-zsh-hook -d precmd __conduit_precmd 2>/dev/null
add-zsh-hook -d preexec __conduit_preexec 2>/dev/null
add-zsh-hook precmd __conduit_precmd
add-zsh-hook preexec __conduit_preexec
