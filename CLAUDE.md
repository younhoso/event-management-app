# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 상태

모임 이벤트 관리 웹 MVP(공지·참석 응답·카풀·N빵 정산). **기획·스키마 단계이며 이벤트 기능 코드는 아직 없다.** `frontend/`와 `admin/`은 Next.js 14 + Supabase 스타터 상태다. 구현 전에 아래 문서를 먼저 읽는다.

- `docs/PRD.md` — 요구사항·데이터 모델·보안 설계 (기준 문서)
- `docs/ROADMAP.md` — Phase 0~5 태스크, 확정 사항, 공통 원칙, 에러 코드 표
- `docs/LEANCANVAS.md` — 사업 가설 (🟡는 근거 없는 추정)
- `supabase/schema.sql` — DB 스키마·RLS·트리거 (**아직 어떤 DB에도 실행되지 않음**)
- `docs/TECH-STACK-PRIORITY.md` — 의존성은 기능 구현 시점에 추가, 형제 앱과 버전을 맞춘다
- `docs/design.shadcn.md` 외 `docs/01~09-*.md` — 디자인 시스템 템플릿 (파일명은 소문자 `design.shadcn.md`)

MVP 대상 앱은 **`frontend/`뿐**이고 `admin/`은 범위 밖이다.

## 명령어

루트에 `package.json`이 없다. 각 앱 디렉터리에서 실행한다. (`README`는 npm 기준, lockfile은 커밋되어 있지 않다.)

| | frontend (포트 3000) | admin (포트 3001) |
|---|---|---|
| 개발 | `npm run dev` | `npm run dev` |
| 빌드 | `npm run build` | `npm run build` |
| 린트 | `npm run lint` | `npm run lint` |
| 포맷 | (prettier 설정 없음) | `npm run pretty` |

- **테스트 러너가 없다.** 단일 테스트 실행 명령도 없다. ROADMAP은 Phase마다 Playwright MCP 시나리오 테스트를 쓰도록 계획한다.
- 환경변수: 각 앱의 `.env.local`에 `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`. `.claude/settings.json`이 `.env*` 읽기를 거부한다.

## 아키텍처

### 두 앱의 인증은 구현 수준이 다르다
- **frontend**: `src/middleware.ts` → `lib/supabase/middleware.ts#updateSession`은 **세션 쿠키만 갱신하고 리다이렉트하지 않는다.** `README`는 `/dashboard`가 보호된다고 쓰여 있지만 실제 보호 로직은 없다(ROADMAP Phase 1에서 구현). `/login`, `/auth/callback`도 없다.
- **admin**: 미들웨어가 비로그인 시 `/sign/in`으로 리다이렉트한다(공개: `/sign/in`, `/sign/up`, `/auth/callback`). 단 파일이 `admin/middleware.ts`(앱 루트)에 있는데 앱은 `src/app`을 쓴다. Next.js가 `src/` 사용 시 루트 미들웨어를 인식하는지는 **검증되지 않았다.** 이 앱에 의존하기 전에 확인한다.
- 서버/클라이언트 Supabase 클라이언트는 각각 `frontend/src/lib/supabase/`, `admin/src/libs/supabase/`(폴더명이 `lib` vs `libs`로 다르다).

### frontend 클라이언트 상태 (여러 파일에 걸침)
`app/layout.tsx` → `RecoilProvider` → `AuthProvider`가 `onAuthStateChange`를 구독해 Recoil atoms(`store/atoms/authAtom`, `userAtom`)에 세션·`profiles` 행을 동기화한다. `lib/axios/interceptors.ts`는 요청마다 세션 토큰을 주입하고 401이면 `refreshSession` 후 재시도, 실패 시 `/login`으로 보낸다. **신규 기능은 Server Action 중심으로 만들고 Recoil/Axios를 늘리지 않는다**(ROADMAP 방침).

