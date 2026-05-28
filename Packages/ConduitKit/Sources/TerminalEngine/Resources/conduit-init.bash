__conduit_prompt_command() {
  local __conduit_status="$?"
  trap '__conduit_preexec' DEBUG
  printf '\033]133;D;%s\007\033]133;A\007\033]7;file://%s%s\007' "$__conduit_status" "${HOSTNAME:-${HOST:-localhost}}" "$PWD"
}

__conduit_preexec() {
  local __conduit_command="${BASH_COMMAND:-}"
  case "$__conduit_command" in
    __conduit_*|trap\ *|printf\ *133*) return ;;
  esac
  printf '\033]133;C\007'
  trap - DEBUG
}

case ";${PROMPT_COMMAND-};" in
  *";__conduit_prompt_command;"*) ;;
  *) PROMPT_COMMAND="__conduit_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
trap '__conduit_preexec' DEBUG
