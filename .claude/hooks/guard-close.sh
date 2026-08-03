#!/usr/bin/env bash
# PreToolUse(Bash) 훅: 실행하려는 명령이 gh issue close 면 필수 단계 완료를 검사.
set -euo pipefail
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# gh issue close 가 아니면 통과
echo "$cmd" | grep -qE 'gh +issue +close' || exit 0

issue=$(echo "$cmd" | grep -oE 'close +#?[0-9]+' | grep -oE '[0-9]+' | head -1)
[ -z "${issue:-}" ] && exit 0

comments=$(gh issue view "$issue" --comments 2>/dev/null || echo "")
labels=$(gh issue view "$issue" --json labels -q '.labels[].name' 2>/dev/null || echo "")

required="plan-review implement test qa"
# backend/frontend 는 TDD 필수 → test-plan(Red 먼저) 단계도 요구
if echo "$labels" | grep -qE 'area:(backend|frontend)'; then
  required="plan-review test-plan implement test qa"
fi

missing=""
for s in $required; do
  echo "$comments" | grep -q "STAGE:${s}:done" || missing="${missing} ${s}"
done

if [ -n "$missing" ]; then
  echo "이슈 #${issue}: 다음 단계 완료 기록이 없어 close를 막습니다 →${missing}" >&2
  exit 2   # 차단 + stderr가 팀원에게 피드백으로 전달됨
fi
exit 0