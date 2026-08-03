# 프로젝트 작업 규약 (Agent Team)

이슈는 "컨베이어 벨트 위의 물건", `stage:*` 라벨은 "지금 어느 작업대에 있는지"다.
각자 자기 작업대(라벨)에 온 이슈만 처리하고, 끝나면 라벨을 다음 작업대로 넘긴다.

## 라벨 상태머신

- 이슈 생성 시: area:<역할> + stage:plan-review
- 흐름: stage:plan-review → stage:impl → stage:qa → (close)
- QA 반려: stage:qa 를 떼고 stage:impl 로 되돌리며 blocked 표시

## 브랜치 전략 (dev 기반, 역할별 워크트리)

- 베이스 브랜치는 `dev` (원격에 미리 있어야 함). 모든 feature 브랜치는 `dev`에서 갈라져서 `dev`로만 머지된다.
- 브랜치 이름 규칙: `feature/<역할>-<이슈번호>` (예: `feature/backend-42`)
- 역할마다 자기 전용 워크트리 폴더를 쓴다: `.claude/worktrees/backend`, `.claude/worktrees/frontend`,
  `.claude/worktrees/design`, `.claude/worktrees/qa`. 같은 폴더를 여러 팀원이 공유하지 않는다(각자 자기 것만 사용).
- backend/frontend/designer: 이슈를 claim 하면 가장 먼저 `./scripts/start-branch.sh <역할> <n>` 로
  자기 워크트리를 준비하고 `dev` 기준 새 브랜치를 만든다. **이후 모든 파일 작업(Read/Edit/Write)과 테스트 실행은
  `.claude/worktrees/<역할>/` 안에서** 한다 (예: `.claude/worktrees/backend/src/auth.ts`).
- 구현·테스트가 끝나면 브랜치를 push 하고 `dev`를 대상으로 PR을 연다. PR 링크를 이슈 댓글로 남기고 QA에게 인계한다.
- qa: PR을 받으면 `./scripts/qa-checkout.sh <브랜치명>` 으로 자기 워크트리(`.claude/worktrees/qa`)에 그 브랜치를
  체크아웃해서 실제로 돌려보고 검증한다. 통과하면 `gh pr merge`로 `dev`에 머지한 뒤 이슈를 close 한다.
- **브랜치 접근 제한(자동):** 각 역할은 자기 `feature/<역할>-<n>` 브랜치와 `dev` 이외의 브랜치는 checkout·push·merge·삭제할 수 없다.
  다른 브랜치를 건드리려 하면 `guard-branch.sh` 훅이 명령 실행 자체를 차단한다(§9-1) — 팀원이 실수하거나 지시를 잘못 이해해도
  다른 역할의 브랜치나 `main`을 건드릴 수 없다. QA만 예외로 **모든** `feature/*` 브랜치를 체크아웃할 수 있지만(검증이 본업이므로),
  그마저도 항상 detached HEAD로만 가능하고 push·브랜치 생성/삭제는 QA에게 전면 금지된다.

## 역할별 담당 큐 (각자 이 목록만 반복 처리)

- plan-reviewer : gh issue list --label "stage:plan-review"
- backend : gh issue list --label "area:backend" --label "stage:impl"
- frontend : gh issue list --label "area:frontend" --label "stage:impl"
- designer : gh issue list --label "area:design" --label "stage:impl"
- qa : gh issue list --label "stage:qa"

## 공통 루프

1. 자기 큐에서 가장 오래된 이슈 1건을 고른다.
2. 각 단계의 시작/완료를 ./scripts/issue-log.sh 로 이슈 댓글에 남긴다.
3. 자기 단계가 끝나면 라벨을 다음 단계로 넘긴다(아래 각 역할 절차 참고).
4. 큐를 다시 확인한다. 비어 있으면 리더에게 "idle"이라고 알리고 대기한다.

- 자기 담당 라벨/파일만 건드린다. 애매하면 리더에게 물어본다.

## plan-reviewer

