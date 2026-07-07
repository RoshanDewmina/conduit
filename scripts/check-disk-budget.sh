#!/usr/bin/env bash
# Guard against the disk-exhaustion incident pattern: git worktrees and Xcode
# DerivedData silently re-accumulating until the internal disk runs out.
#
# 2026-07-04: a session reduced 32 worktrees to 2; by 2026-07-06 it had
# regrown to 14, alongside 67GB of stale per-worktree DerivedData, with no
# automated check to catch either. This script makes both machine-checkable,
# plus flags worktrees living outside the approved /Volumes/LancerDev/worktrees
# location. It only warns and lists — it never deletes anything.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MIN_FREE_GB="${LANCER_MIN_FREE_GB:-20}"
MAX_DERIVED_DATA_GB="${LANCER_MAX_DERIVED_DATA_GB:-15}"
WORKTREE_ROOT="${LANCER_WORKTREE_ROOT:-/Volumes/LancerDev/worktrees}"
DERIVED_DATA_GLOB="${LANCER_DERIVED_DATA_GLOB:-$HOME/Library/Developer/Xcode/DerivedData/Lancer-*}"

VIOLATIONS=0

echo "== Disk budget check =="
echo

# 1. Free space on the volume backing the repo's data (internal SSD).
DATA_VOL="/System/Volumes/Data"
if ! df -k "$DATA_VOL" >/dev/null 2>&1; then
  DATA_VOL="/"
fi
AVAIL_KB="$(df -k "$DATA_VOL" | tail -1 | awk '{print $4}')"
AVAIL_GB=$(( AVAIL_KB / 1024 / 1024 ))
echo "Free space on $DATA_VOL: ${AVAIL_GB}GB (min: ${MIN_FREE_GB}GB)"
if [ "$AVAIL_GB" -lt "$MIN_FREE_GB" ]; then
  echo "  WARNING: below minimum free space threshold."
  VIOLATIONS=$((VIOLATIONS + 1))
fi
echo

# 2. DerivedData size for Lancer build products.
echo "DerivedData (Lancer-*):"
shopt -s nullglob
DD_DIRS=($DERIVED_DATA_GLOB)
shopt -u nullglob
TOTAL_DD_KB=0
if [ "${#DD_DIRS[@]}" -eq 0 ]; then
  echo "  none found"
else
  for d in "${DD_DIRS[@]}"; do
    SIZE_KB="$(du -sk "$d" 2>/dev/null | awk '{print $1}')"
    SIZE_KB="${SIZE_KB:-0}"
    TOTAL_DD_KB=$((TOTAL_DD_KB + SIZE_KB))
    echo "  $(du -sh "$d" 2>/dev/null | awk '{print $1}')	$d"
  done
fi
TOTAL_DD_GB=$(( TOTAL_DD_KB / 1024 / 1024 ))
echo "  total: ${TOTAL_DD_GB}GB (max: ${MAX_DERIVED_DATA_GB}GB)"
if [ "$TOTAL_DD_GB" -gt "$MAX_DERIVED_DATA_GB" ]; then
  echo "  WARNING: DerivedData exceeds budget. Not deleting automatically -- review, then if safe:"
  echo "    rm -rf ~/Library/Developer/Xcode/DerivedData/Lancer-*"
  VIOLATIONS=$((VIOLATIONS + 1))
fi
echo

# 3. Worktrees living outside the approved root.
echo "Worktrees outside $WORKTREE_ROOT:"
OUTSIDE_COUNT=0
while IFS= read -r wt; do
  [ -z "$wt" ] && continue
  case "$wt" in
    "$WORKTREE_ROOT"/*) continue ;;
  esac
  [ "$wt" = "$REPO_ROOT" ] && continue
  OUTSIDE_COUNT=$((OUTSIDE_COUNT + 1))
  BRANCH="$(git -C "$wt" branch --show-current 2>/dev/null || echo '?')"
  if [ -n "$BRANCH" ] && git -C "$wt" merge-base --is-ancestor "$BRANCH" master 2>/dev/null; then
    MERGE_STATUS="MERGED (safe to remove)"
  else
    MERGE_STATUS="not merged"
  fi
  echo "  $wt  branch=$BRANCH  $MERGE_STATUS"
done < <(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10)}')

if [ "$OUTSIDE_COUNT" -eq 0 ]; then
  echo "  none"
else
  echo "  WARNING: $OUTSIDE_COUNT worktree(s) outside the approved root."
  echo "  Migrate merged ones by removing them; move active ones under $WORKTREE_ROOT."
  VIOLATIONS=$((VIOLATIONS + 1))
fi
echo

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL: $VIOLATIONS check(s) over budget."
  exit 1
fi

echo "PASS: all checks within budget."
