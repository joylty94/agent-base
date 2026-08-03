# agent-base

**여러 역할의 AI 에이전트가 GitHub 이슈를 주고받으며 협업하는 개발 파이프라인 기반(base) 프로젝트.**

다른 AI 에이전트 프로젝트를 시작할 때 그대로 복사해서 쓰는 "뼈대" 저장소다. 실제 애플리케이션 코드는
들어 있지 않고, **AI 팀이 어떻게 일할지에 대한 규칙·역할·자동화 스크립트**만 담겨 있다.

핵심 아이디어 한 줄:

> 이슈는 "컨베이어 벨트 위의 물건", `stage:*` 라벨은 "지금 어느 작업대에 있는지"다.
> 각 역할(에이전트)은 자기 작업대에 온 이슈만 처리하고, 끝나면 라벨을 다음 작업대로 넘긴다.

---

## 한눈에 보는 동작 흐름

```
사람이 요구사항 작성 (요건.md)
        │
        ▼
todos.txt 로 정리  ──(plan-to-issues.sh)──►  GitHub 이슈 여러 개 자동 생성
        │                                     (area:<역할> + stage:plan-review 라벨)
        ▼
┌──────────────────────────────────────────────────────────────────┐
│  이슈가 라벨을 따라 작업대를 이동 (각 작업대 = AI 에이전트 1명)      │
│                                                                    │
│  stage:plan-review ──► stage:impl ──► stage:qa ──► close            │
│   (plan-reviewer)      (backend/       (qa)                         │
│                         frontend/                                   │
│                         designer/                                   │
│                         infra)                                      │
│                                                                    │
│         ▲                              │                            │
│         └──────── QA 반려 시 되돌림 ────┘ (stage:impl + blocked)     │
└──────────────────────────────────────────────────────────────────┘
```

- 각 에이전트는 **자기 큐(라벨 조합)를 반복 조회**하다가 이슈가 오면 처리한다.
- 단계 시작·완료는 모두 **이슈 댓글로 로그**를 남긴다(`issue-log.sh`).
- 브랜치·머지·close는 **훅(hook)으로 강제 통제**되어, 각 역할이 남의 영역을 건드릴 수 없다.

---

## 폴더 / 파일 구조

```
agent-base/
├── CLAUDE.md                  ★ 팀 작업 규약(가장 중요). 모든 규칙의 원본.
├── 요건.md                     사람이 적는 프로젝트 요구사항 예시(입력물)
├── README.md                  이 문서
│
├── .claude/
│   ├── settings.json          Claude Code 설정: 에이전트 팀 on, 권한 허용목록, 훅 등록, 샌드박스
│   ├── agents/                역할별 에이전트 정의(누가·무엇을·어떻게)
│   │   ├── plan-reviewer.md      플랜/설계 검토 (코드 수정 X, 읽기만)
│   │   ├── backend.md            백엔드 구현·테스트 (TDD 필수)
│   │   ├── frontend.md           프론트엔드 구현·테스트 (TDD 필수)
│   │   ├── designer.md           디자인 스펙/에셋 (TDD 비대상)
│   │   ├── infra.md              IaC·배포·CI 설정 (드라이런까지, 실제 apply X)
│   │   └── qa.md                 최종 검증·머지·close 담당
│   ├── hooks/                 명령 실행 직전에 끼어들어 규칙 위반을 "차단"하는 가드
│   │   ├── guard-branch.sh       git 브랜치 접근 제한(자기 브랜치·dev만)
│   │   └── guard-close.sh        필수 단계 완료 전 이슈 close 차단
│   └── worktrees/            (실행 중 생성) 역할별 git worktree 작업 폴더
│       ├── backend/  frontend/  design/  infra/  qa/
│
└── scripts/                  파이프라인을 굴리는 자동화 스크립트
    ├── setup-labels.sh          필요한 라벨 일괄 생성(area:*, stage:*, blocked ...)
    ├── plan-to-issues.sh        todos.txt → GitHub 이슈 대량 생성(의존성 잠금 포함)
    ├── start-branch.sh          역할 워크트리에 dev 기준 feature 브랜치 준비
    ├── issue-log.sh             단계 시작/완료를 이슈 댓글로 기록(+ close 게이트용 숨은 마커)
    ├── qa-checkout.sh           QA 워크트리에 PR 브랜치를 detached 체크아웃
    ├── unblock-dependents.sh    선행 이슈 완료 시, 대기 중이던 후속 이슈 잠금 해제
    └── link-project-status.sh   GitHub Projects 보드의 Status 컬럼을 라벨과 자동 동기화
```

