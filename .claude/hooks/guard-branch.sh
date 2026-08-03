#!/usr/bin/env bash
# PreToolUse(Bash) 훅: git으로 브랜치를 직접 바꾸는 명령이면, 실행 중인 워크트리(=자기 역할)가
# 허용된 브랜치(dev, 또는 자기 feature/<역할>-<n>)만 건드리는지 검사한다.
set -euo pipefail
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

check_segment() {
  local seg="$1"
  local -a words
  read -r -a words <<< "$seg"
  local n=${#words[@]}

  local git_idx=-1 i
  for ((i=0; i<n; i++)); do
    if [ "${words[$i]}" = "git" ]; then git_idx=$i; break; fi
  done
  [ "$git_idx" -lt 0 ] && return 0

  # git 다음 전역 옵션(-C <path> 등)을 건너뛰며 실제 서브커맨드 위치(k)를 찾는다
  local role="root" path="" k=$((git_idx+1))
  while [ "$k" -lt "$n" ]; do
    case "${words[$k]}" in
      -C) path="${words[$((k+1))]:-}"; k=$((k+2));;
      -*) k=$((k+1));;
      *) break;;
    esac
  done
  case "$path" in
    *".claude/worktrees/qa"*)       role="qa";;
    *".claude/worktrees/backend"*)  role="backend";;
    *".claude/worktrees/frontend"*) role="frontend";;
    *".claude/worktrees/design"*)   role="design";;
  esac

  local sub="${words[$k]:-}"
  [ -z "$sub" ] && return 0

  local allow
  case "$role" in
    qa)       allow='^(dev|feature/.+)$';;
    backend)  allow='^(dev|feature/backend-[0-9]+)$';;
    frontend) allow='^(dev|feature/frontend-[0-9]+)$';;
    design)   allow='^(dev|feature/design-[0-9]+)$';;
    root)     allow='^dev$';;
  esac

  local branch="" start=$((k+1)) j w
  case "$sub" in
    checkout|switch)
      for ((j=start; j<n; j++)); do
        w="${words[$j]}"
        case "$w" in
          -b|-B|-c) branch="${words[$((j+1))]:-}"; break;;
          -*) continue;;
          *) branch="$w"; break;;
        esac
      done;;
    push)
      if echo "$seg" | grep -qE -- '(^|[[:space:]])(-f|--force|--force-with-lease)([[:space:]]|$)'; then
        echo "차단(guard-branch): force push는 허용되지 않습니다." >&2
        exit 2
      fi
      for ((j=start; j<n; j++)); do
        w="${words[$j]}"
        case "$w" in
          -*) continue;;
          *) branch="$w";;
        esac
      done;;
    merge)
      for ((j=start; j<n; j++)); do
        w="${words[$j]}"
        case "$w" in
          -*) continue;;
          *) branch="$w"; break;;
        esac
      done;;
    branch)
      for ((j=start; j<n; j++)); do
        w="${words[$j]}"
        case "$w" in
          -d|-D|-m|-M) branch="${words[$((j+1))]:-}"; break;;
          -*) continue;;
          *) branch="$w"; break;;
        esac
      done;;
  esac

  if [ "$role" = "qa" ] && { [ "$sub" = "push" ] || [ "$sub" = "branch" ]; }; then
    echo "차단(guard-branch): qa 워크트리는 검증 전용이라 push/branch 명령을 실행할 수 없습니다(머지는 gh pr merge로만)." >&2
    exit 2
  fi

  if [ -n "$branch" ]; then
    branch="${branch#origin/}"; branch="${branch%%:*}"
    if [ "$sub" = "merge" ]; then
      if [ "$branch" != "dev" ]; then
        echo "차단(guard-branch): merge 대상은 dev만 허용됩니다(받은 브랜치: $branch)." >&2
        exit 2
      fi
    else
      if ! echo "$branch" | grep -qE "$allow"; then
        echo "차단(guard-branch): '${role}' 컨텍스트에서 브랜치 '${branch}' 는 다룰 수 없습니다. 허용: ${allow}" >&2
        exit 2
      fi
    fi
  fi
  return 0
}

echo "$cmd" | grep -qE '(^|[;&|])[[:space:]]*git([[:space:]]|$)|^git([[:space:]]|$)' || exit 0

segments=$(echo "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
while IFS= read -r seg; do
  echo "$seg" | grep -qE '(^|[[:space:]])git([[:space:]]|$)' || continue
  check_segment "$seg"
done <<< "$segments"

exit 0