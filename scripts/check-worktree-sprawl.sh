#!/usr/bin/env bash
# Warn when git worktrees have re-accumulated past a small threshold.
#
# 2026-07-04: a session reduced 32 worktrees to 2; by 2026-07-06 it had
# regrown to 14 with no automated check to catch it, contributing to at
# least one disk-exhaustion incident (67GB of stale per-worktree
# DerivedData). Run this ad hoc, or wire it into a pre-dispatch check in
# lancer-parallel-handoff, to catch re-accumulation early.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

THRESHOLD="${LANCER_WORKTREE_WARN_THRESHOLD:-5}"
COUNT="$(git worktree list | wc -l | tr -d ' ')"

echo "Active worktrees: $COUNT (warn threshold: $THRESHOLD)"
git worktree list

if [ "$COUNT" -gt "$THRESHOLD" ]; then
  echo
  echo "WARNING: $COUNT worktrees exceeds the threshold of $THRESHOLD."
  echo "Check each one for a merged/abandoned branch before creating more:"
  echo "  for wt in \$(git worktree list --porcelain | awk '/^worktree /{print \$2}'); do"
  echo "    branch=\$(git -C \"\$wt\" branch --show-current)"
  echo "    git merge-base --is-ancestor \"\$branch\" master && echo \"\$wt: MERGED (safe to remove)\" || echo \"\$wt: not merged\""
  echo "  done"
  exit 1
fi
