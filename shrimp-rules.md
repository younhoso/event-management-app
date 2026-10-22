# Development Guidelines

> AI Agent 전용. 일반 개발 지식은 적지 않는다. 요구사항 기준은 `docs/PRD.md`, 일정·완료 기준은 `docs/ROADMAP.md`. 둘과 코드가 다르면 **임의로 맞추지 말고 사용자에게 보고**한다.

## 1. Project Overview

- 모임 이벤트 관리 웹 MVP: 공지 · 참석 응답(RSVP) · 카풀 · N빵 정산.
- 스택: Next.js 14 (App Router) + Supabase + Tailwind 3 + shadcn/ui(base-nova) + zod + react-hook-form + sonner.
- 현재 상태: 기획·스키마 단계. 이벤트 기능 코드는 없다. `frontend/`는 스타터 상태.
- **MVP 대상은 `frontend/`뿐. `admin/`은 수정하지 않는다.** (예외: 3절 버전 동기화)
- 주최자 = Supabase Auth(카카오) 로그인. 참여자 = 비로그인(이름 + 쿠키 토큰).

## 2. Project Architecture

| 경로 | 역할 | 규칙 |
|---|---|---|
| `frontend/src/app/` | 라우트 | 참여자 페이지·Route Handler는 `/e/[shareCode]/...` 아래에만 둔다 |
| `frontend/src/lib/supabase/` | `client.ts` `server.ts` `middleware.ts` | 서비스 롤은 신규 `admin.ts`에만 둔다 |
| `frontend/src/lib/participant/` | 신규: `verify.ts`, `withParticipant.ts` | 참여자 인증은 여기로만 모은다 |
| `frontend/src/lib/errors.ts` | 신규: DB 예외 코드 → 사용자 메시지 | 코드 문자열 하드코딩 금지, 여기서만 매핑 |
| `frontend/src/types/db.types.ts` | 신규: 테이블 Row/Insert 타입 | `schema.sql` 변경 시 갱신 |
| `frontend/src/store/`, `lib/axios/` | 기존 Recoil/Axios | **확장 금지** (유지보수만) |
| `supabase/schema.sql` | DB 스키마·RLS·트리거 | 아직 어떤 DB에도 실행되지 않음 |
| `docs/` | PRD, ROADMAP, 디자인 토큰 | `docs/design.shadcn.md`가 토큰 기준(소문자 파일명) |
| `.claude/` | 에이전트·스킬·훅 설정 | 기능 작업 중 수정하지 않는다 |

## 3. Code Standards

- 응답·주석·문서·커밋 메시지는 한국어. 식별자·기술 용어는 원문.
- import 경로는 `@/` 별칭(`./src/*`)을 쓴다. 상대경로 `../../` 금지.
- shadcn 컴포넌트는 `npx shadcn@latest add <name>`(frontend 디렉터리)으로 추가한다. `components/ui/`를 손으로 새로 만들지 않는다.
- 금액은 정수(원)만. `number` 부동소수점 연산·`toFixed` 금지.
- 일시는 KST 기준 표시(`date-fns`, Phase 1에서 추가).
- 의존성은 **그 기능을 구현하는 시점에** 추가한다. 미리 설치하지 않는다.
- **버전 동기화**: `next`, `@supabase/ssr`, `zod` 등을 올릴 때(특히 보안 패치) `frontend/package.json`과 `admin/package.json`을 같이 올린다. 현재 드리프트: next 14.2.35 vs 14.2.3, @supabase/ssr 0.10 vs 0.5, zod 4 vs 3.
- 린트: `frontend`에서 `npm run lint`. prettier 설정은 frontend에 없다 (PostToolUse 훅이 자동 실행).

## 4. Functionality Implementation Standards

### 4.1 서버 로직

- 신규 기능은 **Server Action 중심**. 클라이언트 fetch·Axios·Recoil atom을 새로 만들지 않는다.
- 서버 전용 모듈에는 첫 줄에 `import 'server-only'`를 둔다.
- 참여자 액션은 **반드시** `withParticipant` 래퍼를 경유한다.

```ts
// ✅ 행위자 ID는 토큰에서만 도출, 전달된 ID는 event_id 재검증
export const requestRide = withParticipant(async ({ participant, event }, rideId) => { ... })

// ❌ 클라이언트가 보낸 participantId를 그대로 신뢰
export async function requestRide(participantId: string, rideId: string) { ... }
```

### 4.2 참여자 접근(비로그인) 흐름

`share_code` → 이벤트 조회 → 쿠키 `pt_<shareCode>` 평문 토큰 → **sha256** → `participants.participant_token_hash` 비교 → `participant.event_id === event.id` 확인 → 서비스 롤로 처리.

- 쿠키: httpOnly, Secure, SameSite=Lax, path `/e/<shareCode>`, 1년. 토큰은 32바이트 이상 `crypto` 난수.
- DB에는 해시만 저장한다. 평문 저장·로그 출력 금지.
- 로그인한 주최자(`auth.uid() = events.host_id`)는 토큰 없이 해당 이벤트의 `is_host` 참여자 행으로 인정한다. 해시는 null 유지.
- `/e/[code]` 코드는 대문자 정규화(308)한다. `frontend/src/middleware.ts`에서 처리(쿠키 path와 일치시키기 위함).

