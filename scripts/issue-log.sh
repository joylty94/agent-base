#!/usr/bin/env bash
# usage: issue-log.sh <issue-number> <stage> <start|done> [note]
#   stage: plan-review | test-plan | implement | test | qa
#   note는 여러 줄(개행 포함)이어도 됨 — 각 줄이 인용 블록 안에서 줄바꿈된 채로 표시됨
set -euo pipefail

issue="$1"; stage="$2"; status="$3"; note="${4:-}"

case "$stage" in
  plan-review) label="플랜 검토";;
  test-plan)   label="테스트 계획(Red)";;
  implement)   label="구현(Green)";;
  test)        label="테스트 실행";;
  qa)          label="QA";;
  *) echo "unknown stage: $stage" >&2; exit 1;;
esac

case "$status" in
  start) icon="▶️"; word="시작";;
  done)  icon="✅"; word="완료";;
  *) echo "status must be start|done" >&2; exit 1;;
esac

ts="$(date '+%Y-%m-%d %H:%M %Z')"
body="${icon} **${label} ${word}** — ${ts}"

if [ -n "$note" ]; then
  # 매 줄 앞에 '> ' 를 붙이고 끝에 공백 두 칸(마크다운 강제 줄바꿈)을 추가.
  # 이렇게 안 하면 note가 여러 줄일 때 둘째 줄부터 인용 블록이 깨지거나 한 줄로 뭉쳐 보인다.
  quoted="$(printf '%s\n' "$note" | sed -e 's/[[:space:]]*$//' -e 's/^/> /' -e 's/$/  /')"
  body="${body}
${quoted}"
fi

# 숨은 마커: close 게이트가 이 마커로 단계 완료를 집계
body="${body}

<!-- STAGE:${stage}:${status} -->"

gh issue comment "$issue" --body "$body"