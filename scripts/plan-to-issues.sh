#!/usr/bin/env bash
# usage: plan-to-issues.sh todos.txt
# 형식: 역할|제목|본문|key|depends_on   (key, depends_on 안 쓰면 "-")
#   key        : 다른 줄이 나를 가리킬 때 쓰는 이름표
#   depends_on : 내가 기다리는 이슈의 key — 반드시 그 줄보다 "뒤"에 적을 것(위에서부터 순서대로 읽음)
set -euo pipefail
file="$1"
declare -A issue_of   # key -> 이슈 번호

while IFS='|' read -r role title body key depends_on; do
  [ -z "${role:-}" ] && continue
  case "$role" in
    backend)  area="area:backend";;
    frontend) area="area:frontend";;
    design)   area="area:design";;
    infra)    area="area:infra";;
    *) echo "skip unknown role: $role" >&2; continue;;
  esac

  dep_issue=""
  if [ -n "${depends_on:-}" ] && [ "$depends_on" != "-" ]; then
    dep_issue="${issue_of[$depends_on]:-}"
    [ -z "$dep_issue" ] && echo "경고: key '$depends_on' 를 아직 못 찾음(순서 확인) — 잠금 없이 생성합니다." >&2
  fi

  if [ -n "$dep_issue" ]; then
    url=$(gh issue create --title "$title" --body "$body

Depends-on: #${dep_issue}" --label "$area" --label "blocked-by-design")
    echo "blocked: $area  $url  (depends on #$dep_issue)"
  else
    url=$(gh issue create --title "$title" --body "$body" --label "$area" --label "stage:plan-review")
    echo "created: $area  $url"
  fi

  if [ -n "${key:-}" ] && [ "$key" != "-" ]; then
    issue_of["$key"]=$(echo "$url" | grep -oE '[0-9]+$')
  fi
done < "$file"