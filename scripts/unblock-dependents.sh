#!/usr/bin/env bash
# usage: unblock-dependents.sh <closed-issue-number>
# 방금 close된 이슈를 depends_on 으로 기다리던 blocked-by-design 이슈를 찾아 stage:plan-review 로 풀어준다.
set -euo pipefail
closed="$1"

gh issue list --label "blocked-by-design" --state open --json number,body \
  -q ".[] | select(.body | test(\"Depends-on: *#${closed}(\\\\D|\$)\")) | .number" |
while read -r dep; do
  [ -z "$dep" ] && continue
  gh issue edit "$dep" --remove-label "blocked-by-design" --add-label "stage:plan-review"
  gh issue comment "$dep" --body "🔓 의존 이슈 #${closed} 완료 → 잠금 해제, stage:plan-review 로 전환"
  echo "unblocked: #$dep"
done