### 참여자(비로그인) 보안 모델 — 코드만 읽어서는 보이지 않는 설계
- 참여자는 로그인하지 않는다. `anon`에는 신규 테이블 권한과 정책이 **0개**다.
- 서버(Server Action/Route Handler)가 `share_code`로 이벤트를 찾고, httpOnly 쿠키의 평문 토큰을 **sha256**으로 해시해 `participants.participant_token_hash`와 비교한 뒤 **서비스 롤**로 접근한다. 평문 토큰은 DB에 저장하지 않는다.
- 서비스 롤 키는 `import 'server-only'` 모듈에서만 쓰고 `NEXT_PUBLIC_` 접두사를 붙이지 않는다. 서비스 롤 조회는 `select('*')` 금지, 컬럼 명시 + `event_id` 필터.
- 주최자(로그인)는 RLS(`events.host_id = auth.uid()`)로 접근한다. 주최자 브라우저 클라이언트도 `participants`에 `select('*')`를 쓰면 권한 에러가 난다(해시 컬럼 단위 권한 제한).
- 참여자 액션은 공통 래퍼(`withParticipant`, 미구현)를 거치고 행위자 ID는 항상 토큰에서만 도출한다. 로그인한 주최자는 토큰 없이 `is_host` 참여자 행으로 인정한다.

### DB가 불변식을 강제한다
정원·대기열(FIFO 승격), 카풀 좌석 초과 방지, 이벤트 상태 가드(`closed`/`canceled`에서 RSVP·카풀 쓰기 차단), 정산 스냅샷은 앱이 아니라 `supabase/schema.sql`의 **트리거**가 처리한다. 앱에서 같은 규칙을 다시 구현하지 말고, 트리거가 던지는 예외 코드(`event_not_open`, `carpool_seats_full`, `rsvp_capacity_exceeded` 등, 전체 목록은 ROADMAP 에러 코드 표)를 `lib/errors.ts`에서 사용자 메시지로 매핑한다.

- 스키마는 Supabase 대시보드 **SQL Editor**에서 직접 실행하고 로컬 CLI 마이그레이션은 쓰지 않는다. `create table if not exists`는 기존 테이블 컬럼을 바꾸지 않으므로 변경은 `supabase/`에 번호 붙인 별도 SQL 파일로 추가한다.
- 새 테이블은 반드시 `enable row level security` + `revoke all ... from anon`을 함께 실행한다.
- 교착 가능성: 트리거는 `events` 행만 잠그지만 행을 직접 update하는 경로는 `행 → events` 순서가 된다. 쓰기는 events를 먼저 잠그는 RPC로 모으고 `40P01`은 1~2회 재시도한다.

### 정산 규칙 (PRD 5.4)
모든 지출은 주최자 단일 결제로 간주(결제자 필드는 메모용). `unit = floor(총액 / Σshares)`, 나머지 원은 주최자가 흡수, 정산 대상 인원 0 또는 총액 0이면 확정 불가. 금액은 정수(원)만 쓴다.

### 버전 드리프트
두 앱의 의존성 버전이 다르다: `next` 14.2.35(frontend) vs 14.2.3(admin), `@supabase/ssr` 0.10 vs 0.5, `zod` 4 vs 3. 보안 패치로 한쪽을 올리면 다른 쪽도 같이 올린다(`docs/TECH-STACK-PRIORITY.md`).

## 저장소 도구 주의

- **`.claude/settings.json`의 훅 일부는 깨져 있다.** Notification/Stop이 `.claude/hooks/*.sh`를 가리키지만 파일이 없다. PostToolUse는 편집한 파일에 `npx prettier --write`를 실행한다.
- SessionStart/PreCompact 훅은 `.claude/rules.md`를 읽는다(PreCompact는 앞 50줄만). 지켜야 할 규칙은 거기에 두고 50줄 이내로 유지한다. 구조·아키텍처 설명은 이 파일(`CLAUDE.md`)에 둔다.
- `.husky/pre-commit`은 이 저장소에 없는 `main/`, `lint-staged`, `yarn test`를 참조하고 `core.hooksPath`도 설정되어 있지 않아 사실상 동작하지 않는다. `.husky/pre-push`는 `master|dev|prod` 브랜치 커밋만 막는다(`main`은 허용).
- **커밋 전에 `code-reviewer` 에이전트로 리뷰하고 APPROVED를 받는다**(`.claude/agents/`). 커밋 메시지는 한국어 + 이모지 컨벤셔널 형식(`.claude/skills/git-commit`).
- `.claude/settings.json`: 기본 모드 `plan`, 출력 스타일 `Explanatory`, 응답·문서는 한국어.
