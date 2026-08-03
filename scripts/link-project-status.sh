#!/usr/bin/env bash
# usage: ./scripts/link-project-status.sh <project-number>
# 이미 있는 프로젝트의 기본 "Status" 필드(Backlog/Ready/In progress/In review/Done)를
# 그대로 활용해서, stage:* 라벨/close 상태에 맞춰 자동으로 컬럼을 옮겨주는 워크플로우를 생성한다.
set -euo pipefail

num="$1"
owner="$(gh repo view --json owner -q .owner.login)"
repo="$(gh repo view --json name -q .name)"

echo "1) 저장소 연결 확인..."
gh project link "$num" --owner "$owner" --repo "$repo" 2>/dev/null || echo "   (이미 연결됨)"

project_id=$(gh project view "$num" --owner "$owner" --format json -q .id)
echo "   project_id = $project_id"

echo "2) 'Status' 필드 확인..."
field_id=$(gh project field-list "$num" --owner "$owner" --format json \
  -q '.fields[] | select(.name=="Status") | .id')
if [ -z "$field_id" ]; then
  echo "   'Status' 필드를 못 찾았습니다. 필드 이름이 다르면 이 스크립트의 \"Status\" 부분을 실제 이름으로 바꿔서 다시 실행하세요." >&2
  exit 1
fi
echo "   field_id = $field_id"

opt() { gh project field-list "$num" --owner "$owner" --format json \
  -q ".fields[] | select(.name==\"Status\") | .options[] | select(.name==\"$1\") | .id"; }
opt_backlog=$(opt "Backlog"); opt_ready=$(opt "Ready")
opt_inprogress=$(opt "In progress"); opt_inreview=$(opt "In review"); opt_done=$(opt "Done")

set_status() {
  gh project item-edit --project-id "$project_id" --id "$1" \
    --field-id "$field_id" --single-select-option-id "$2" || echo "   (상태 설정 실패, 건너뜀)"
}

echo "3) 기존 이슈를 현재 라벨/상태 기준으로 채워 넣는 중..."
gh issue list --repo "$owner/$repo" --state all --limit 500 --json number,url,labels,state |
jq -c '.[]' | while read -r issue; do
  iurl=$(echo "$issue" | jq -r .url)
  state=$(echo "$issue" | jq -r .state)
  labels=$(echo "$issue" | jq -r '.labels[].name' | tr '\n' ',')
  item_id=$(gh project item-add "$num" --owner "$owner" --url "$iurl" --format json -q .id 2>/dev/null || true)
  [ -z "$item_id" ] && { echo "   #$(echo "$issue" | jq -r .number) 추가 실패/이미 있음, 건너뜀"; continue; }
  if [ "$state" = "CLOSED" ]; then
    set_status "$item_id" "$opt_done"
  else
    case "$labels" in
      *stage:plan-review*) set_status "$item_id" "$opt_ready";;
      *stage:impl*)        set_status "$item_id" "$opt_inprogress";;
      *stage:qa*)          set_status "$item_id" "$opt_inreview";;
      *)                   set_status "$item_id" "$opt_backlog";;
    esac
  fi
  echo "   #$(echo "$issue" | jq -r .number) 처리 완료"
done

echo "4) .github/workflows/sync-project-status.yml 생성..."
mkdir -p .github/workflows
cat > .github/workflows/sync-project-status.yml <<YAML
name: sync-project-status
on:
  issues:
    types: [labeled, unlabeled, closed, reopened]

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - name: 라벨/상태를 보고 Status 필드를 맞춘다
        env:
          GH_TOKEN: \${{ secrets.PROJECT_TOKEN }}
        run: |
          ACTION="\${{ github.event.action }}"
          LABELS="\${{ join(github.event.issue.labels.*.name, ',') }}"
          if [ "\$ACTION" = "closed" ]; then
            OPTION_ID="$opt_done"
          else
            case "\$LABELS" in
              *stage:plan-review*) OPTION_ID="$opt_ready";;
              *stage:impl*)        OPTION_ID="$opt_inprogress";;
              *stage:qa*)          OPTION_ID="$opt_inreview";;
              *)                   OPTION_ID="$opt_backlog";;
            esac
          fi
          ITEM_ID=\$(gh project item-add $num --owner "$owner" \\
            --url "\${{ github.event.issue.html_url }}" --format json -q .id)
          gh project item-edit --project-id "$project_id" --id "\$ITEM_ID" \\
            --field-id "$field_id" --single-select-option-id "\$OPTION_ID"
YAML

echo
echo "완료!"
echo "남은 수동 작업: git add .github/workflows/sync-project-status.yml && git commit -m 'chore: project status sync' && git push"
