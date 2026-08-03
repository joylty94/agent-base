#!/usr/bin/env bash
set -euo pipefail
ensure() {  # ensure <name> <color> <desc>
  if gh label list --limit 300 | cut -f1 | grep -qxF "$1"; then echo "exists: $1"
  else gh label create "$1" --color "$2" --description "$3" && echo "created: $1"; fi
}
ensure "area:backend"       1D76DB "백엔드 작업"
ensure "area:frontend"      5319E7 "프론트엔드 작업"
ensure "area:design"        E99695 "디자인 작업"
ensure "area:infra"         0052CC "인프라 작업"
ensure "stage:plan-review"  0E8A16 "플랜 검토 대기"
ensure "stage:impl"         FBCA04 "구현·테스트 대기"
ensure "stage:qa"           D93F0B "QA 대기"
ensure "blocked"            B60205 "QA 반려됨"
ensure "blocked-by-design"  C5DEF5 "디자인 완료 대기(자동 잠금, §8-2)"