# Lancer shim — sourced from ~/.zshrc / ~/.bashrc (managed block).
# Loads the real-binary map resolved at install time, then shadows `claude`
# with the daemon handoff. We deliberately do NOT resolve the real path via
# `command -v claude` here: after PATH prepends ~/.lancer/bin that would
# resolve to the shim itself and loop. The installer writes shim.env instead.
export LANCER_CLAUDE_WRAPPER_SHIM=1
[ -f "$HOME/.lancer/shim.env" ] && . "$HOME/.lancer/shim.env"
claude() {
  if [ -x "$HOME/.lancer/bin/claude" ]; then
    "$HOME/.lancer/bin/claude" "$@"
  else
    command claude "$@"
  fi
}