### 4.3 서비스 롤 조회

```ts
// ✅ 컬럼 명시 + event_id 필터
admin.from('participants').select('id, name, status').eq('event_id', event.id)

// ❌
admin.from('participants').select('*')
```

- 공개 명단은 `name` / `status` / `guests_count`만 반환한다. 전화번호·토큰 해시·주최자 이메일은 응답·RSC payload에 넣지 않는다.
- 주최자 브라우저 클라이언트도 `participants`에 `select('*')` / `returning *` 금지 (해시 컬럼 권한 없음 → 권한 에러).

### 4.4 DB 불변식은 앱에서 재구현하지 않는다

정원·대기열(FIFO 승격)·카풀 좌석 초과·이벤트 상태 가드·정산 스냅샷은 `supabase/schema.sql` 트리거가 강제한다.

- ✅ 트리거 예외를 잡아 `lib/errors.ts`로 메시지 매핑.
- ❌ 앱 코드에서 "정원 초과면 waitlisted로 바꾼다" 같은 로직 복제.
- 예외: 1 + 동반 인원이 정원보다 큰 RSVP는 DB가 대기로 저장해 대기열을 막으므로 **폼에서 먼저 검증**한다.

### 4.5 DB 에러 코드 (전부 `lib/errors.ts`에 매핑)

`event_not_open` · `rsvp_capacity_exceeded` · `carpool_seats_full` · `carpool_self_request` · `carpool_already_confirmed` · `carpool_participant_event_mismatch` · `carpool_seats_below_confirmed` · `carpool_requires_rsvp_yes` · `carpool_ride_not_found` · `share_code_generation_failed`

### 4.6 쓰기 경로와 교착

- 트리거는 `events` 행만 잠근다. 행을 직접 update하면 `행 → events` 순서가 되어 교착(`40P01`) 가능.
- RSVP·카풀 확정·정원 변경은 **events를 먼저 `for update`로 잠그는 RPC 한 곳**으로 모은다.
- `40P01` 발생 시 1~2회 재시도한다.

### 4.7 정산 (PRD 5.4)

- 모든 지출은 주최자 단일 결제. `paid_by_participant_id`는 메모용.
- `unit = floor(총액 / Σshares)`, shares = 본인 1 + 동반. `amount_due = unit × shares`.
- 나머지 원은 **주최자가 흡수**. 불변식: `Σ참여자 amount_due + 주최자 몫 + 나머지 = 총액` (assert).
- 정산 대상 인원 0 또는 총액 0이면 확정 불가.
- 확정 시 `shares`·`amount_due`·`confirmed_at` 스냅샷. 이후 RSVP 변경은 "재계산" 클릭 시에만 반영. 재계산은 `amount_paid` 보존.

## 5. Framework / Library Usage Standards

- **Supabase 클라이언트 선택**: Server Component·Action → `lib/supabase/server.ts`, 브라우저 → `client.ts`, 참여자 처리 → `admin.ts`(server-only).
- `SUPABASE_SERVICE_ROLE_KEY`에 `NEXT_PUBLIC_` 접두사 금지. 빌드 결과에 키가 없는지 grep으로 확인한다.
- 폼: `react-hook-form` + `zod` + `@hookform/resolvers`. 토스트: `sonner`.
- `'use client'`는 상호작용이 필요한 말단 컴포넌트에만 붙인다.
- `.env*`는 읽지도 수정하지도 않는다. 필요한 변수 이름은 `*.env.example`로 확인한다.

## 6. Workflow Standards

1. `docs/PRD.md` · `docs/ROADMAP.md`에서 해당 Phase 태스크와 완료 기준을 확인한다.
2. Phase 순서: P0(스키마·서버 유틸) → P1(로그인·이벤트·공지) → P2(RSVP) → P3(카풀)/P4(정산, 병렬 가능) → P5(QA·배포).
3. 구현 후 `frontend`에서 `npm run lint` 및 `npm run build`.
4. API·비즈니스 로직이 있는 Phase는 **Playwright MCP 시나리오 테스트**를 함께 작성한다 (테스트 러너 없음).
5. 완료한 태스크는 `docs/ROADMAP.md` 체크박스를 갱신한다.
6. 커밋 전 `code-reviewer` 에이전트로 리뷰해 **APPROVED**를 받는다. 형식은 한국어 + 이모지 컨벤셔널(`.claude/skills/git-commit`). 관심사별(문서/스키마/설정/앱 코드)로 나눠 커밋한다.

## 7. Key File Interaction Standards (동시 수정 표)