1. ./scripts/issue-log.sh <n> plan-review start "확인할 범위·우려 포인트"
2. gstack 스킬로 접근방식·아키텍처·범위 점검: /plan-eng-review (디자인 이슈면 /plan-design-review, 요구가 모호하면 /spec)
3. 통과 → ./scripts/issue-log.sh <n> plan-review done "합의된 접근·주의점"
   → gh issue edit <n> --remove-label "stage:plan-review" --add-label "stage:impl"
   보류 → 문제점을 이슈 댓글로 남기고 리더에게 보고 (라벨은 그대로 둔다)
   ※ 구현·close 금지. 코드는 읽기만.
   ※ plan-review의 done 내용은 예외적으로 비우지 않는다 — "합의된 접근"은 backend/frontend가
   1번에서 그대로 읽고 따르는 실제 지시사항이라, 요약 로그가 아니라 이 단계의 산출물이다.

## backend / frontend — TDD 필수 (반드시 이 순서)

0. ./scripts/start-branch.sh <역할> <n> → .claude/worktrees/<역할>/ 에 dev 기준 feature/<역할>-<n> 브랜치 준비
   이후 모든 Read/Edit/Write와 테스트 실행은 이 워크트리 폴더 안에서 한다.
1. gh issue view <n> --comments 로 plan-review 합의사항 확인
2. ./scripts/issue-log.sh <n> test-plan start "무엇을 테스트할지(케이스 목록·커버 범위)"
   → 구현 코드를 쓰기 전에 실패하는 테스트(Red)부터 작성 (먼저 실패하는 걸 확인)
   → ./scripts/issue-log.sh <n> test-plan done
3. ./scripts/issue-log.sh <n> implement start "무엇을 구현할지(접근 방식·바꿀 파일)"
   → 테스트를 통과시키는 최소 구현(Green) 후 리팩터
   → ./scripts/issue-log.sh <n> implement done
4. ./scripts/issue-log.sh <n> test start "무엇을 검증할지(전체 스위트 범위·회귀 체크 포인트)"
   → 전체 테스트 실행, 모두 통과 + 회귀 확인
   → ./scripts/issue-log.sh <n> test done (실패가 남으면 done 호출 금지, 3번으로)
5. 브랜치를 push(`git -C .claude/worktrees/<역할> push -u origin feature/<역할>-<n>`)하고
   PR을 연다: `gh pr create --base dev --head feature/<역할>-<n> --title "..." --body "이슈 #<n>"`.
   PR 링크를 이슈 댓글로 남기고, `gh issue edit <n> --remove-label "stage:impl" --add-label "stage:qa"`,
   qa 팀원에게 SendMessage: "#<n> PR 열었음(링크), QA 부탁"
   ※ close·머지 금지(머지는 QA 담당). 테스트를 안 쓴 채 구현부터 시작하지 말 것.
   gstack: 모호하면 /spec, 어려운 버그는 /investigate, 구현 후 /review·/cso 로 자가점검.
6. QA가 반려하면(라벨이 다시 stage:impl + blocked로 옴) 같은 브랜치/워크트리에서 계속 수정하고,
   커밋 후 다시 push. 브랜치를 새로 만들지 않는다.
   ※ 각 단계의 note는 항상 start에 적는다("지금부터 무엇을 할지") — done은 완료만 표시하고 내용을 반복하지 않는다.
   (예외: plan-review의 done, QA 반려 사유 — §「공통 규칙」 참고)

## designer — TDD 비대상

0. ./scripts/start-branch.sh design <n> → .claude/worktrees/design/ 에 dev 기준 feature/design-<n> 브랜치 준비
1. ./scripts/issue-log.sh <n> implement start "무엇을 만들지(스펙·에셋·컴포넌트 범위)"
   → 산출물 작성 (/design-consultation, /design-shotgun, /design-html)
   → ./scripts/issue-log.sh <n> implement done
2. ./scripts/issue-log.sh <n> test start "무엇을 리뷰할지(체크리스트)"
   → 디자인 일관성/접근성 리뷰 (/design-review)
   → ./scripts/issue-log.sh <n> test done
3. 브랜치를 push하고 PR을 연다(위 backend/frontend 5번과 동일한 방식).
   `gh issue edit <n> --remove-label "stage:impl" --add-label "stage:qa"` → qa 에게 인계.
   ※ 여기서 '구현'=산출물 작성, '테스트'=디자인 리뷰. 코드 대신 문서/에셋을 이슈에 링크. close·머지 금지.

## qa (브랜치 작업 상세는 §9-2 참고)

