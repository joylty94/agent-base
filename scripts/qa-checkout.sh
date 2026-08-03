#!/usr/bin/env bash
# usage: qa-checkout.sh <branch-name>
set -euo pipefail
branch="$1"
wt=".claude/worktrees/qa"

git fetch origin "$branch"

if [ -d "$wt" ]; then
  git -C "$wt" fetch origin "$branch"
  git -C "$wt" checkout --detach "origin/$branch"
else
  git worktree add --detach "$wt" "origin/$branch"
fi

echo "worktree: $wt (detached at origin/$branch)"