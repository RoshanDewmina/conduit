# Conduit shim — sourced from ~/.zshrc / ~/.bashrc (managed block).
# Loads the real-binary map resolved at install time, then shadows `claude`
# with the daemon handoff. We deliberately do NOT resolve the real path via
# `command -v claude` here: after PATH prepends ~/.conduit/bin that would
# resolve to the shim itself and loop. The installer writes shim.env instead.
export CONDUIT_CLAUDE_WRAPPER_SHIM=1
[ -f "$HOME/.conduit/shim.env" ] && . "$HOME/.conduit/shim.env"
claude() {
  if [ -x "$HOME/.conduit/bin/claude" ]; then
    "$HOME/.conduit/bin/claude" "$@"
  else
    command claude "$@"
  fi
}