---

## 등장 인물(역할별 에이전트)

`.claude/agents/*.md` 로 정의된다. 각 파일은 프론트매터(name·model·tools)와 지침으로 구성되며,
모두 `model: sonnet` 을 쓰고 CLAUDE.md 의 해당 절차를 따른다.

| 역할 | 담당 큐(라벨) | 하는 일 | 코드 수정 |
|------|--------------|---------|:--------:|
| **plan-reviewer** | `stage:plan-review` | 구현 전 접근방식·아키텍처·범위 점검. 통과 시 `stage:impl` 로 넘김 | ✗ (읽기만) |
| **backend** | `area:backend` + `stage:impl` | TDD로 백엔드 구현→PR→`stage:qa` 인계 | ✓ |
| **frontend** | `area:frontend` + `stage:impl` | TDD로 UI/클라이언트 구현→PR→`stage:qa` 인계 | ✓ |
| **designer** | `area:design` + `stage:impl` | 디자인 스펙/에셋 산출→디자인 리뷰→PR | ✓(문서/에셋) |
| **infra** | `area:infra` + `stage:impl` | IaC·CI 작성 + 드라이런 검증(실제 apply는 안 함) | ✓ |
| **qa** | `stage:qa` | PR을 실제로 돌려 검증 후 `dev`에 머지·이슈 close. 실패 시 반려 | ✗ (읽기만) |

> backend·frontend는 **TDD 필수**: 실패 테스트(Red) → 최소 구현(Green) → 전체 통과(refactor) 순서를 지켜야 한다.

---

## 라벨 상태머신

이슈 하나는 항상 딱 하나의 `stage:*` 라벨과 하나의 `area:*` 라벨을 가진다.

```
[생성] area:<역할> + stage:plan-review
   │
   ├─ plan-reviewer 통과  → stage:plan-review 제거, stage:impl 추가
   │
   ├─ 담당 역할 구현·PR   → stage:impl 제거, stage:qa 추가
   │
   ├─ qa 통과            → 머지 후 이슈 close
   │
   └─ qa 반려            → stage:qa 제거, stage:impl + blocked 추가 (담당에게 되돌림)
```

라벨 목록(`setup-labels.sh` 가 생성):
`area:backend/frontend/design/infra`, `stage:plan-review/impl/qa`, `blocked`(QA 반려), `blocked-by-design`(선행 이슈 대기 잠금).

---

## 브랜치 전략 (dev 기반 · 역할별 워크트리)

- 베이스 브랜치는 **`dev`**. 모든 feature 브랜치는 `dev`에서 갈라져 `dev`로만 머지된다(`main`은 건드리지 않음).
- 브랜치 이름: `feature/<역할>-<이슈번호>` (예: `feature/backend-42`).
- 역할마다 **전용 워크트리**(`.claude/worktrees/<역할>/`)를 쓴다. 서로 폴더를 공유하지 않아 병렬 작업이 충돌 없이 굴러간다.
- QA는 PR 브랜치를 **detached HEAD**로만 체크아웃해 검증한다(직접 push·브랜치 생성 금지).

---

## 안전장치(훅)

