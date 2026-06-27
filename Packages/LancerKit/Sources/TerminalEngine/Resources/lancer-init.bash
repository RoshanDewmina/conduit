__lancer_prompt_command() {
  local __lancer_status="$?"
  trap '__lancer_preexec' DEBUG
  printf '\033]133;D;%s\007\033]133;A\007\033]7;file://%s%s\007' "$__lancer_status" "${HOSTNAME:-${HOST:-localhost}}" "$PWD"
}

__lancer_preexec() {
  local __lancer_command="${BASH_COMMAND:-}"
  case "$__lancer_command" in
    __lancer_*|trap\ *|printf\ *133*) return ;;
  esac
  printf '\033]133;C\007'
  trap - DEBUG
}

case ";${PROMPT_COMMAND-};" in
  *";__lancer_prompt_command;"*) ;;
  *) PROMPT_COMMAND="__lancer_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
trap '__lancer_preexec' DEBUG