| 수정 대상 | 함께 수정할 것 |
|---|---|
| 스키마 변경(컬럼 추가 등) | `supabase/`에 **번호 붙인 새 SQL 파일**(`create table if not exists`는 기존 컬럼을 바꾸지 못함) + `frontend/src/types/db.types.ts` + `docs/PRD.md` 6장 + `docs/ROADMAP.md` |
| 새 테이블 | `enable row level security` + `revoke all ... from anon` + 필요한 `authenticated` 정책(`is_event_host(event_id)` 헬퍼, `carpool_requests`는 `is_ride_host(ride_id)`) |
| DB 에러 코드 추가·변경 | `supabase/schema.sql` 트리거 + `docs/ROADMAP.md` 에러 코드 표 + `frontend/src/lib/errors.ts` |
| 의존성 버전 상향 | `frontend/package.json` + `admin/package.json` + `docs/TECH-STACK-PRIORITY.md` |
| 보호 라우트 변경 | `frontend/src/lib/supabase/middleware.ts#updateSession` + `docs/ROADMAP.md` + `README.md`의 `/dashboard` 보호 설명 |
| 디자인 토큰 변경 | `docs/design.shadcn.md` + `frontend/src/app/globals.css` + `frontend/tailwind.config.ts` |
| 프로젝트 규칙 변경 | `.claude/rules.md`(**50줄 이내**) / 구조·아키텍처는 `CLAUDE.md` / 상세는 이 파일 |

- `supabase/schema.sql`은 **Supabase 대시보드 SQL Editor에서 직접 실행**한다. CLI 마이그레이션은 쓰지 않는다. 실행한 SQL은 파일로 보관하고 실행 일자를 기록한다.
- MCP `supabase`의 `apply_migration` / `execute_sql`로 운영 DB를 바꾸기 전에는 반드시 사용자 확인을 받는다.

## 8. AI Decision-making Standards

```
요청이 참여자(비로그인) 동작인가?
├─ 예 → withParticipant + 서비스 롤(admin.ts) + 컬럼 명시. anon 정책은 추가하지 않는다.
└─ 아니오 (주최자 동작) → 로그인 세션 + RLS(events.host_id = auth.uid()). 서비스 롤 사용 금지.

규칙을 앱에 구현하려는가? (정원·좌석·상태·정산 스냅샷)
├─ schema.sql 트리거에 이미 있음 → 구현하지 않는다. 에러 코드만 매핑.
└─ 트리거에 없음 → 사용자에게 보고하고 SQL 변경 파일을 제안한다.

문서와 코드가 다른가? → 임의 수정 금지, 차이를 보고하고 기준(PRD/ROADMAP)을 확인한다.
admin/ 수정이 필요해 보이는가? → 버전 동기화 외에는 하지 않는다.
```

우선순위: 보안 규칙(1순위) > DB 불변식 > PRD/ROADMAP 완료 기준 > 코드 편의.

## 9. Known Pitfalls (코드만 읽어서는 안 보이는 것)

- `frontend/src/middleware.ts`는 세션 쿠키만 갱신하고 **리다이렉트하지 않는다**. `/dashboard`는 현재 보호되지 않는다. `/login`, `/auth/callback`도 없다.
- `admin/middleware.ts`는 앱 루트에 있으나 앱은 `src/app`을 쓴다. 인식 여부가 **검증되지 않았다**. admin 인증에 의존하지 않는다.
- Supabase 폴더명이 다르다: frontend `lib/supabase/`, admin `libs/supabase/`.
- `.claude/settings.json`: Notification/Stop 훅이 가리키는 `.claude/hooks/*.sh`가 **없다**. PostToolUse는 편집 파일에 `npx prettier --write`를 실행한다. PreToolUse는 `.env*`·`config/*.{yaml,yml,json}` 접근을 차단한다.
- `.husky/pre-commit`은 존재하지 않는 `main/`, `lint-staged`, `yarn test`를 참조하고 `core.hooksPath`도 미설정이라 동작하지 않는다. `.husky/pre-push`는 `master|dev|prod` 커밋만 막는다.
- 기본 권한 모드는 `plan`, 출력 스타일은 `Explanatory`.

## 10. Prohibited Actions

- ❌ `anon` 역할에 신규 테이블 권한·정책 부여
- ❌ 평문 참여자 토큰의 DB 저장·로그 출력
- ❌ `SUPABASE_SERVICE_ROLE_KEY`에 `NEXT_PUBLIC_` 접두사, 또는 `server-only` 아닌 모듈에서 서비스 롤 사용
- ❌ 서비스 롤·`participants` 조회에 `select('*')`, `event_id` 필터 누락
- ❌ 클라이언트가 보낸 `participantId` / `rideId` / `settlementId`를 `event_id` 재검증 없이 사용
- ❌ 트리거가 강제하는 불변식의 앱 측 재구현
- ❌ Recoil atom·Axios 호출 신규 추가
- ❌ `.env*` 읽기·수정
- ❌ 정산 금액에 부동소수점 사용, 나머지 원을 참여자에게 분배
- ❌ `code-reviewer` APPROVED 없는 커밋
- ❌ 기능 구현 전 의존성 선설치