1. ./scripts/issue-log.sh <n> qa start "무엇을 검증할지(체크리스트·시나리오)"
2. 이슈 댓글에서 앞 단계 done 기록 + PR 링크 확인
3. ./scripts/qa-checkout.sh <PR의 head 브랜치명> → .claude/worktrees/qa/ 에 그 브랜치를 체크아웃
4. 그 워크트리 안에서 실제로 돌려보고 검증 (/qa, 화면 /browse, 보안 /cso, 성능 /benchmark).
   머지 전에 `git -C .claude/worktrees/qa fetch origin dev && git -C .claude/worktrees/qa merge origin/dev --no-commit --no-ff`
   로 dev 최신 상태와 충돌이 없는지 먼저 확인한다. 충돌이 있으면 담당 팀원에게 되돌려 리베이스를 요청한다.
5. 통과 → ./scripts/issue-log.sh <n> qa done
   → `gh pr merge <PR번호> --squash --delete-branch` 로 dev에 머지
   → gh issue close <n> --comment "✅ 전체 단계 완료. QA 통과하여 dev에 머지 후 종료합니다."
   → (디자인 이슈였다면) ./scripts/unblock-dependents.sh <n> 로 이 디자인을 기다리던 프론트엔드 이슈 잠금 해제 (§8-2, 선택 기능)
   반려 → ./scripts/issue-log.sh <n> qa done "반려: <사유>"
   → gh issue edit <n> --remove-label "stage:qa" --add-label "stage:impl" --add-label "blocked"
   → 담당 역할 팀원에게 SendMessage 로 반려 사유 전달 (머지하지 않음, PR은 열어둠)
   ※ 소스 직접 수정 금지(읽기 위주). close는 반드시 머지 후에만.
   ※ qa done은 통과 시엔 내용 없이 완료만 표시하고, 반려 시에만 사유를 적는다 — 반려 사유는
   담당 팀원에게 전달되는 유일한 근거라서 예외적으로 done에 남긴다.

## 공통 규칙

- issue-log.sh의 note는 원칙적으로 start에 적고("지금부터 뭘 할지"), done은 완료 표시만 남긴다.
  예외는 둘뿐이다 — plan-review의 done(합의된 접근 자체가 이 단계의 산출물), QA 반려 시의 done
  (반려 사유는 완료 시점에만 나오고 담당 팀원에게 전달되는 유일한 근거).
- 커밋 메시지는 conventional commits (feat/fix/refactor/test/docs/chore).
- 워크트리 폴더(`.claude/worktrees/<역할>`)는 역할당 하나만 쓰고 재사용한다. 새 이슈를 시작할 때
  `start-branch.sh`가 그 폴더 안에서 dev 기준으로 브랜치를 새로 갈아 끼워준다.
- 막히면 무리해서 완료 표시하지 말고 리더에게 보고.
- **작업 중 todos.txt에 없던, 다른 역할의 작업이 필요함을 발견했을 때**: 그 역할의 파일은 절대 직접 고치지
  않는다(브랜치 접근 제한과 별개로, 담당이 아닌 영역은 원래 안 건드리는 게 원칙). 대신
  `gh issue create --title "..." --body "이슈 #<n> 작업 중 발견: <내용>" --label "area:<상대 역할>" --label "stage:plan-review"`
  로 새 이슈를 만들어 넘긴다 — 생성 즉시 그 역할의 정상 큐(plan-review)에 들어가 자동으로 처리된다.
  - **안 막히는 경우**(새 이슈 없이도 내 작업을 끝낼 수 있음): 새 이슈만 만들어두고 원래 하던 작업을 계속한다.
  - **막히는 경우**(그 결과가 나와야 내 작업을 끝낼 수 있음): 내 이슈 댓글에 "새 이슈 #<번호> 완료 대기 중"이라고
    남기고, 리더에게 SendMessage로 보고한 뒤 이 이슈는 미뤄두고 큐의 다음 이슈로 넘어간다(완료 표시 금지, 라벨도
    그대로 둔다). 새 이슈가 close되면 리더가 보류 중이던 담당자에게 재개를 알린다 — 라벨이 자동으로 넘어가진
    않으므로 리더가 직접 챙긴다.
  - §8-2의 `depends_on`/`unblock-dependents.sh`는 **plan-review 시작 전** 이슈를 잠가두는 장치라 이미
    stage:impl에 들어간 이슈에는 쓰지 않는다(잘못 걸면 이미 끝낸 plan-review 단계로 되돌아가버린다) — 그래서
    이 경우는 자동 라벨 전환 대신 리더 보고로 처리한다.
