#!/usr/bin/env bash
# usage: start-branch.sh <role> <issue-number>
set -euo pipefail
role="$1"; issue="$2"
wt=".claude/worktrees/$role"
branch="feature/${role}-${issue}"

git fetch origin dev

if [ -d "$wt" ]; then
  git -C "$wt" checkout -B "$branch" origin/dev
else
  git worktree add "$wt" -b "$branch" origin/dev
fi

echo "worktree: $wt"
echo "branch:   $branch"