Claude Code의 `PreToolUse` 훅으로, 위험한 명령은 **실행되기 전에** 막힌다(에이전트가 실수하거나
지시를 잘못 이해해도 강제로 차단).

- **`guard-branch.sh`** — `git checkout/switch/push/merge/branch` 명령을 가로채,
  현재 워크트리(=역할)가 **자기 `feature/<역할>-<n>` 브랜치와 `dev`** 외의 브랜치를 건드리면 차단.
  force push 금지, merge 대상은 `dev`만 허용, QA 워크트리의 push/branch 금지 등도 여기서 강제한다.
- **`guard-close.sh`** — `gh issue close` 시 이슈 댓글에 필요한 단계 완료 마커
  (`plan-review → (test-plan) → implement → test → qa`)가 모두 있는지 검사하고, 빠지면 close를 차단.
  backend/frontend 이슈는 TDD라서 `test-plan` 단계까지 요구한다.

이 마커는 `issue-log.sh` 가 이슈 댓글 끝에 숨겨두는 `<!-- STAGE:<단계>:<start|done> -->` 주석이다.

---

## 자동화 스크립트 요약

| 스크립트 | 용도 |
|---------|------|
| `setup-labels.sh` | 파이프라인에 필요한 라벨을 저장소에 일괄 생성(이미 있으면 건너뜀) |
| `plan-to-issues.sh <file>` | `역할\|제목\|본문\|key\|depends_on` 형식 목록을 읽어 이슈를 대량 생성. `depends_on` 이 있으면 `blocked-by-design` 으로 잠가서 만든다 |
| `start-branch.sh <역할> <n>` | 역할 워크트리에 `dev` 기준 `feature/<역할>-<n>` 브랜치를 새로 준비 |
| `issue-log.sh <n> <단계> <start\|done> [note]` | 단계 진행 상황을 이슈 댓글로 기록(+ close 게이트용 숨은 마커 삽입) |
| `qa-checkout.sh <브랜치>` | QA 워크트리에 해당 PR 브랜치를 detached로 체크아웃 |
| `unblock-dependents.sh <n>` | 방금 close된 이슈를 기다리던 `blocked-by-design` 이슈를 찾아 `stage:plan-review` 로 풀어줌 |
| `link-project-status.sh <프로젝트번호>` | GitHub Projects 보드의 Status 컬럼(Backlog/Ready/In progress/In review/Done)을 라벨·close 상태에 맞춰 자동 이동시키는 워크플로우 생성 |

---

## 이 프로젝트를 시작하는 순서(개략)

1. GitHub 저장소를 준비하고 `dev` 브랜치를 원격에 만들어 둔다.
2. `./scripts/setup-labels.sh` 로 라벨을 만든다.
3. `요건.md` 처럼 요구사항을 정리한 뒤, 작업을 `todos.txt`(`역할|제목|본문|key|depends_on`)로 쪼갠다.
4. `./scripts/plan-to-issues.sh todos.txt` 로 이슈를 생성한다 → 각 이슈가 `stage:plan-review` 큐에 들어간다.
5. Claude Code에서 에이전트 팀을 실행하면, 각 역할이 자기 큐를 돌며 이슈를 컨베이어 벨트처럼 흘려보낸다.
6. (선택) `./scripts/link-project-status.sh <번호>` 로 GitHub Projects 보드와 자동 동기화한다.

> 자세한 규칙·각 역할의 정확한 절차·예외 처리는 **`CLAUDE.md`** 에 모두 정의되어 있다.
> `요건.md` 는 "이런 요구사항이 들어온다"는 입력 예시(개인 블로그 구축)일 뿐이며, 이 base 자체의 기능이 아니다.

---

## 필요 조건

- **Claude Code** (에이전트 팀 기능: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` — `.claude/settings.json` 에 설정됨)
- **`gh`** (GitHub CLI, 인증 완료) · **`git`** (worktree 지원) · **`jq`** · **bash**
